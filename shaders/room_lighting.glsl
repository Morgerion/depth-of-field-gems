#ifndef ROOM_LIGHTING_GLSL_H
#define ROOM_LIGHTING_GLSL_H

// Analytic lighting of the cube room, shared by the room itself (room.fp) and by the gems,
// which see the room in reflections and through refraction (gem.fp): ray-box intersection,
// exact irradiance from two rectangular window lights (polygon form factor), a cheap
// approximation of indirect light and the dielectric Fresnel term.
// Requires a uniform block with the room_* constants and window_light_color.

const float INV_PI = 0.31830988618;

vec3 normalize_tint(vec3 color) {
  float max_component = max(max(color.r, color.g), color.b);
  return color / max(max_component, 1e-5);
}

float get_wall_albedo() {
  return room_surface_settings.x;
}

float get_floor_albedo() {
  return room_surface_settings.y;
}

float get_ceiling_albedo() {
  return room_surface_settings.z;
}

float get_window_half_size(vec3 half_extents) {
  return half_extents.x * room_surface_settings.w;
}

vec3 get_window_radiance() {
  return window_light_color.rgb * window_light_color.w;
}

vec3 get_face_tint(vec3 outward_normal) {
  if (outward_normal.x < -0.5) {
    return normalize_tint(room_tint_neg_x.rgb);
  }
  if (outward_normal.x > 0.5) {
    return normalize_tint(room_tint_pos_x.rgb);
  }
  if (outward_normal.y > 0.5) {
    return vec3(1.0, 1.0, 1.0);
  }
  if (outward_normal.y < -0.5) {
    return normalize_tint(room_tint_floor.rgb);
  }
  if (outward_normal.z < -0.5) {
    return normalize_tint(room_tint_neg_z.rgb);
  }
  return normalize_tint(room_tint_pos_z.rgb);
}

float get_face_albedo(vec3 outward_normal) {
  if (outward_normal.y > 0.5) {
    return get_ceiling_albedo();
  }
  if (outward_normal.y < -0.5) {
    return get_floor_albedo();
  }
  return get_wall_albedo();
}

float ray_box(vec3 ro, vec3 rd, vec3 half_extents) {
  vec3 t0 = (-half_extents - ro) / rd;
  vec3 t1 = ( half_extents - ro) / rd;
  vec3 tmin3 = min(t0, t1);
  vec3 tmax3 = max(t0, t1);
  float t_near = max(max(tmin3.x, tmin3.y), tmin3.z);
  float t_far = min(min(tmax3.x, tmax3.y), tmax3.z);

  if (t_near > t_far || t_far <= 0.0) {
    return -1.0;
  }

  return t_near > 0.0 ? t_near : t_far;
}

vec3 get_outward_normal(vec3 p, vec3 half_extents) {
  vec3 d = abs(abs(p) - half_extents);
  if (d.x < d.y && d.x < d.z) {
    return vec3(sign(p.x), 0.0, 0.0);
  }
  if (d.y < d.z) {
    return vec3(0.0, sign(p.y), 0.0);
  }
  return vec3(0.0, 0.0, sign(p.z));
}

float rect_geometric_term(vec3 p, vec3 n, vec3 l0, vec3 l1, vec3 l2, vec3 l3) {
  vec3 center = (l0 + l1 + l2 + l3) * 0.25;
  if (dot(n, center - p) <= 0.0) {
    return 0.0;
  }

  vec3 w0 = normalize(l0 - p);
  vec3 w1 = normalize(l1 - p);
  vec3 w2 = normalize(l2 - p);
  vec3 w3 = normalize(l3 - p);

  vec3 c0 = cross(w0, w1);
  vec3 c1 = cross(w1, w2);
  vec3 c2 = cross(w2, w3);
  vec3 c3 = cross(w3, w0);

  float sum = 0.0;

  float l0c = length(c0);
  if (l0c > 1e-6) sum += atan(l0c, dot(w0, w1)) * dot(n, c0 / l0c);
  float l1c = length(c1);
  if (l1c > 1e-6) sum += atan(l1c, dot(w1, w2)) * dot(n, c1 / l1c);
  float l2c = length(c2);
  if (l2c > 1e-6) sum += atan(l2c, dot(w2, w3)) * dot(n, c2 / l2c);
  float l3c = length(c3);
  if (l3c > 1e-6) sum += atan(l3c, dot(w3, w0)) * dot(n, c3 / l3c);

  return abs(sum);
}

void get_pos_x_window(vec3 half_extents, out vec3 l0, out vec3 l1, out vec3 l2, out vec3 l3) {
  float h = get_window_half_size(half_extents);
  l0 = vec3(half_extents.x, -h, -h);
  l1 = vec3(half_extents.x, -h,  h);
  l2 = vec3(half_extents.x,  h,  h);
  l3 = vec3(half_extents.x,  h, -h);
}

void get_neg_z_window(vec3 half_extents, out vec3 l0, out vec3 l1, out vec3 l2, out vec3 l3) {
  float h = get_window_half_size(half_extents);
  l0 = vec3(-h, -h, -half_extents.z);
  l1 = vec3(-h,  h, -half_extents.z);
  l2 = vec3( h,  h, -half_extents.z);
  l3 = vec3( h, -h, -half_extents.z);
}

