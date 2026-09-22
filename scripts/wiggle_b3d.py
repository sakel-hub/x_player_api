#!/usr/bin/env python3
"""
B3D Model Rotation Wiggler for Luanti
Mitigates Irrlicht skeletal animation matrix decomposition bug (Issue #15692).

When a bone has a perfect 180° rotation around a cardinal axis, Irrlicht's
CMatrix4<T>::getScale() optimization treats zero off-diagonals as an unrotated
matrix and returns a negative scale, decomposing 180° into Identity rotation + Negative scale.
This script perturbs perfect rotations by ±0.001 to force Irrlicht to execute full
Euclidean column-length calculation (scale = 1.0, 1.0, 1.0).

Usage:
    python3 scripts/wiggle_b3d.py <input_b3d> [output_b3d]
    If output_b3d is omitted, modifies in-place.
"""

import sys
import os
import struct
import math


def is_perfect_rotation(w: float, x: float, y: float, z: float) -> bool:
    """
    Check if rotation quaternion decomposes into a 3x3 matrix with zero off-diagonals.
    quat = [x, y, z, w]
    """
    # Exclude identity rotation (angle 0)
    if abs(x) + abs(y) + abs(z) < 1e-5:
        return False
    m11 = 1.0 - 2.0 * (y * y + z * z)
    m22 = 1.0 - 2.0 * (x * x + z * z)
    m33 = 1.0 - 2.0 * (x * x + y * y)
    diag_abs_sum = abs(m11) + abs(m22) + abs(m33)
    return abs(diag_abs_sum - 3.0) < 1e-5


def wiggle_quaternion(w: float, x: float, y: float, z: float) -> tuple:
    """
    Perturb a perfect rotation quaternion by ±1e-3 and normalize.
    """
    if not is_perfect_rotation(w, x, y, z):
        return w, x, y, z

    quat = [x, y, z, w]
    for sign in (1.0, -1.0):
        wiggled = [c + sign * 1e-3 for c in quat]
        length = math.sqrt(sum(c * c for c in wiggled))
        if length > 0.0:
            normed = [c / length for c in wiggled]
            # Verify that perturbed quaternion is no longer classified as perfect
            if not is_perfect_rotation(normed[3], normed[0], normed[1], normed[2]):
                return normed[3], normed[0], normed[1], normed[2]

    return w, x, y, z


def process_b3d_data(raw_bytes: bytes) -> tuple:
    """
    Parse B3D chunks and wiggle all perfect NODE and KEYS rotation quaternions.
    Returns: (modified_bytes, nodes_wiggled, keys_wiggled)
    """
    data = bytearray(raw_bytes)
    if len(data) < 12:
        raise ValueError("Invalid B3D file: data too short")

    tag = data[:4]
    if tag != b"BB3D":
        raise ValueError(f"Invalid B3D header tag: {tag!r}")

    total_size, version = struct.unpack("<II", data[4:12])
    nodes_wiggled = 0
    keys_wiggled = 0

    def walk_chunks(start: int, end: int):
        nonlocal nodes_wiggled, keys_wiggled
        pos = start
        while pos < end:
            if pos + 8 > end:
                break
            chunk_tag = data[pos:pos+4].decode("latin1", "ignore")
            chunk_size = struct.unpack("<I", data[pos+4:pos+8])[0]
            payload_start = pos + 8
            payload_end = payload_start + chunk_size
            if payload_end > len(data):
                break

            if chunk_tag == "NODE":
                nend = data.find(b"\0", payload_start)
                if nend != -1 and nend < payload_end:
                    rot_offset = nend + 1 + 12 + 12
                    if rot_offset + 16 <= payload_end:
                        w, x, y, z = struct.unpack("<4f", data[rot_offset:rot_offset+16])
                        if is_perfect_rotation(w, x, y, z):
                            nw, nx, ny, nz = wiggle_quaternion(w, x, y, z)
                            data[rot_offset:rot_offset+16] = struct.pack("<4f", nw, nx, ny, nz)
                            nodes_wiggled += 1
                        sub_start = rot_offset + 16
                        walk_chunks(sub_start, payload_end)
            elif chunk_tag == "KEYS":
                if payload_start + 4 <= payload_end:
                    flags = struct.unpack("<I", data[payload_start:payload_start+4])[0]
                    k_pos = payload_start + 4
                    while k_pos < payload_end:
                        k_pos += 4  # frame (uint32)
                        if flags & 1:
                            k_pos += 12  # pos
                        if flags & 2:
                            k_pos += 12  # scale
                        if flags & 4:
                            if k_pos + 16 <= payload_end:
                                rot_offset = k_pos
                                w, x, y, z = struct.unpack("<4f", data[rot_offset:rot_offset+16])
                                if is_perfect_rotation(w, x, y, z):
                                    nw, nx, ny, nz = wiggle_quaternion(w, x, y, z)
                                    data[rot_offset:rot_offset+16] = struct.pack("<4f", nw, nx, ny, nz)
                                    keys_wiggled += 1
                            k_pos += 16

            pos = payload_end

    walk_chunks(12, len(data))
    return bytes(data), nodes_wiggled, keys_wiggled


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input_b3d> [output_b3d]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path

    if not os.path.isfile(input_path):
        print(f"Error: input file '{input_path}' not found")
        sys.exit(1)

    with open(input_path, "rb") as f:
        original_data = f.read()

    patched_data, nodes_count, keys_count = process_b3d_data(original_data)
    print(f"Processed '{input_path}':")
    print(f"  - Nodes wiggled: {nodes_count}")
    print(f"  - Keyframes wiggled: {keys_count}")

    with open(output_path, "wb") as f:
        f.write(patched_data)

    print(f"Successfully saved to '{output_path}' ({len(patched_data)} bytes).")


if __name__ == "__main__":
    main()
