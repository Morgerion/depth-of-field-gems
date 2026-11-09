-- All tuning constants of the demo. Values listed in DEBUG_SLIDERS at the end can also be
-- changed at runtime with the sliders under the FPS counter (gui/fps_hud.gui_script).

local M = {}

-------------------------------------------------------------------------------------------------
-- Depth of field
-------------------------------------------------------------------------------------------------

-- Focus distance in world units; 0 = autofocus on the gem in the center of the view.
M.DOF_FOCUS_DISTANCE = 0.0
-- Blur radius (circle of confusion) in pixels at full defocus. At most 64: the tile pass
-- searches at most 4 tiles of 16 px around a pixel (checked at startup).
M.DOF_MAX_BLUR_RADIUS_PX = 28.0
-- Distance from the focus at which the blur reaches half of the maximum radius, and the full
-- radius. Everything closer than (2 * mid - max) to the focus distance stays sharp, so mid
-- should be at least max / 2; the defaults give a sharp range of zero.
M.DOF_MID_BLUR_DISTANCE = 0.14
M.DOF_MAX_BLUR_DISTANCE = 0.3
-- Autofocus: the focus ray towards the scene center hits gem bounding spheres shrunk by this
-- fraction (so the focus does not jump onto the very edge of a gem) and moves towards a new
-- target at this speed, in world units per second.
M.DOF_AUTOFOCUS_SPHERE_SHRINK = 0.3
M.DOF_AUTOFOCUS_SPEED = 0.15

-- Kernel samples per pixel when temporal accumulation is off.
M.DOF_SAMPLE_COUNT = 64.0
-- Fast path: unpack the scene into RGBA16F once per frame and skip kernel samples beyond the
-- neighbors' maximum blur radius (16x16 tiles). Same result as the original single pass
-- (shaders/dof_present.fp), which is used when this is false or RGBA16F is unavailable.
M.DOF_FAST_PATH = true
-- Temporal accumulation (fast path only). Every frame uses a new kernel rotation and ring
-- offset; while the image is static, frames are averaged and the noise fades; when the camera
-- moves, history is reprojected and clamped to avoid ghosting. false = every frame stands alone.
M.DOF_TEMPORAL = true
-- Kernel samples per pixel per frame with accumulation. The layered DoF is non-linear, so the
-- converged image still depends on this. Measured with a 16 px maximum blur radius against a
-- 128-sample reference, the share of pixels with a persistent error above 5/255 is
-- 24 -> 1.7%, 32 -> 1.15%, 48 -> 0.67%, 64 -> 0.40% (original single pass: 0.9%).
M.DOF_TEMPORAL_SAMPLE_COUNT = 48.0
-- Half-resolution mode (fast path only): the blur is computed at half resolution and brought
-- back to full size with depth-aware upsampling; in-focus pixels keep their full-resolution
-- detail. Much cheaper, slightly less exact (see README). Also switchable at runtime with the
-- button in the settings panel.
M.DOF_HALF_RESOLUTION = false
-- Kernel samples per half-resolution pixel per frame with accumulation. A half-resolution
-- pixel covers four full-resolution ones, so the kernel is four times denser than at full
-- resolution with the same count.
M.DOF_HALF_RES_SAMPLE_COUNT = 48.0
-- Averaging window in frames while the image is static, and while it is changing.
M.DOF_TEMPORAL_MAX_FRAMES = 32.0
M.DOF_TEMPORAL_MAX_FRAMES_MOVING = 8.0
-- Width of the history clamp window while moving, in standard deviations of the 3x3
-- neighborhood. Smaller = less ghosting, but more noise in motion.
M.DOF_TEMPORAL_CLAMP_GAMMA = 1.25

-------------------------------------------------------------------------------------------------
-- Camera and scene
-------------------------------------------------------------------------------------------------

M.CAMERA_ORBIT_RADIUS = 0.485
M.CAMERA_FOV = math.rad(60)
M.CAMERA_NEAR = 0.01
M.CAMERA_FAR = 4.0
-- Starting orbit angles in radians.
M.CAMERA_START_YAW = 0.55
M.CAMERA_START_PITCH = -0.18
-- Orbit speed in radians per pixel of mouse drag, smoothing of the drag in seconds and the
-- vertical orbit limit.
M.CAMERA_DRAG_SPEED = 0.006
M.CAMERA_INPUT_SMOOTH_TIME = 0.1
M.CAMERA_PITCH_LIMIT = math.rad(80)

-- Edge length of the cube room.
M.ROOM_SIZE = 1.0
-- Radius the gem meshes were normalized to by tools/extract_gems.py. Changing it without
-- re-running the tool makes absorption and autofocus disagree with the actual mesh size.
M.GEM_BOUND_RADIUS = 0.065
-- Radius of the gem cluster around the room center.
M.GEM_CLUSTER_RADIUS = M.ROOM_SIZE * 0.2

