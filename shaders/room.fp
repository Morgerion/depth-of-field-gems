#version 140

// The cube room, drawn as a fullscreen quad: every pixel casts its view ray into the room,
// shades the hit point analytically (room_lighting.glsl) and writes the matching hardware
// depth, so the gems drawn afterwards are depth-tested against the room walls.

uniform fs_uniforms {
	vec4 camera_position;
	vec4 camera_forward;
	vec4 camera_right;
	vec4 camera_up;
	vec4 camera_settings;
	vec4 camera_clip;
	vec4 room_bounds;
	vec4 room_tint_neg_x;
	vec4 room_tint_pos_x;
	vec4 room_tint_neg_z;
	vec4 room_tint_pos_z;
	vec4 room_tint_floor;
	vec4 room_surface_settings;
	vec4 window_light_color;
};

in vec2 var_texcoord0;

out vec4 color_out;

#include "/shaders/hdr_common.glsl"
#include "/shaders/room_lighting.glsl"

const float WALL_VIGNETTE = 0.22;

float raw_depth_from_view_depth(float z_view) {
	float near_plane = camera_clip.x;
	float far_plane = camera_clip.y;
	float safe_z = max(z_view, near_plane + 1e-5);
	float z_ndc = (far_plane + near_plane - (2.0 * near_plane * far_plane) / safe_z) / max(far_plane - near_plane, 1e-5);
	return z_ndc * 0.5 + 0.5;
}

void main() {
	vec2 uv = var_texcoord0;
	vec2 screen = uv * 2.0 - 1.0;
	screen.x *= camera_settings.y;

	vec3 ray_origin = camera_position.xyz;
	vec3 ray_dir = normalize(
		camera_forward.xyz +
		camera_right.xyz * screen.x * camera_settings.x +
		camera_up.xyz * screen.y * camera_settings.x
	);

	vec3 half_extents = room_bounds.xyz;
	float t_hit = ray_box(ray_origin, ray_dir, half_extents);

	if (t_hit < 0.0) {
		color_out = vec4(0.0);
		gl_FragDepth = 1.0;
		return;
	}

	vec3 p = ray_origin + ray_dir * t_hit;
	vec3 outward_normal = get_outward_normal(p, half_extents);
	vec3 hdr = sample_room_radiance(p, outward_normal, half_extents);
	float view_depth = max(dot(p - camera_position.xyz, camera_forward.xyz), camera_clip.x);

	// Slight darkening of the walls towards the screen corners (up to 11%).
	hdr *= 1.0 - dot(uv - 0.5, uv - 0.5) * WALL_VIGNETTE;

	color_out = pack_hdr(hdr);
	gl_FragDepth = raw_depth_from_view_depth(view_depth);
}
