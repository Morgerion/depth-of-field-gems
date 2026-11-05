"""Extracts the gem meshes from geometry/gems_21.gltf into Defold buffers.

Every mesh of the glTF scene becomes geometry/gems/<name>.buffer (flat triangles with
positions and normals), centered and scaled to GEM_BOUND_RADIUS from config/consts.lua,
and geometry/gems/manifest.lua lists them for objects/scene_layout.lua. Run from the project
root: python tools/extract_gems.py. Afterwards run tools/extract_gem_planes.py.
"""

import json
import math
import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GEOMETRY_DIR = ROOT / "geometry"
SOURCE_GLTF = GEOMETRY_DIR / "gems_21.gltf"
SOURCE_BIN = GEOMETRY_DIR / "gems_21.bin"
OUTPUT_DIR = GEOMETRY_DIR / "gems"
MANIFEST_PATH = OUTPUT_DIR / "manifest.lua"
CONSTS_PATH = ROOT / "config" / "consts.lua"


COMPONENT_FORMAT = {
    5126: ("f", 4),
    5125: ("I", 4),
    5123: ("H", 2),
    5122: ("h", 2),
    5121: ("B", 1),
}

TYPE_COMPONENTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
}


def load_target_radius():
    text = CONSTS_PATH.read_text("utf-8")
    match = re.search(r"GEM_BOUND_RADIUS\s*=\s*([0-9.]+)", text)
    if not match:
        raise RuntimeError("GEM_BOUND_RADIUS not found in config/consts.lua")
    return float(match.group(1))


def mat_identity():
    return [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]


def mat_mul(a, b):
    result = [[0.0] * 4 for _ in range(4)]
    for r in range(4):
        for c in range(4):
            result[r][c] = sum(a[r][k] * b[k][c] for k in range(4))
    return result


def transform_point(m, p):
    x, y, z = p
    return [
        m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
        m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
        m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3],
    ]


def transform_direction(m, v):
    x, y, z = v
    out = [
        m[0][0] * x + m[0][1] * y + m[0][2] * z,
        m[1][0] * x + m[1][1] * y + m[1][2] * z,
        m[2][0] * x + m[2][1] * y + m[2][2] * z,
    ]
    length = math.sqrt(out[0] * out[0] + out[1] * out[1] + out[2] * out[2])
    if length > 1e-8:
        out = [c / length for c in out]
    return out


