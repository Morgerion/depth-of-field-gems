#ifndef DOF_COMMON_GLSL_H
#define DOF_COMMON_GLSL_H

// Depth of field math shared by the original single-pass DoF (dof_present.fp) and the
// fast path (dof_gather.fp and friends).
//
// Model: every pixel is a light source that spreads into a disk whose radius (the circle of
// confusion, "blur radius" below) grows linearly with the distance from the focus range.
// Inside that disk the source's energy falls off linearly from the center (a cone), and
// the cone is normalized so that its integral over the disk is 1.

#include "/shaders/hdr_common.glsl"

// Shared focus uniform of every DoF shader (u_dof_focus):
//   x = focus distance, y = sharp range on either side of it,
//   z = blur radius in pixels per unit of depth beyond the sharp range, w = maximum blur radius.

const float PI = 3.14159265359;
const float GOLDEN_ANGLE = 2.39996322973;
// Fractional parts of the golden ratio and of the plastic number: low-discrepancy
// sequences for per-frame kernel rotation and ring offsets.
const float GOLDEN_RATIO_FRACT = 0.61803398875;
const float PLASTIC_RATIO_FRACT = 0.75487766625;
// Sources with a blur radius at or below this are treated as perfectly sharp.
const float DOF_SOURCE_MIN_RADIUS_PX = 1.0;
// Tolerance when sorting samples into depth layers.
const float DOF_DEPTH_EPS = 0.001;
const int DOF_MAX_SAMPLES = 128;

// View-space depth (positive, in world units) from a hardware depth value.
float linearize_depth(float raw_depth, vec2 uv, mat4 inv_proj) {
  vec4 ndc = vec4(uv * 2.0 - 1.0, raw_depth * 2.0 - 1.0, 1.0);
  vec4 view = inv_proj * ndc;
  return -view.z / max(view.w, 1e-5);
}

// As linearize_depth, but empty pixels (cleared depth) are put at the far plane.
float load_linear_depth(float raw_depth, vec2 uv, mat4 inv_proj, vec2 camera_clip) {
  if (raw_depth >= 0.99999) {
    return camera_clip.y;
  }

  return linearize_depth(raw_depth, uv, inv_proj);
}

// Blur radius in pixels for a given depth (see u_dof_focus above).
float compute_dof_radius(float linear_depth, vec4 focus) {
  float defocus = max(abs(linear_depth - focus.x) - focus.y, 0.0);
  return min(defocus * focus.z, focus.w);
}

