"""Read-only compatibility probe. Does NOT compile/run the C++ implementation.

Downloads only the small current metadata and one coarse node; never writes imagery.
Run explicitly: python tests/earth/rocktree_probe.py
"""
import math
import struct
import urllib.request


def varint(data, offset):
    value = 0
    for shift in range(0, 70, 7):
        if offset >= len(data):
            raise ValueError("TRUNCATED_VARINT")
        byte = data[offset]
        offset += 1
        if shift == 63 and byte > 1:
            raise ValueError("VARINT_OVERFLOW")
        value |= (byte & 127) << shift
        if not byte & 128:
            return value, offset
    raise ValueError("VARINT_OVERFLOW")


def fields(data):
    offset = 0
    while offset < len(data):
        tag, offset = varint(data, offset)
        field, wire = tag >> 3, tag & 7
        if not field:
            raise ValueError("ZERO_FIELD")
        if wire == 0:
            value, offset = varint(data, offset)
        else:
            if wire in (1, 5):
                size = 8 if wire == 1 else 4
            elif wire == 2:
                size, offset = varint(data, offset)
            else:
                raise ValueError("UNSUPPORTED_WIRE")
            if size > len(data) - offset:
                raise ValueError("TRUNCATED_FIELD")
            value = data[offset:offset + size]
            offset += size
        yield field, wire, value


def get(path):
    with urllib.request.urlopen("https://kh.google.com/rt/earth/" + path, timeout=20) as response:
        assert response.status == 200
        data = response.read(16 * 1024 * 1024 + 1)
        assert 0 < len(data) <= 16 * 1024 * 1024
        return data


def probe():
    planet = dict((field, value) for field, _, value in fields(get("PlanetoidMetadata")))
    epoch = dict((field, value) for field, _, value in fields(planet[1]))[2]
    radius, = struct.unpack("<f", planet[2])
    assert 6_000_000 < radius < 7_000_000
    bulk = list(fields(get(f"BulkMetadata/pb=!1m2!1s!2u{epoch}")))
    defaults = {field: value for field, _, value in bulk if field != 1}
    head = dict((field, value) for field, _, value in fields(defaults[2]))
    selected = None
    count = 0
    for field, _, value in bulk:
        if field != 1:
            continue
        count += 1
        metadata = dict((field, value) for field, _, value in fields(value))
        packed = metadata[1]
        depth, packed = 1 + (packed & 3), packed >> 2
        path = ""
        for _ in range(depth):
            path += str(packed & 7)
            packed >>= 3
        if path == "02":
            selected = metadata, packed
    assert selected, "COARSE_NODE_02_NOT_AVAILABLE"
    metadata, flags = selected
    node_epoch = metadata.get(2, head[2])
    imagery_epoch = metadata.get(7, defaults.get(5, 0))
    assert metadata.get(8, defaults.get(6, 0)) & 1, "JPEG_NOT_AVAILABLE"
    imagery = f"!3u{imagery_epoch}" if flags & 16 else ""
    packet = list(fields(get(f"NodeData/pb=!1m2!1s02!2u{node_epoch}!2e1{imagery}!4b0")))
    matrix = struct.unpack("<16d", next(value for field, _, value in packet if field == 1))
    assert all(math.isfinite(value) for value in matrix)
    mesh_count = triangles = 0
    for field, _, message in packet:
        if field != 2:
            continue
        mesh_count += 1
        mesh = dict((field, value) for field, _, value in fields(message))
        vertex_count = len(mesh[1]) // 3
        assert len(mesh[1]) % 3 == 0 and 3 <= vertex_count <= 65535
        assert len(mesh[7]) == 4 + vertex_count * 4
        size, offset = varint(mesh[3], 0)
        zeros, indices = 0, []
        for _ in range(size):
            delta, offset = varint(mesh[3], offset)
            index = zeros - delta
            assert 0 <= index < vertex_count
            indices.append(index)
            zeros += delta == 0
        assert offset == len(mesh[3])
        layers, offset = varint(mesh[8], 0)
        assert 1 <= layers <= 72
        counts = []
        for _ in range(layers):
            value, offset = varint(mesh[8], offset)
            counts.append(value)
        assert sum(counts) == size and offset == len(mesh[8])
        end = sum(counts[:24])
        triangles += sum(len(set(indices[i - 2:i + 1])) == 3 for i in range(2, end))
        texture = dict((field, value) for field, _, value in fields(mesh[6]))
        assert texture[2] == 1 and texture[1].startswith(b"\xff\xd8")
    assert mesh_count and triangles
    print(f"PASS live RockTree: epoch={epoch}, bulk_nodes={count}, node=02, imagery_epoch={imagery_epoch}, meshes={mesh_count}, terrain_triangles={triangles}")


if __name__ == "__main__":
    probe()
