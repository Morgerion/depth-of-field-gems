#version 140

// Half-resolution DoF, step 1: 2x2 downsample of the prepared scene (dof_prepare.fp).
// Rendered into a target of size ceil(width / 2) x ceil(height / 2).
//
// A half-resolution texel takes the depth of the nearest of its four pixels, so foreground
// edges keep their full extent. Its color is the average of the pixels on that nearest surface
// (depth within 1 px of blur of it): a plain box average keeps the energy of small bright
// highlights, which is what makes their bokeh disks as bright as at full resolution.

uniform sampler2D u_source_sampler;

out vec4 color_out;

#include "/shaders/dof_fast_common.glsl"

void main() {
  vec2 size = get_full_size();
  vec2 base = floor(gl_FragCoord.xy) * 2.0;
  vec4 texels[4];
  texels[0] = fetch_texel(u_source_sampler, base, size);
  texels[1] = fetch_texel(u_source_sampler, base + vec2(1.0, 0.0), size);
  texels[2] = fetch_texel(u_source_sampler, base + vec2(0.0, 1.0), size);
  texels[3] = fetch_texel(u_source_sampler, base + vec2(1.0, 1.0), size);

  float nearest_depth = min(min(texels[0].a, texels[1].a), min(texels[2].a, texels[3].a));
  float tolerance = 1.0 / max(u_dof_focus.z, 1e-3) + DOF_DEPTH_EPS;

  vec3 color_sum = vec3(0.0);
  float count = 0.0;
  for (int i = 0; i < 4; ++i) {
    if (texels[i].a - nearest_depth <= tolerance) {
      color_sum += texels[i].rgb;
      count += 1.0;
    }
  }

  color_out = vec4(color_sum / count, nearest_depth);
}
