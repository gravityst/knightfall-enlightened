#!/usr/bin/env python3
"""Packs Poly Haven terrain materials into 4x4 atlases (loaded as Texture2DArrays at runtime)
and bakes the terrain normal map + quadtree min/max table from world/height.bin."""
import os, numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
SRC = '/private/tmp/claude-501/-Users-curtis-Documents-Documents---macstudio-CalebDevelops-Knightfall/6f457a99-4795-4180-b015-80cdab47186a/scratchpad/dl2/tex'
OUT = os.path.join(ROOT, 'world')
LAYERS = ['leafy_grass', 'forest_floor', 'withered_grass', 'stony_dirt_path', 'rocky_terrain_02', 'snow_02', 'aerial_sand',
          'cobblestone_01', 'cliff_side', 'brown_mud_02', 'river_small_rocks', 'dry_ground_01', 'coast_sand_01']
TS = 1024
def load(name, kind, mode):
    for ext in ('jpg', 'png'):
        p = os.path.join(SRC, f'{name}_{kind}.{ext}')
        if os.path.exists(p): return Image.open(p).convert(mode).resize((TS, TS), Image.LANCZOS)
    return None
if os.path.isdir(SRC):
    alb = Image.new('RGBA', (TS * 4, TS * 4)); nrm = Image.new('RGBA', (TS * 4, TS * 4))
    for i, name in enumerate(LAYERS):
        x, y = (i % 4) * TS, (i // 4) * TS
        d = np.asarray(load(name, 'diff', 'RGB'), np.uint8)
        h = load(name, 'disp', 'L'); h = np.asarray(h, np.uint8) if h else np.full((TS, TS), 128, np.uint8)
        alb.paste(Image.fromarray(np.dstack([d, h])), (x, y))
        n = np.asarray(load(name, 'nor', 'RGB'), np.uint8)
        r = load(name, 'rough', 'L'); r = np.asarray(r, np.uint8) if r else np.full((TS, TS), 200, np.uint8)
        a = load(name, 'ao', 'L'); a = np.asarray(a, np.uint8) if a else np.full((TS, TS), 255, np.uint8)
        nrm.paste(Image.fromarray(np.dstack([n[..., 0], n[..., 1], r, a])), (x, y))
        print('layer', i, name)
    alb.save(os.path.join(OUT, 'tex_albedo.png')); nrm.save(os.path.join(OUT, 'tex_normal.png'))
# normal map + minmax
N = 4096; T = 1.5
H = np.fromfile(os.path.join(OUT, 'height.bin'), '<f4').reshape(N, N)
gz, gx = np.gradient(H, T)
nx, ny, nz = -gx, np.ones_like(gx), -gz
l = np.sqrt(nx * nx + ny * ny + nz * nz)
img = np.dstack([(nx / l * 0.5 + 0.5) * 255, (nz / l * 0.5 + 0.5) * 255, (ny / l) * 255]).astype(np.uint8)
Image.fromarray(img).save(os.path.join(OUT, 'normal.png'), compress_level=3)
# quadtree leaf min/max: 256x256 leaves of 32 m over the 8192 m root [-4096, 4096)
L = 256; mm = np.zeros((L, L, 2), np.float32); mm[..., 0] = -60; mm[..., 1] = 0
for j in range(L):
    z0 = -4096 + j * 32
    jz0 = int(np.floor((z0 + 3072) / T)); jz1 = int(np.ceil((z0 + 32 + 3072) / T)) + 1
    if jz1 <= 0 or jz0 >= N: continue
    rows = H[max(jz0, 0):min(jz1, N)]
    for i in range(L):
        x0 = -4096 + i * 32
        ix0 = int(np.floor((x0 + 3072) / T)); ix1 = int(np.ceil((x0 + 32 + 3072) / T)) + 1
        if ix1 <= 0 or ix0 >= N: continue
        blk = rows[:, max(ix0, 0):min(ix1, N)]
        mm[j, i] = (min(blk.min(), 0.0) if (ix0 < 0 or ix1 > N or jz0 < 0 or jz1 > N) else blk.min(), max(blk.max(), 0.0))
mm.astype('<f4').tofile(os.path.join(OUT, 'minmax.bin'))
open(os.path.join(OUT, '.gdignore'), 'w').close()
print('done')