// Interleaved gradient noise: a per-pixel value in [0, 1) with a well-spread pattern.
float hash12(vec2 p) {
  return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

vec2 rotate2(vec2 p, float angle) {
  float s = sin(angle);
  float c = cos(angle);
  return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Kernel rotation for a pixel: spatially interleaved gradient noise, advanced every frame
// along the golden-ratio sequence so that consecutive frames fill each other's gaps.
float random_kernel_angle(vec2 frag_coord, float frame_index) {
  return PI * 2.0 * fract(hash12(floor(frag_coord)) + frame_index * GOLDEN_RATIO_FRACT);
}

// Sample `index` of `sample_count` on a Fibonacci spiral over the unit disk. Every sample
// stands for an equal-area ring band, and its radius sqrt((index + ring_offset) / sample_count)
// grows with the index. ring_offset = 0.5 puts it in the middle of its band; sweeping the
// offset over [0, 1) from frame to frame covers the whole disk instead of fixed rings.
vec2 fibonacci_disk_sample(int index, int sample_count, float ring_offset) {
  float count = float(sample_count);
  float radius = sqrt((float(index) + ring_offset) / count);
  float angle = (float(index) + 0.5) * GOLDEN_ANGLE;
  return vec2(cos(angle), sin(angle)) * radius;
}

// Linear falloff of a source with blur radius `radius_px` at distance `dist_px`: 1 at the
// center, 0 at the edge and beyond.
float dof_blur_shape(float radius_px, float dist_px) {
  if (radius_px <= 1e-4 || dist_px >= radius_px) {
    return 0.0;
  }

  return 1.0 - dist_px / radius_px;
}

// Energy a source with blur radius `radius_px` deposits per pixel at distance `dist_px`.
// The cone integrates to pi * r^2 / 3 over the disk, hence the 3 / (pi * r^2) factor.
// Sharp sources only cover their own pixel.
float dof_alpha_at_distance(float radius_px, float dist_px) {
  if (radius_px <= DOF_SOURCE_MIN_RADIUS_PX) {
    return dist_px <= 0.5 ? 1.0 : 0.0;
  }

  float shape = dof_blur_shape(radius_px, dist_px);

  if (shape <= 0.0) {
    return 0.0;
  }

  return (3.0 * shape) / max(PI * radius_px * radius_px, 1e-4);
}

// Area each kernel sample stands for: the kernel disk split evenly between its samples.
float dof_sample_boost(float max_radius_px, float sample_count) {
  return PI * max_radius_px * max_radius_px / sample_count;
}

// ---- five depth layers ----
//
// Samples are sorted by their depth relative to the pixel into far, mid-far, current,
// mid-near and near layers. Each layer averages its samples and gets an opacity equal to its
// total weight; the layers are then composited back to front. The layer boundaries are the
// depth differences that produce 1 px and 4 px of blur.

struct DofLayers {
  vec3 far_color;
  float far_weight;
  vec3 mid_far_color;
  float mid_far_weight;
  vec3 current_color;
  float current_weight;
  vec3 mid_near_color;
  float mid_near_weight;
  vec3 near_color;
  float near_weight;
};

DofLayers dof_layers_begin(vec3 pixel_color, float pixel_weight) {
  return DofLayers(
    vec3(0.0), 0.0,
    vec3(0.0), 0.0,
    pixel_color * pixel_weight, pixel_weight,
    vec3(0.0), 0.0,
    vec3(0.0), 0.0
  );
}

void dof_layers_add(inout DofLayers layers, vec3 color, float weight, float depth_delta, vec4 focus) {
  float center_band = 1.0 / focus.z;
  float mid_band = 4.0 / focus.z;

  if (depth_delta > mid_band + DOF_DEPTH_EPS) {
    layers.far_color += color * weight;
    layers.far_weight += weight;
  } else if (depth_delta > center_band + DOF_DEPTH_EPS) {
    layers.mid_far_color += color * weight;
    layers.mid_far_weight += weight;
  } else if (depth_delta >= -center_band - DOF_DEPTH_EPS) {
    layers.current_color += color * weight;
    layers.current_weight += weight;
  } else if (depth_delta >= -mid_band - DOF_DEPTH_EPS) {
    layers.mid_near_color += color * weight;
    layers.mid_near_weight += weight;
  } else {
    layers.near_color += color * weight;
    layers.near_weight += weight;
  }
}

// Premultiplied layer: average color times opacity, opacity = total weight clamped to 1.
vec4 dof_resolve_layer(vec3 color_sum, float weight_sum) {
  if (weight_sum <= 1e-5) {
    return vec4(0.0);
  }

  float alpha = clamp(weight_sum, 0.0, 1.0);
  return vec4(color_sum / weight_sum * alpha, alpha);
}

vec4 dof_composite_over(vec4 top, vec4 bottom) {
  return top + bottom * (1.0 - top.a);
}

// Opacity of the layers in front of the pixel (mid-near and near) composited together.
float dof_layers_front_alpha(DofLayers layers) {
  float near_alpha = clamp(layers.near_weight, 0.0, 1.0);
  float mid_near_alpha = clamp(layers.mid_near_weight, 0.0, 1.0);
  return near_alpha + mid_near_alpha * (1.0 - near_alpha);
}

// Final HDR color of the pixel; `fallback` is used when no layer received any weight.
vec3 dof_layers_resolve(DofLayers layers, vec3 fallback) {
  vec4 result = dof_resolve_layer(layers.far_color, layers.far_weight);
  result = dof_composite_over(dof_resolve_layer(layers.mid_far_color, layers.mid_far_weight), result);
  result = dof_composite_over(dof_resolve_layer(layers.current_color, layers.current_weight), result);
  result = dof_composite_over(dof_resolve_layer(layers.mid_near_color, layers.mid_near_weight), result);
  result = dof_composite_over(dof_resolve_layer(layers.near_color, layers.near_weight), result);
  return result.a > 1e-5 ? result.rgb / result.a : fallback;
}

#endif
