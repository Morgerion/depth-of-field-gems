-- Layout of the gem cluster: one gem of every cut in geometry/gems/manifest.lua, placed on
-- three rings and two poles around the room center, each with a saturated body color.

local consts = require("config.consts")
local gem_manifest = require("geometry.gems.manifest")

local M = {}

local PALETTE = {
  vmath.vector4(1.0, 0.0, 0.0, 1.0),
  vmath.vector4(0.0, 1.0, 0.0, 1.0),
  vmath.vector4(0.0, 0.0, 1.0, 1.0),
  vmath.vector4(1.0, 1.0, 0.0, 1.0),
  vmath.vector4(1.0, 0.0, 1.0, 1.0),
  vmath.vector4(0.0, 1.0, 1.0, 1.0),
  vmath.vector4(1.0, 0.5, 0.0, 1.0),
  vmath.vector4(1.0, 0.0, 0.5, 1.0),
  vmath.vector4(0.5, 1.0, 0.0, 1.0),
  vmath.vector4(0.0, 1.0, 0.5, 1.0),
  vmath.vector4(0.5, 0.0, 1.0, 1.0),
  vmath.vector4(0.0, 0.5, 1.0, 1.0),
}

-- The upper and lower rings are pulled in a little so their gems do not touch the middle ring.
local OUTER_RING_TIGHTENING = 0.82

-- Colors beyond the palette size repeat with a stride of 5, so neighbors differ.
local function pick_color(index)
  local palette_index = index
  if index > #PALETTE then
    palette_index = ((index - #PALETTE - 1) * 5 + 2) % #PALETTE + 1
  end
  return vmath.vector4(PALETTE[palette_index])
end

local function add_ring(positions, count, radius, y, angle_offset)
  for i = 0, count - 1 do
    local angle = (i / count) * math.pi * 2.0 - math.pi * 0.5 + angle_offset
    positions[#positions + 1] = vmath.vector3(math.cos(angle) * radius, y, math.sin(angle) * radius)
  end
end

-- 21 positions: top pole, upper ring of 5, center, middle ring of 8, lower ring of 5, bottom pole.
local function build_positions(radius)
  local positions = {}
  local ring_y = radius * 0.5
  local outer_ring_radius = math.sqrt(radius * radius - ring_y * ring_y) * OUTER_RING_TIGHTENING

  positions[#positions + 1] = vmath.vector3(0.0, radius, 0.0)
  add_ring(positions, 5, outer_ring_radius, ring_y, 0.0)
  positions[#positions + 1] = vmath.vector3(0.0, 0.0, 0.0)
  add_ring(positions, 8, radius, 0.0, 0.0)
  add_ring(positions, 5, outer_ring_radius, -ring_y, math.pi / 5.0)
  positions[#positions + 1] = vmath.vector3(0.0, -radius, 0.0)
  return positions
end

function M.build_descriptors()
  local gems = gem_manifest.gems
  local positions = build_positions(consts.GEM_CLUSTER_RADIUS)
  assert(#positions >= #gems, "The layout has fewer positions than there are gems")

  local result = {}
  for i = 1, #gems do
    result[i] = {
      id = gems[i].id,
      buffer = gems[i].buffer,
      color = pick_color(i),
      position = positions[i],
      radius = consts.GEM_BOUND_RADIUS,
    }
  end
  return result
end

return M
