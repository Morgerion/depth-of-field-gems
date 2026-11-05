#version 140

// DoF fast path, step 3: maximum radius over neighboring tiles. The dilation radius
// (u_dof_tiles.y) = ceil(max radius / tile size), to cover all neighbors
// whose blur spot can reach a pixel of this tile.

uniform sampler2D u_tiles_sampler;

out vec4 color_out;

#include "/shaders/dof_fast_common.glsl"

void main() {
  vec2 size = get_tiles_size();
  vec2 tile = floor(gl_FragCoord.xy);
  float dilation = clamp(floor(u_dof_tiles.y + 0.5), 0.0, float(DOF_MAX_DILATION));
  float encoded = 0.0;

  for (int y = -DOF_MAX_DILATION; y <= DOF_MAX_DILATION; ++y) {
    if (abs(float(y)) > dilation) {
      continue;
    }
    for (int x = -DOF_MAX_DILATION; x <= DOF_MAX_DILATION; ++x) {
      if (abs(float(x)) > dilation) {
        continue;
      }
      encoded = max(encoded, fetch_texel(u_tiles_sampler, tile + vec2(float(x), float(y)), size).r);
    }
  }

  color_out = vec4(encoded, 0.0, 0.0, 1.0);
}
