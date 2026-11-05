-- Loads a gem mesh written by tools/extract_gems.py (JSON streams: flat triangles with
-- positions and normals) into a Defold buffer. The exported triangles have inconsistent
-- winding, so every triangle is turned to face away from the gem center (the meshes are
-- convex around their origin) and gets its flat face normal. The AABB metadata lets the
-- mesh component frustum-cull the buffer.

local M = {}

local AABB_METADATA = hash("AABB")

local TYPE_MAP = {
  float32 = buffer.VALUE_TYPE_FLOAT32,
  uint8 = buffer.VALUE_TYPE_UINT8,
  uint16 = buffer.VALUE_TYPE_UINT16,
  uint32 = buffer.VALUE_TYPE_UINT32,
  int8 = buffer.VALUE_TYPE_INT8,
  int16 = buffer.VALUE_TYPE_INT16,
  int32 = buffer.VALUE_TYPE_INT32,
}

local function cross(ax, ay, az, bx, by, bz)
  return ay * bz - az * by,
         az * bx - ax * bz,
         ax * by - ay * bx
end

local function normalize(x, y, z)
  local len = math.sqrt(x * x + y * y + z * z)
  if len < 1e-8 then
    return 0, 1, 0
  end
  return x / len, y / len, z / len
end

local function find_stream(streams, name)
  for i = 1, #streams do
    if streams[i].name == name then
      return streams[i].data
    end
  end
  error("Gem buffer has no '" .. name .. "' stream")
end

local function swap_vertices(data, i, j)
  for k = 0, 2 do
    data[i + k], data[j + k] = data[j + k], data[i + k]
  end
end

local function orient_triangles(streams)
  local positions = find_stream(streams, "position")
  local normals = find_stream(streams, "normal")
  assert(#positions % 9 == 0 and #normals == #positions, "Gem buffer is not a list of triangles")

  -- Exported vertex normals, turned outwards (away from the origin); a missing normal is
  -- replaced by the direction of the vertex itself.
  for i = 1, #positions, 3 do
    local px, py, pz = positions[i], positions[i + 1], positions[i + 2]
    local nx, ny, nz = normals[i], normals[i + 1], normals[i + 2]

    if nx * nx + ny * ny + nz * nz <= 1e-8 then
      nx, ny, nz = normalize(px, py, pz)
    elseif px * nx + py * ny + pz * nz < 0 then
      nx, ny, nz = -nx, -ny, -nz
    end
    normals[i], normals[i + 1], normals[i + 2] = nx, ny, nz
  end

  -- Triangles whose winding disagrees with those outward normals are flipped; then every
  -- vertex gets the flat face normal.
  for i = 1, #positions, 9 do
    local ax, ay, az = positions[i], positions[i + 1], positions[i + 2]
    local nx, ny, nz = cross(
      positions[i + 3] - ax, positions[i + 4] - ay, positions[i + 5] - az,
      positions[i + 6] - ax, positions[i + 7] - ay, positions[i + 8] - az
    )
    local snx = normals[i] + normals[i + 3] + normals[i + 6]
    local sny = normals[i + 1] + normals[i + 4] + normals[i + 7]
    local snz = normals[i + 2] + normals[i + 5] + normals[i + 8]

    if nx * snx + ny * sny + nz * snz < 0 then
      swap_vertices(positions, i + 3, i + 6)
      nx, ny, nz = -nx, -ny, -nz
    end

    nx, ny, nz = normalize(nx, ny, nz)
    for j = i, i + 6, 3 do
      normals[j], normals[j + 1], normals[j + 2] = nx, ny, nz
    end
  end
end

local function build_buffer(streams)
  local declaration = {}
  local element_count = #streams[1].data / streams[1].count

  for i = 1, #streams do
    local stream = streams[i]
    assert(#stream.data / stream.count == element_count, "Mismatched stream element counts")
    declaration[i] = {
      name = hash(stream.name),
      type = assert(TYPE_MAP[stream.type], "Unsupported buffer stream type: " .. tostring(stream.type)),
      count = stream.count,
    }
  end

  local buf = buffer.create(element_count, declaration)
  for i = 1, #streams do
    local source = streams[i].data
    local target = buffer.get_stream(buf, hash(streams[i].name))
    for j = 1, #source do
      target[j] = source[j]
    end
  end

  local positions = find_stream(streams, "position")
  local min = { math.huge, math.huge, math.huge }
  local max = { -math.huge, -math.huge, -math.huge }
  for j = 1, #positions do
    local axis = (j - 1) % 3 + 1
    min[axis] = math.min(min[axis], positions[j])
    max[axis] = math.max(max[axis], positions[j])
  end
  buffer.set_metadata(buf, AABB_METADATA, { min[1], min[2], min[3], max[1], max[2], max[3] }, buffer.VALUE_TYPE_FLOAT32)

  return buf
end

function M.create(path)
  local raw = assert(sys.load_resource(path), "Failed to load gem buffer: " .. tostring(path))
  local streams = json.decode(raw)
  orient_triangles(streams)
  return build_buffer(streams)
end

return M
