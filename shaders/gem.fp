#version 140

// Gem: analytic ray tracing against facets with dispersion.
//
// The gem is a convex polyhedron: facet planes gem_planes[i] = (n, w)
// in local coordinates, point x is inside if dot(n, x) <= w for all facets.
// The planes are built by tools/extract_gem_planes.py (geometry/gems/planes.lua),
// and gem.script writes them into each gem's material.
//
// The ray enters through the rasterized facet, refracts and then travels inside
// the polyhedron: the exit is the nearest plane it is moving toward.
// At each facet part of the energy exits according to Fresnel, the rest reflects
// back inside (under total internal reflection nothing exits).
//
// Dispersion: three independent traces with different indices of refraction for
// R, G and B; each produces its own channel. Hence the colored "fire" on the facets.

#define GEM_MAX_PLANES 96
#define GEM_MAX_BOUNCES 8

uniform fs_uniforms {
  // Per gem (objects/gem.script): body color, x = circumscribed sphere radius and
  // y = number of facet planes.
  vec4 gem_color;
  vec4 gem_shape;
  // x = transmittance of the color channels at full hue over the gem diameter,
  // y = transmittance of the other channels, w = index of refraction.
  vec4 gem_optics;
  vec4 camera_position;
  vec4 room_bounds;
  vec4 room_tint_neg_x;
  vec4 room_tint_pos_x;
  vec4 room_tint_neg_z;
  vec4 room_tint_pos_z;
  vec4 room_tint_floor;
  vec4 room_surface_settings;
  vec4 window_light_color;
  // x = reflection on/off, y = transmission on/off (for inspecting the two parts).
  vec4 gem_toggles;
  // x = neutral absorption, y = path length added once per ray, z = color density.
  vec4 gem_absorption;
  // x = internal reflections, y = IOR spread from red to blue, z = trapped light escape.
  vec4 gem_trace_settings;
  vec4 gem_planes[GEM_MAX_PLANES];
};

in vec3 var_world_normal;
in vec3 var_world_position;
in vec3 var_world_center;
in vec3 var_local_position;
in vec3 var_world_basis_x;
in vec3 var_world_basis_y;
in vec3 var_world_basis_z;
in vec3 var_local_basis_x;
in vec3 var_local_basis_y;
in vec3 var_local_basis_z;

out vec4 color_out;

#include "/shaders/hdr_common.glsl"
#include "/shaders/room_lighting.glsl"

const float SURFACE_OFFSET = 0.0015;

// ---- parameters ----

int get_plane_count() {
  return clamp(int(gem_shape.y + 0.5), 0, GEM_MAX_PLANES);
}

int get_max_bounces() {
  return clamp(int(gem_trace_settings.x + 0.5), 1, GEM_MAX_BOUNCES);
}

// 0 = no dispersion: a single trace instead of three.
float get_dispersion_spread() {
  return max(gem_trace_settings.y, 0.0);
}

// Fraction of the light still trapped after the last reflection that is released anyway.
float get_trapped_light_escape() {
  return clamp(gem_trace_settings.z, 0.0, 1.0);
}

float get_gem_ior() {
  return max(gem_optics.w, 1.01);
}

// ---- absorption (Beer-Lambert) ----

vec3 get_gem_hue(vec3 gem_color) {
  return normalize_tint(max(gem_color, vec3(0.0)));
}

vec3 get_total_absorption(vec3 gem_hue, float sphere_radius) {
  float transmittance_peak = clamp(gem_optics.x, 0.001, 0.98);
  float transmittance_floor = clamp(gem_optics.y, 0.001, transmittance_peak - 1e-4);
  vec3 reference_transmittance = mix(vec3(transmittance_floor), vec3(transmittance_peak), gem_hue);
  float reference_length = max(sphere_radius * 2.0, 1e-4);
  float density_scale = max(gem_absorption.z, 0.0);
  vec3 color_absorption = (-log(reference_transmittance) / reference_length) * density_scale;
  return color_absorption + vec3(max(gem_absorption.x, 0.0));
}

// ---- conversions between local and world coordinates ----

mat3 get_to_world() {
  return mat3(var_world_basis_x, var_world_basis_y, var_world_basis_z);
}

mat3 get_to_local() {
  return mat3(var_local_basis_x, var_local_basis_y, var_local_basis_z);
}

vec3 sample_environment_local(mat3 to_world, vec3 local_position, vec3 local_dir, vec3 half_extents) {
  vec3 world_dir = normalize(to_world * local_dir);
  vec3 world_position = to_world * local_position + var_world_center;
  return sample_room_environment(world_position + world_dir * SURFACE_OFFSET, world_dir, half_extents);
}

// ---- tracing inside the polyhedron ----

// Nearest facet through which a ray from p in direction d leaves the gem.
float find_exit(vec3 p, vec3 d, int plane_count, out vec3 exit_normal) {
  float t_exit = 1e9;
  exit_normal = vec3(0.0);

  for (int i = 0; i < GEM_MAX_PLANES; ++i) {
    if (i >= plane_count) {
      break;
    }

    vec4 plane = gem_planes[i];
    float facing = dot(plane.xyz, d);
    if (facing > 1e-4) {
      float t = (plane.w - dot(plane.xyz, p)) / facing;
      if (t < t_exit) {
        t_exit = t;
        exit_normal = plane.xyz;
      }
    }
  }

  return max(t_exit, 0.0);
}

