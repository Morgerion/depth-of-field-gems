#version 140

// DoF fast path, step 6 (when accumulation is enabled): tone mapping of the accumulated history
// to the screen. Without accumulation, dof_gather.fp does the tone mapping itself.

uniform sampler2D u_history_sampler;

in vec2 var_texcoord0;

out vec4 color_out;

#include "/shaders/dof_fast_common.glsl"

void main() {
  vec2 size = get_full_size();
  vec3 hdr = fetch_texel(u_history_sampler, floor(var_texcoord0 * size), size).rgb;
  color_out = vec4(tone_mapping_aces(hdr, u_tonemap.x), 1.0);
}
