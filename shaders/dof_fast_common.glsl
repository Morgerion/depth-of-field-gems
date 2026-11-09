#ifndef DOF_FAST_COMMON_GLSL_H
#define DOF_FAST_COMMON_GLSL_H

// Shared code for the DoF fast path: dof_prepare -> dof_tile_max -> dof_tile_dilate ->
// dof_gather -> (dof_temporal -> dof_tonemap when temporal accumulation is on).
// The half-resolution mode inserts dof_downsample before the tile passes, runs the tile passes
// and the gather at half resolution and brings the result back with dof_composite.
//
// The fast path computes exactly the same formula as dof_present.fp, but:
//   1. color and depth are unpacked once per frame into RGBA16F (rgb = HDR, a = linear
//      depth), so each sample costs 2 reads instead of 5 reads, 4 unpacks and a matrix;
//   2. the neighbors' maximum blur radius is computed per tile, and a pixel iterates over
//      only the kernel samples that lie within it. The rest get zero weight in the original
//      formula anyway; sample positions, rotation and weights are unchanged, and so is the result.

uniform fs_uniforms {
  // xy = 1 / size, zw = size of the full-resolution targets in pixels.
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
  // x = tile size in pixels, y = dilation radius in tiles, z = 1 for the half-resolution gather.
  vec4 u_dof_tiles;
  // Temporal accumulation (dof_temporal.fp): x = 1 if enabled, y = 1 if the image changed
  // this frame (camera, focus or settings), z = 1 if the camera moved (history needs
  // reprojection), w = width of the history clamp window in standard deviations.
  vec4 u_temporal;
  // x = accumulated frame limit while the image is static; y = while it is changing.
  vec4 u_temporal_limits;
  // Transforms a position from the current frame's view space to the previous frame's clip space.
  mat4 u_reproj;
};

#include "/shaders/dof_common.glsl"

const int DOF_MAX_TILE_SIZE = 32;
const int DOF_MAX_DILATION = 4;
// The per-tile radius is stored in RGBA8 in 0.25 px steps (up to 63.75 px), rounded up,
// so that the search radius is never smaller than the true one.
const float DOF_TILE_RADIUS_STEPS = 4.0;

float encode_tile_radius(float radius_px) {
  return min(ceil(radius_px * DOF_TILE_RADIUS_STEPS) / 255.0, 1.0);
}

// Target sizes come from uniforms rather than textureSize/texelFetch: Defold also builds shaders for
// WebGL1 (ESSL 1.00), which lacks these functions. Sampling exactly at the texel center returns
// the texel itself even with linear filtering, so this is the same read.
vec2 get_full_size() {
  return u_full_texel.zw;
}

float get_tile_size() {
  return max(floor(u_dof_tiles.x + 0.5), 1.0);
}

vec2 get_tiles_size() {
  return ceil(get_full_size() / get_tile_size());
}

vec4 fetch_texel(sampler2D tex, vec2 texel, vec2 size) {
  return texture(tex, (clamp(texel, vec2(0.0), size - vec2(1.0)) + vec2(0.5)) / size);
}

float decode_tile_radius(float encoded, float max_radius_px) {
  if (encoded >= 1.0) {
    return max_radius_px;
  }
  return encoded * 255.0 / DOF_TILE_RADIUS_STEPS;
}

#endif
