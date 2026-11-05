#version 140

// DoF fast path, step 4: the gather. The math is the same as in dof_present.fp
// (scatter-as-gather, 5 depth layers, back-to-front compositing); only the data
// sources and the number of samples iterated differ. Details in dof_fast_common.glsl.
// Writes tone-mapped color to the screen, or HDR for dof_temporal.fp when accumulation is on.

uniform sampler2D u_source_sampler;
uniform sampler2D u_tiles_sampler;

in vec2 var_texcoord0;

out vec4 color_out;

#include "/shaders/dof_fast_common.glsl"

// Unfiltered depth: the same texel that the nearest-neighbor sample read in dof_present.
float load_scene_depth(vec2 uv, vec2 size) {
  return fetch_texel(u_source_sampler, floor(uv * size), size).a;
}

// Color with hardware bilinear filtering: dof_present did the same thing by hand
// from four unpacked texels.
vec3 load_scene_color(vec2 uv) {
  return texture(u_source_sampler, uv).rgb;
}

bool is_temporal() {
  return u_temporal.x > 0.5;
}

// With temporal accumulation HDR is written for dof_temporal.fp (which tone maps later);
// without it the pixel goes straight to the screen.
vec4 dof_output(vec3 hdr) {
  if (is_temporal()) {
    return vec4(hdr, 1.0);
  }
  return vec4(tone_mapping_aces(hdr, u_tonemap.x), 1.0);
}

void main() {
  vec2 size = get_full_size();
  int sample_count = clamp(int(u_dof_sampling.y + 0.5), 1, DOF_MAX_SAMPLES);
  float max_radius_px = max(u_dof_focus.w, 0.5);

  vec3 pixel_color = load_scene_color(var_texcoord0);
  float pixel_depth = load_scene_depth(var_texcoord0, size);

  // Same kernel as in dof_present: sample_count samples on a Fibonacci spiral over the full
  // radius, sample i's radius grows with i. A sample contributes only if it is closer than
  // its source's blur radius, which is no larger than the maximum over the neighboring tiles.
  // So the loop runs only over the samples inside that maximum; the rest would get zero
  // weight in the original formula. Positions, rotation and weights are unchanged.
  vec2 tile = floor(floor(var_texcoord0 * size) / get_tile_size());
  float encoded_radius = fetch_texel(u_tiles_sampler, tile, get_tiles_size()).r;
  float neighborhood_radius_px = min(decode_tile_radius(encoded_radius, max_radius_px), max_radius_px);

  // None of the neighbors is blurred: the original formula would return the pixel's own color.
  if (neighborhood_radius_px <= DOF_SOURCE_MIN_RADIUS_PX) {
    color_out = dof_output(pixel_color);
    return;
  }

  // Sample i's radius is at least R * sqrt(i / N) for any ring offset, so a contribution is
  // only possible for i < N * (r / R)^2. One extra sample of margin for rounding.
  float ratio = neighborhood_radius_px / max_radius_px;
  int active_sample_count = clamp(int(ceil(float(sample_count) * ratio * ratio)) + 1, 0, sample_count);

  float sample_boost = dof_sample_boost(max_radius_px, float(sample_count));
  float frame = u_dof_sampling.x;
  float angle = random_kernel_angle(gl_FragCoord.xy, frame);
  // With temporal accumulation the rings also slide within their area bands from frame to
  // frame, so the average converges to the integral over the whole disk instead of over a
  // fixed set of rings. Without accumulation they stay where dof_present has them.
  float ring_offset = is_temporal()
    ? fract(hash12(floor(gl_FragCoord.xy) + vec2(37.0, 17.0)) + frame * PLASTIC_RATIO_FRACT)
    : 0.5;

  float pixel_weight = dof_alpha_at_distance(compute_dof_radius(pixel_depth, u_dof_focus), 0.0);
  DofLayers layers = dof_layers_begin(pixel_color, pixel_weight);

  for (int i = 0; i < DOF_MAX_SAMPLES; ++i) {
    if (i >= active_sample_count) {
      break;
    }

    vec2 disk = rotate2(fibonacci_disk_sample(i, sample_count, ring_offset), angle);
    float dist_px = length(disk) * max_radius_px;
    if (dist_px < 0.5) {
      continue;
    }

    vec2 sample_uv = var_texcoord0 + disk * max_radius_px * u_full_texel.xy;
    float sample_depth = load_scene_depth(sample_uv, size);
    float sample_weight = dof_alpha_at_distance(compute_dof_radius(sample_depth, u_dof_focus), dist_px) * sample_boost;
    if (sample_weight <= 1e-5) {
      continue;
    }

    dof_layers_add(layers, load_scene_color(sample_uv), sample_weight, sample_depth - pixel_depth, u_dof_focus);
  }

  color_out = dof_output(dof_layers_resolve(layers, pixel_color));
}
