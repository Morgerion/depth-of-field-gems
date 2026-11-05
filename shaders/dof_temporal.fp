#version 140

// DoF fast path, step 5 (when accumulation is enabled): blending with history.
//
// History stores the HDR DoF result (rgb) and the number of accumulated frames (a). While the
// image is static, every frame brings a new kernel rotation and ring offset and is blended
// with weight 1 / n: an exact average of the first frames, then an exponential moving average
// over about u_temporal_limits.x frames. No clamping is applied, so the result converges to
// the noise-free integral over the lens disk without bias.
//
// When the image changes (camera, focus or settings), history is clamped to a window
// (mean +- gamma * deviation) over the current frame's 3x3 neighborhood and the frame count
// is limited, so nothing trails behind. When the camera itself moved, history is first
// reprojected using the pixel's depth (the scene geometry is static).

uniform sampler2D u_current_sampler;
uniform sampler2D u_history_sampler;
uniform sampler2D u_source_sampler;

in vec2 var_texcoord0;

out vec4 color_out;

#include "/shaders/dof_fast_common.glsl"

// Where this pixel was on screen in the previous frame. The view-space position comes from
// the pixel's linear depth; for a perspective projection the diagonal of the inverse
// projection holds tan(fov / 2) * aspect and tan(fov / 2).
vec2 reproject(vec2 uv, float linear_depth) {
  vec2 ndc = uv * 2.0 - 1.0;
  vec3 view_position = vec3(
    ndc.x * u_inv_proj[0][0] * linear_depth,
    ndc.y * u_inv_proj[1][1] * linear_depth,
    -linear_depth
  );
  vec4 prev_clip = u_reproj * vec4(view_position, 1.0);
  return (prev_clip.xy / max(prev_clip.w, 1e-5)) * 0.5 + 0.5;
}

void main() {
  vec2 size = get_full_size();
  vec2 texel = floor(var_texcoord0 * size);
  vec3 current = fetch_texel(u_current_sampler, texel, size).rgb;

  // The image changed (camera or focus) -> clamping and a short history.
  // The camera itself moved -> reprojection. While the camera is still, history is read
  // exactly at its texel center, without bilinear blurring.
  bool image_changed = u_temporal.y > 0.5;
  bool camera_moved = u_temporal.z > 0.5;
  vec2 history_uv = var_texcoord0;

  if (camera_moved) {
    float linear_depth = fetch_texel(u_source_sampler, texel, size).a;
    history_uv = reproject(var_texcoord0, linear_depth);
  }

  bool history_valid = all(greaterThanEqual(history_uv, vec2(0.0))) && all(lessThanEqual(history_uv, vec2(1.0)));
  vec4 history = texture(u_history_sampler, history_uv);
  float history_frames = history_valid ? history.a : 0.0;

  if (image_changed && history_frames > 0.0) {
    vec3 mean = vec3(0.0);
    vec3 mean_sq = vec3(0.0);
    for (int y = -1; y <= 1; ++y) {
      for (int x = -1; x <= 1; ++x) {
        vec3 c = fetch_texel(u_current_sampler, texel + vec2(float(x), float(y)), size).rgb;
        mean += c;
        mean_sq += c * c;
      }
    }
    mean /= 9.0;
    vec3 deviation = sqrt(max(mean_sq / 9.0 - mean * mean, vec3(0.0)));
    vec3 corridor = deviation * max(u_temporal.w, 0.0);
    history.rgb = clamp(history.rgb, mean - corridor, mean + corridor);
    history_frames = min(history_frames, max(u_temporal_limits.y - 1.0, 0.0));
  }

  float max_frames = max(image_changed ? u_temporal_limits.y : u_temporal_limits.x, 1.0);
  float frames = min(history_frames + 1.0, max_frames);
  vec3 result = mix(history.rgb, current, 1.0 / frames);

  color_out = vec4(result, frames);
}
