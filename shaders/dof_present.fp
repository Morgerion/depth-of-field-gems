#version 140

// Original single-pass depth of field, used when the device cannot render to RGBA16F (the
// fast path in dof_gather.fp computes the same result faster). Reads the RGBM-packed scene
// and hardware depth directly, gathers samples over the full kernel radius, sorts them into
// five depth layers relative to the pixel, composites the layers back to front and tone maps.

uniform sampler2D u_scene_sampler;
uniform sampler2D u_depth_sampler;

uniform fs_uniforms {
  // xy = 1 / size, zw = size of the scene target in pixels.
  vec4 u_full_texel;
  // See dof_common.glsl.
  vec4 u_dof_focus;
  // x = frame index (wrapping), y = kernel samples per pixel.
  vec4 u_dof_sampling;
  // x = exposure before tone mapping.
  vec4 u_tonemap;
  // x = near plane, y = far plane.
  vec4 u_camera_clip;
  mat4 u_inv_proj;
};

in vec2 var_texcoord0;

out vec4 color_out;

#include "/shaders/dof_common.glsl"

vec3 sample_hdr(sampler2D color_sampler, vec2 uv) {
  return unpack_hdr(texture(color_sampler, uv));
}

// Bilinear filtering by hand: RGBM-packed texels cannot be filtered by the hardware.
vec3 sample_hdr_bilinear(sampler2D color_sampler, vec2 uv, vec4 texel_info) {
  vec2 size = texel_info.zw;
  vec2 texel_pos = uv * size - 0.5;
  vec2 base = floor(texel_pos);
  vec2 frac_uv = fract(texel_pos);

  vec2 p00 = clamp(base, vec2(0.0), size - vec2(1.0));
  vec2 p10 = clamp(base + vec2(1.0, 0.0), vec2(0.0), size - vec2(1.0));
  vec2 p01 = clamp(base + vec2(0.0, 1.0), vec2(0.0), size - vec2(1.0));
  vec2 p11 = clamp(base + vec2(1.0, 1.0), vec2(0.0), size - vec2(1.0));

  vec3 c00 = sample_hdr(color_sampler, (p00 + vec2(0.5)) * texel_info.xy);
  vec3 c10 = sample_hdr(color_sampler, (p10 + vec2(0.5)) * texel_info.xy);
  vec3 c01 = sample_hdr(color_sampler, (p01 + vec2(0.5)) * texel_info.xy);
  vec3 c11 = sample_hdr(color_sampler, (p11 + vec2(0.5)) * texel_info.xy);

  return mix(mix(c00, c10, frac_uv.x), mix(c01, c11, frac_uv.x), frac_uv.y);
}

float load_scene_depth(vec2 uv) {
  return load_linear_depth(texture(u_depth_sampler, uv).r, uv, u_inv_proj, u_camera_clip.xy);
}

vec3 load_scene_color(vec2 uv) {
  return sample_hdr_bilinear(u_scene_sampler, uv, u_full_texel);
}

void main() {
  int sample_count = clamp(int(u_dof_sampling.y + 0.5), 1, DOF_MAX_SAMPLES);
  float max_radius_px = max(u_dof_focus.w, 0.5);
  float sample_boost = dof_sample_boost(max_radius_px, float(sample_count));
  float angle = random_kernel_angle(gl_FragCoord.xy, u_dof_sampling.x);

  vec3 pixel_color = load_scene_color(var_texcoord0);
  float pixel_depth = load_scene_depth(var_texcoord0);
  float pixel_weight = dof_alpha_at_distance(compute_dof_radius(pixel_depth, u_dof_focus), 0.0);
  DofLayers layers = dof_layers_begin(pixel_color, pixel_weight);

  for (int i = 0; i < DOF_MAX_SAMPLES; ++i) {
    if (i >= sample_count) {
      break;
    }

    vec2 disk = rotate2(fibonacci_disk_sample(i, sample_count, 0.5), angle);
    float dist_px = length(disk) * max_radius_px;
    if (dist_px < 0.5) {
      continue;
    }

    vec2 sample_uv = var_texcoord0 + disk * max_radius_px * u_full_texel.xy;
    float sample_depth = load_scene_depth(sample_uv);
    float sample_weight = dof_alpha_at_distance(compute_dof_radius(sample_depth, u_dof_focus), dist_px) * sample_boost;
    if (sample_weight <= 1e-5) {
      continue;
    }

    dof_layers_add(layers, load_scene_color(sample_uv), sample_weight, sample_depth - pixel_depth, u_dof_focus);
  }

  vec3 hdr = dof_layers_resolve(layers, pixel_color);
  color_out = vec4(tone_mapping_aces(hdr, u_tonemap.x), 1.0);
}
