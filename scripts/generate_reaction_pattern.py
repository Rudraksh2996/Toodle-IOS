#!/usr/bin/env python3
"""Bake a tiny Gray–Scott reaction-diffusion mask for transient loading states."""
import pathlib
import random
import struct
import zlib

SIZE = 64
randomizer = random.Random(370)  # Tok.noiseSeed (0.37) on a stable integer scale.
u = [1.0] * (SIZE * SIZE)
v = [0.0] * (SIZE * SIZE)
for _ in range(18):
    center_x = randomizer.randrange(SIZE)
    center_y = randomizer.randrange(SIZE)
    for offset_y in range(-2, 3):
        for offset_x in range(-2, 3):
            index = ((center_y + offset_y) % SIZE) * SIZE + (center_x + offset_x) % SIZE
            u[index], v[index] = 0.5, 0.25

for _ in range(420):
    next_u, next_v = u.copy(), v.copy()
    for y in range(SIZE):
        for x in range(SIZE):
            i = y * SIZE + x
            neighbors = (
                y * SIZE + (x - 1) % SIZE,
                y * SIZE + (x + 1) % SIZE,
                ((y - 1) % SIZE) * SIZE + x,
                ((y + 1) % SIZE) * SIZE + x,
            )
            lap_u = sum(u[n] for n in neighbors) - 4 * u[i]
            lap_v = sum(v[n] for n in neighbors) - 4 * v[i]
            reaction = u[i] * v[i] * v[i]
            next_u[i] = max(0, min(1, u[i] + 0.16 * lap_u - reaction + 0.035 * (1 - u[i])))
            next_v[i] = max(0, min(1, v[i] + 0.08 * lap_v + reaction - (0.035 + 0.065) * v[i]))
    u, v = next_u, next_v

rows = []
for y in range(SIZE):
    row = bytearray([0])  # PNG filter: none.
    for x in range(SIZE):
        alpha = max(0, min(255, round((v[y * SIZE + x] - 0.025) * 1150)))
        row.extend((255, 255, 255, alpha))
    rows.append(row)

def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
       + chunk(b"IEND", b""))
target = pathlib.Path(__file__).resolve().parent.parent / "Toodle/Resources/Assets.xcassets/ReactionPattern.imageset/pattern.png"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(png)
print(target)
