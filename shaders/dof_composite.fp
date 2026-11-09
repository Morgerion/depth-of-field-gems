#version 140

// Half-resolution DoF, last step at full resolution: brings the half-resolution blur
// (dof_gather.fp in half-resolution mode) back to full size and restores the sharp detail.
//
// Upsampling is bilateral: the four half-resolution texels around a pixel are weighted
// bilinearly and by how close their depth is to the pixel's, so blur never leaks across the
// edge of something sharp. Where both the pixel and the texel are blurred by a few pixels the
// true image is smooth anyway, and the depth weight fades out: otherwise pixels next to the
// edge of a blurred object would take their blur from texels further away and show a step.
// The detail lost by the downsample is then added back:
//
//   result = blur + detail * (sharp - low)
//
// where `low` is the half-resolution scene upsampled with the same weights and `detail` is how
// much of the pixel itself is visible: 1 in focus, 0 once its own blur radius reaches a few
// pixels, and reduced by the blurred foreground layers that cover it (alpha of the blur).
// For an in-focus pixel behind a blurred edge this gives front + (1 - front alpha) * sharp,
// the same as the full-resolution layers would.
// Writes HDR for dof_temporal.fp when accumulation is on, tone-mapped color otherwise.

uniform sampler2D u_source_sampler;
uniform sampler2D u_half_source_sampler;
uniform sampler2D u_half_blur_sampler;

in vec2 var_texcoord0;

out vec4 color_out;

#include "/shaders/dof_fast_common.glsl"

// A pixel is fully sharp up to this own blur radius and fully taken from the half-resolution
// blur from DOF_DETAIL_FADE_END_PX on. The half-resolution gather treats sources below 1 half
// pixel (2 px) as sharp, so the fade covers that range.
const float DOF_DETAIL_FADE_START_PX = 1.0;
const float DOF_DETAIL_FADE_END_PX = 3.0;
// Depth difference, relative to the pixel's depth, at which a half-resolution texel counts as
// half as similar.
const float DOF_UPSAMPLE_DEPTH_TOLERANCE = 0.015;
// Below this total weight none of the texels lies on the pixel's surface.
const float DOF_UPSAMPLE_MIN_WEIGHT = 0.02;
// Blur radius of both the pixel and the texel over which the depth weight fades out.
const float DOF_UPSAMPLE_SMOOTH_START_PX = 2.0;
const float DOF_UPSAMPLE_SMOOTH_END_PX = 4.0;

vec4 dof_output(vec3 hdr) {
  if (u_temporal.x > 0.5) {
    return vec4(hdr, 1.0);
  }
  return vec4(tone_mapping_aces(hdr, u_tonemap.x), 1.0);
}

struct Upsample {
  vec4 blur;
  vec3 low;
  float weight;
};

void upsample_add(inout Upsample sum, vec2 half_texel, vec2 half_size, float spatial_weight,
                  float depth, float own_radius, float tolerance) {
  vec4 half_source = fetch_texel(u_half_source_sampler, half_texel, half_size);
  float depth_ratio = (half_source.a - depth) / tolerance;
  float both_blurred = smoothstep(DOF_UPSAMPLE_SMOOTH_START_PX, DOF_UPSAMPLE_SMOOTH_END_PX,
    min(own_radius, compute_dof_radius(half_source.a, u_dof_focus)));
  float weight = spatial_weight * mix(1.0 / (1.0 + depth_ratio * depth_ratio), 1.0, both_blurred);
  sum.blur += fetch_texel(u_half_blur_sampler, half_texel, half_size) * weight;
  sum.low += half_source.rgb * weight;
  sum.weight += weight;
}

void main() {
  vec2 size = get_full_size();
  vec2 half_size = ceil(size * 0.5);
  vec2 texel = floor(var_texcoord0 * size);
  vec4 source = fetch_texel(u_source_sampler, texel, size);
  float depth = source.a;

  // Pixel center in half-resolution texel space, and the bilinear footprint around it.
  vec2 half_position = (texel + vec2(0.5)) * 0.5 - vec2(0.5);
  vec2 half_base = floor(half_position);
  vec2 fraction = half_position - half_base;
  float tolerance = DOF_UPSAMPLE_DEPTH_TOLERANCE * depth + DOF_DEPTH_EPS;
  float own_radius = compute_dof_radius(depth, u_dof_focus);

  Upsample sum = Upsample(vec4(0.0), vec3(0.0), 0.0);
  for (int y = 0; y < 2; ++y) {
    for (int x = 0; x < 2; ++x) {
      vec2 offset = vec2(float(x), float(y));
      vec2 bilinear = mix(vec2(1.0) - fraction, fraction, offset);
      upsample_add(sum, half_base + offset, half_size, bilinear.x * bilinear.y, depth, own_radius, tolerance);
    }
  }

  // None of the four texels lies on this pixel's surface: a thin sliver next to a depth edge,
  // which the downsample gave to the nearer surface. Its own surface is then looked for one
  // texel further out, and if it is not there either, the plain bilinear blur is used.
  if (sum.weight < DOF_UPSAMPLE_MIN_WEIGHT) {
    sum = Upsample(vec4(0.0), vec3(0.0), 0.0);
    for (int y = -1; y < 3; ++y) {
      for (int x = -1; x < 3; ++x) {
        upsample_add(sum, half_base + vec2(float(x), float(y)), half_size, 1.0 / 16.0, depth, own_radius, tolerance);
      }
    }
  }
  if (sum.weight < DOF_UPSAMPLE_MIN_WEIGHT) {
    sum = Upsample(vec4(0.0), vec3(0.0), 0.0);
    for (int y = 0; y < 2; ++y) {
      for (int x = 0; x < 2; ++x) {
        vec2 offset = vec2(float(x), float(y));
        vec2 bilinear = mix(vec2(1.0) - fraction, fraction, offset);
        upsample_add(sum, half_base + offset, half_size, bilinear.x * bilinear.y, depth, own_radius, 1e6);
      }
    }
  }

  vec4 blur = sum.blur / sum.weight;
  vec3 low = sum.low / sum.weight;
  float detail = (1.0 - smoothstep(DOF_DETAIL_FADE_START_PX, DOF_DETAIL_FADE_END_PX, own_radius))
    * (1.0 - clamp(blur.a, 0.0, 1.0));
  vec3 hdr = max(blur.rgb + detail * (source.rgb - low), vec3(0.0));

  color_out = dof_output(hdr);
}