bool is_window_region(vec3 p, vec3 outward_normal, vec3 half_extents) {
  float h = get_window_half_size(half_extents);
  if (outward_normal.x > 0.5) {
    return abs(p.y) <= h && abs(p.z) <= h;
  }
  if (outward_normal.z < -0.5) {
    return abs(p.x) <= h && abs(p.y) <= h;
  }
  return false;
}

vec3 sample_window_lights(vec3 p, vec3 n, vec3 half_extents) {
  vec3 l0;
  vec3 l1;
  vec3 l2;
  vec3 l3;
  get_pos_x_window(half_extents, l0, l1, l2, l3);
  float projected_pos_x = rect_geometric_term(p, n, l0, l1, l2, l3);
  get_neg_z_window(half_extents, l0, l1, l2, l3);
  float projected_neg_z = rect_geometric_term(p, n, l0, l1, l2, l3);
  return get_window_radiance() * ((projected_pos_x + projected_neg_z) * INV_PI);
}

vec3 sample_indirect_bounce(vec3 p, vec3 inward_normal, vec3 outward_normal, vec3 half_extents) {
  float wall_albedo = get_wall_albedo();
  float floor_albedo = get_floor_albedo();
  float ceiling_albedo = get_ceiling_albedo();
  vec3 wall_mix =
      normalize_tint(room_tint_neg_x.rgb) * (wall_albedo * 0.22) +
      normalize_tint(room_tint_pos_x.rgb) * (wall_albedo * 0.22) +
      normalize_tint(room_tint_neg_z.rgb) * (wall_albedo * 0.18) +
      normalize_tint(room_tint_pos_z.rgb) * (wall_albedo * 0.14) +
      normalize_tint(room_tint_floor.rgb) * (floor_albedo * 0.14) +
      vec3(1.00, 1.00, 1.00) * (ceiling_albedo * 0.10);

  float right_window_proximity = 1.0 - clamp((half_extents.x - p.x) / (half_extents.x * 2.0), 0.0, 1.0);
  float back_window_proximity = 1.0 - clamp((p.z + half_extents.z) / (half_extents.z * 2.0), 0.0, 1.0);
  float upper_bounce = smoothstep(-half_extents.y, half_extents.y, p.y);
  float normal_lift = clamp(dot(inward_normal, vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 0.0, 1.0);
  float face_boost = abs(outward_normal.y) > 0.5 ? 0.92 : 1.0;
  float window_fill = 0.16 + 0.24 * max(right_window_proximity, back_window_proximity);

  return wall_mix * (window_fill + 0.10 * upper_bounce + 0.12 * normal_lift) * face_boost;
}

vec3 sample_room_radiance(vec3 p, vec3 outward_normal, vec3 half_extents) {
  if (is_window_region(p, outward_normal, half_extents)) {
    return get_window_radiance();
  }

  vec3 inward_normal = -outward_normal;
  vec3 tint = get_face_tint(outward_normal);
  float albedo = get_face_albedo(outward_normal);
  vec3 direct = sample_window_lights(p, inward_normal, half_extents);
  vec3 indirect = sample_indirect_bounce(p, inward_normal, outward_normal, half_extents);
  return tint * albedo * (direct + indirect);
}

vec3 sample_room_environment(vec3 ray_origin, vec3 ray_dir, vec3 half_extents) {
  float t_hit = ray_box(ray_origin, ray_dir, half_extents);
  if (t_hit < 0.0) {
    return vec3(0.0);
  }

  vec3 hit_position = ray_origin + ray_dir * t_hit;
  vec3 outward_normal = get_outward_normal(hit_position, half_extents);
  return sample_room_radiance(hit_position, outward_normal, half_extents);
}

float fresnel_dielectric(float cos_theta_i, float eta_i, float eta_t) {
  cos_theta_i = clamp(cos_theta_i, -1.0, 1.0);

  bool entering = cos_theta_i > 0.0;
  if (!entering) {
    float temp = eta_i;
    eta_i = eta_t;
    eta_t = temp;
    cos_theta_i = abs(cos_theta_i);
  }

  float sin_theta_i = sqrt(max(0.0, 1.0 - cos_theta_i * cos_theta_i));
  float sin_theta_t = eta_i / eta_t * sin_theta_i;
  if (sin_theta_t >= 1.0) {
    return 1.0;
  }

  float cos_theta_t = sqrt(max(0.0, 1.0 - sin_theta_t * sin_theta_t));
  float r_parallel = ((eta_t * cos_theta_i) - (eta_i * cos_theta_t)) /
      ((eta_t * cos_theta_i) + (eta_i * cos_theta_t));
  float r_perpendicular = ((eta_i * cos_theta_i) - (eta_t * cos_theta_t)) /
      ((eta_i * cos_theta_i) + (eta_t * cos_theta_t));
  return 0.5 * (r_parallel * r_parallel + r_perpendicular * r_perpendicular);
}

#endif