def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]
        return [
            [m[0], m[4], m[8], m[12]],
            [m[1], m[5], m[9], m[13]],
            [m[2], m[6], m[10], m[14]],
            [m[3], m[7], m[11], m[15]],
        ]

    tx, ty, tz = node.get("translation", [0.0, 0.0, 0.0])
    sx, sy, sz = node.get("scale", [1.0, 1.0, 1.0])
    qx, qy, qz, qw = node.get("rotation", [0.0, 0.0, 0.0, 1.0])

    xx = qx * qx
    yy = qy * qy
    zz = qz * qz
    xy = qx * qy
    xz = qx * qz
    yz = qy * qz
    wx = qw * qx
    wy = qw * qy
    wz = qw * qz

    rot = [
        [1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), 0.0],
        [2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), 0.0],
        [2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy), 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]
    scale = [
        [sx, 0.0, 0.0, 0.0],
        [0.0, sy, 0.0, 0.0],
        [0.0, 0.0, sz, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]
    trans = mat_identity()
    trans[0][3] = tx
    trans[1][3] = ty
    trans[2][3] = tz
    return mat_mul(trans, mat_mul(rot, scale))


def accessor_data(gltf, blob, accessor_index):
    accessor = gltf["accessors"][accessor_index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    count = accessor["count"]
    comp_count = TYPE_COMPONENTS[accessor["type"]]
    fmt_code, comp_size = COMPONENT_FORMAT[accessor["componentType"]]
    stride = view.get("byteStride", comp_count * comp_size)
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    base = offset
    values = []
    for i in range(count):
        start = base + i * stride
        chunk = blob[start:start + comp_count * comp_size]
        values.append(struct.unpack("<" + fmt_code * comp_count, chunk))
    return values


def sanitize(name):
    cleaned = name.lower()
    cleaned = re.sub(r"[^a-z0-9]+", "_", cleaned)
    cleaned = re.sub(r"_+", "_", cleaned).strip("_")
    return cleaned


def build_world_matrices(gltf):
    parents = {}
    for idx, node in enumerate(gltf["nodes"]):
        for child in node.get("children", []):
            parents[child] = idx

    world = {}

    def compute(node_index):
        if node_index in world:
            return world[node_index]
        local = node_matrix(gltf["nodes"][node_index])
        if node_index in parents:
            world[node_index] = mat_mul(compute(parents[node_index]), local)
        else:
            world[node_index] = local
        return world[node_index]

    for i in range(len(gltf["nodes"])):
        compute(i)
    return world


def main():
    target_radius = load_target_radius()
    gltf = json.loads(SOURCE_GLTF.read_text("utf-8"))
    blob = SOURCE_BIN.read_bytes()
    OUTPUT_DIR.mkdir(exist_ok=True)
    world_mats = build_world_matrices(gltf)

    manifest = []

    for node_index, node in enumerate(gltf["nodes"]):
        if "mesh" not in node:
            continue

        mesh_index = node["mesh"]
        mesh = gltf["meshes"][mesh_index]
        primitive = mesh["primitives"][0]
        positions = accessor_data(gltf, blob, primitive["attributes"]["POSITION"])
        normals = accessor_data(gltf, blob, primitive["attributes"]["NORMAL"])
        indices = [x[0] for x in accessor_data(gltf, blob, primitive["indices"])]

        world = world_mats[node_index]
        world_positions = [transform_point(world, p) for p in positions]
        world_normals = [transform_direction(world, n) for n in normals]

        mins = [min(p[i] for p in world_positions) for i in range(3)]
        maxs = [max(p[i] for p in world_positions) for i in range(3)]
        center = [(mins[i] + maxs[i]) * 0.5 for i in range(3)]

        centered = [[p[i] - center[i] for i in range(3)] for p in world_positions]
        radius = max(math.sqrt(p[0] ** 2 + p[1] ** 2 + p[2] ** 2) for p in centered)
        scale = target_radius / radius if radius > 1e-8 else 1.0

        out_positions = []
        out_normals = []
        tri_positions = []

        for idx in indices:
            p = centered[idx]
            n = world_normals[idx]
            p = [c * scale for c in p]
            out_positions.extend(round(c, 8) for c in p)
            out_normals.extend(round(c, 8) for c in n)
            tri_positions.append(p)

        mins = [min(p[i] for p in tri_positions) for i in range(3)]
        maxs = [max(p[i] for p in tri_positions) for i in range(3)]

        file_stem = sanitize(mesh.get("name", f"gem_{mesh_index:02d}"))
        out_path = OUTPUT_DIR / f"{file_stem}.buffer"
        data = [
            {
                "name": "position",
                "type": "float32",
                "count": 3,
                "data": out_positions,
            },
            {
                "name": "normal",
                "type": "float32",
                "count": 3,
                "data": out_normals,
            },
        ]
        out_path.write_text(json.dumps(data, indent=2) + "\n", "utf-8")

        manifest.append({
            "name": mesh.get("name", file_stem),
            "id": file_stem,
            "buffer": f"/geometry/gems/{file_stem}.buffer",
        })

    lines = ["local M = {", "  gems = {"]
    for item in manifest:
        escaped_name = item["name"].replace("\\", "\\\\").replace('"', '\\"')
        lines.extend([
            "    {",
            f'      name = "{escaped_name}",',
            f'      id = "{item["id"]}",',
            f'      buffer = "{item["buffer"]}",',
            "    },",
        ])
    lines.extend(["  }", "}", "", "return M", ""])
    MANIFEST_PATH.write_text("\n".join(lines), "utf-8")

    print(f"Extracted {len(manifest)} gems to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