-------------------------------------------------------------------------------------------------
-- Room lighting
-------------------------------------------------------------------------------------------------

-- Exposure before ACES tone mapping.
M.SCENE_EXPOSURE = 0.4359
-- Albedo of the walls, floor and ceiling.
M.ROOM_WALL_ALBEDO = 0.2371
M.ROOM_FLOOR_ALBEDO = 0.1879
M.ROOM_CEILING_ALBEDO = 0.6183
-- Half size of the two square window lights relative to half the wall, their radiance and
-- color. The scene buffer stores HDR values up to about 8 (shaders/hdr_common.glsl), so the
-- windows themselves are clipped there before the depth of field.
M.WINDOW_LIGHT_SIZE = 0.5558
M.WINDOW_LIGHT_INTENSITY = 10.0
M.WINDOW_LIGHT_COLOR = vmath.vector3(1.0, 1.0, 1.0)

-- Hue of the walls and floor (normalized to the brightest channel; brightness comes from the
-- albedo settings above). The ceiling is white.
M.ROOM_COLORS = {
	neg_x = vmath.vector4(0.36, 0.22, 0.18, 1.0),
	pos_x = vmath.vector4(0.31, 0.56, 0.43, 1.0),
	neg_z = vmath.vector4(0.57, 0.46, 0.31, 1.0),
	pos_z = vmath.vector4(0.43, 0.31, 0.57, 1.0),
	floor = vmath.vector4(0.9, 0.8, 0.8, 1.0),
}

-------------------------------------------------------------------------------------------------
-- Gems
-------------------------------------------------------------------------------------------------

-- Inspect the two parts of the gem shading separately.
M.GEM_REFLECTION_ENABLED = true
M.GEM_TRANSMISSION_ENABLED = true
-- Index of refraction (topaz 1.62, sapphire 1.77, diamond 2.42).
M.GEM_IOR = 1.62
-- Transmittance over the gem diameter of the channels in the gem's hue and of the others:
-- together they set how saturated the body color gets.
M.GEM_TRANSMITTANCE_IN_HUE = 0.22
M.GEM_TRANSMITTANCE_OFF_HUE = 0.02
-- Internal reflections traced per ray; each one is a pass over all facet planes.
M.GEM_FACET_MAX_BOUNCES = 5
-- Spread of the index of refraction from red to blue. 0 = no dispersion (3x cheaper).
-- Real gems have 0.01-0.045 (diamond 0.044); higher values give a more striking "fire".
M.GEM_DISPERSION = 0.06
-- Fraction of the light still trapped inside after the last reflection that is let out anyway,
-- so strongly reflecting gems do not turn dark.
M.GEM_TRAPPED_LIGHT_ESCAPE = 0.5
-- Beer-Lambert absorption: neutral absorption that dims all channels equally, a length added
-- once to every internal ray path so thin parts still show some color, and a multiplier of
-- the gem's own color absorption.
M.GEM_NEUTRAL_ABSORPTION = 0.01
M.GEM_THICKNESS_BIAS = 0.002
M.GEM_COLOR_DENSITY = 0.7091

-------------------------------------------------------------------------------------------------
-- Debug UI
-------------------------------------------------------------------------------------------------

-- How often the FPS counter is refreshed, in seconds.
M.FPS_UPDATE_INTERVAL = 0.25

-- Settings exposed as sliders, with their ranges. The blur radius range ends at the tile
-- search limit of 64 px.
M.DEBUG_SLIDERS = {
	{ key = "DOF_MAX_BLUR_RADIUS_PX", min = 0.0, max = 64.0 },
	{ key = "DOF_MID_BLUR_DISTANCE", min = 0.02, max = 1.0 },
	{ key = "DOF_MAX_BLUR_DISTANCE", min = 0.05, max = 2.0 },
	{ key = "SCENE_EXPOSURE", min = 0.2, max = 5.0 },
	{ key = "ROOM_WALL_ALBEDO", min = 0.1, max = 1.0 },
	{ key = "ROOM_FLOOR_ALBEDO", min = 0.1, max = 1.0 },
	{ key = "ROOM_CEILING_ALBEDO", min = 0.1, max = 1.0 },
	{ key = "WINDOW_LIGHT_SIZE", min = 0.1, max = 0.9 },
	{ key = "WINDOW_LIGHT_INTENSITY", min = 0.1, max = 30.0 },
	{ key = "GEM_NEUTRAL_ABSORPTION", min = 0.0, max = 10.0 },
	{ key = "GEM_THICKNESS_BIAS", min = 0.0, max = 0.02 },
	{ key = "GEM_COLOR_DENSITY", min = 0.0, max = 4.0 },
}

return M
