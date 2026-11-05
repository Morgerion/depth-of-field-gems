#version 140

// DoF fast path, step 2: maximum blur radius within a tile.
// Rendered into a target of size (width / tile) x (height / tile).

uniform sampler2D u_source_sampler;

out vec4 color_out;

#include "/shaders/dof_fast_common.glsl"

void main() {
  vec2 size = get_full_size();
  int tile_size = int(min(get_tile_size(), float(DOF_MAX_TILE_SIZE)));
  vec2 base = floor(gl_FragCoord.xy) * float(tile_size);
  float max_radius = 0.0;

  for (int y = 0; y < DOF_MAX_TILE_SIZE; ++y) {
    if (y >= tile_size) {
      break;
    }
    for (int x = 0; x < DOF_MAX_TILE_SIZE; ++x) {
      if (x >= tile_size) {
        break;
      }
      float linear_depth = fetch_texel(u_source_sampler, base + vec2(float(x), float(y)), size).a;
      max_radius = max(max_radius, compute_dof_radius(linear_depth, u_dof_focus));
    }
  }

  color_out = vec4(encode_tile_radius(max_radius), 0.0, 0.0, 1.0);
}
