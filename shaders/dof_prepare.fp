#version 140

// DoF fast path, step 1: once per frame, unpack the scene's HDR color (RGBM in RGBA8)
// and convert depth to linear. Output in RGBA16F: rgb = HDR, a = linear depth.

uniform sampler2D u_scene_sampler;
uniform sampler2D u_depth_sampler;

in vec2 var_texcoord0;

out vec4 color_out;

#include "/shaders/dof_fast_common.glsl"

void main() {
  vec2 uv = var_texcoord0;
  vec3 hdr = unpack_hdr(texture(u_scene_sampler, uv));
  float linear_depth = load_linear_depth(texture(u_depth_sampler, uv).r, uv, u_inv_proj, u_camera_clip.xy);
  color_out = vec4(hdr, linear_depth);
}