// Light that exits the gem along the path of a ray starting inside at point p along d
// (local coordinates). Returns an HDR color; with dispersion, only the channel
// for its own wavelength is taken from it.
vec3 trace_inside(mat3 to_world, vec3 p, vec3 d, float ior, vec3 sigma, vec3 half_extents) {
  int plane_count = get_plane_count();
  int max_bounces = get_max_bounces();
  vec3 radiance = vec3(0.0);
  vec3 throughput = vec3(1.0);
  float path_bias = max(gem_absorption.y, 0.0);

  for (int bounce = 0; bounce < GEM_MAX_BOUNCES; ++bounce) {
    if (bounce >= max_bounces || plane_count == 0) {
      break;
    }

    vec3 exit_normal;
    float t = find_exit(p, d, plane_count, exit_normal);
    if (dot(exit_normal, exit_normal) < 0.5) {
      break;
    }

    float world_length = t * length(to_world * d) + path_bias;
    path_bias = 0.0;
    throughput *= exp(-sigma * world_length);
    p += d * t;

    float cos_i = dot(d, exit_normal);
    float fresnel = fresnel_dielectric(cos_i, ior, 1.0);
    vec3 reflected_dir = reflect(d, exit_normal);
    vec3 exit_dir = refract(d, -exit_normal, ior);
    bool has_exit = fresnel < 1.0 && dot(exit_dir, exit_dir) > 1e-6;
    bool last_bounce = bounce + 1 >= max_bounces;

    // Exactly one environment lookup per facet. At the last facet, the light still
    // trapped inside is added to the exiting light (otherwise gems with strong total
    // internal reflection go dark); under total reflection it leaves along the reflected ray.
    float exit_weight = has_exit ? 1.0 - fresnel : 0.0;
    if (last_bounce) {
      exit_weight += fresnel * get_trapped_light_escape();
    }

    if (exit_weight > 0.0) {
      vec3 sample_dir = has_exit ? normalize(exit_dir) : reflected_dir;
      radiance += throughput * exit_weight * sample_environment_local(to_world, p, sample_dir, half_extents);
    }

    throughput *= fresnel;
    d = reflected_dir;

    if (max(max(throughput.r, throughput.g), throughput.b) < 0.003) {
      break;
    }
  }

  return radiance;
}

vec3 trace_wavelength(mat3 to_world, vec3 entry_position, vec3 incident_dir, vec3 entry_normal, float ior, vec3 sigma, vec3 half_extents) {
  vec3 inner_dir = refract(incident_dir, entry_normal, 1.0 / ior);
  if (dot(inner_dir, inner_dir) <= 1e-6) {
    return vec3(0.0);
  }
  return trace_inside(to_world, entry_position, normalize(inner_dir), ior, sigma, half_extents);
}

void main() {
  vec3 half_extents = room_bounds.xyz;
  float sphere_radius = gem_shape.x;
  float ior = get_gem_ior();
  vec3 gem_hue = get_gem_hue(gem_color.rgb);
  vec3 sigma = get_total_absorption(gem_hue, sphere_radius);

  vec3 n = normalize(var_world_normal);
  vec3 view_dir = normalize(camera_position.xyz - var_world_position);
  float cos_theta = clamp(dot(n, view_dir), 0.0, 1.0);
  float entry_fresnel = fresnel_dielectric(cos_theta, 1.0, ior);

  vec3 hdr = vec3(0.0);

  if (gem_toggles.x > 0.5) {
    vec3 reflection_dir = reflect(-view_dir, n);
    hdr += sample_room_environment(var_world_position + n * SURFACE_OFFSET, reflection_dir, half_extents) * entry_fresnel;
  }

  if (gem_toggles.y > 0.5) {
    mat3 to_world = get_to_world();
    mat3 to_local = get_to_local();
    vec3 local_normal = normalize(to_local * n);
    vec3 local_incident = normalize(to_local * -view_dir);
    vec3 entry_position = var_local_position;
    float spread = get_dispersion_spread();
    bool dispersion = spread > 1e-4;
    int wavelength_count = dispersion ? 3 : 1;
    vec3 transmission = vec3(0.0);

    // A single trace call inside a loop rather than three copies in a row: otherwise the driver
    // unrolls the nested loops three times and the shader takes tens of seconds to compile.
    for (int channel = 0; channel < 3; ++channel) {
      if (channel >= wavelength_count) {
        break;
      }

      float channel_ior = dispersion ? ior + spread * (float(channel) * 0.5 - 0.5) : ior;
      vec3 traced = trace_wavelength(to_world, entry_position, local_incident, local_normal, channel_ior, sigma, half_extents);
      vec3 mask = dispersion ? vec3(equal(ivec3(channel), ivec3(0, 1, 2))) : vec3(1.0);
      transmission += traced * mask;
    }

    hdr += transmission * (1.0 - entry_fresnel);
  }

  color_out = pack_hdr(hdr);
}
