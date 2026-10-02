#!/usr/bin/env python3
"""Knightfall Enlightened - offline world baker.

Builds the island of Aldmere (6.1 x 6.1 km) from a fixed seed and writes the
data Godot streams at runtime into godot/world/:
  height.bin   float32 4096x4096 terrain heights (1.5 m spacing)
  water.bin    float32 1024x1024 water-surface levels (ocean 0, lakes, rivers)
  flow.png     1024x1024 river flow directions (RG) + foam (B)
  splat0/1.png 2048x2048 terrain material weights
  biome.png    2048x2048 temperature, moisture, biome id, grass density
  veg.bin      tree / bush / rock instances
  map.png      painted world map
  world.json   settlements, building layouts, roads, bridges, rivers, lakes, POIs
Arrays are indexed [z][x]; world x = -3072 + col * cell, z = -3072 + row * cell.
"""
import json, heapq, math, os, time
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'world'))
os.makedirs(OUT, exist_ok=True)
SIZE = 6144.0; HALF = SIZE / 2
N = 4096; T = SIZE / N      # heightmap, 1.5 m
M = 2048; TM = SIZE / M     # macro / splat / biome, 3 m
C = 1024; TC = SIZE / C     # hydrology / water, 6 m
R = 512;  TR = SIZE / R     # road search grid, 12 m
t0 = time.time()
def log(*a): print('[%6.1fs]' % (time.time() - t0), *a, flush=True)
def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t)

# ----------------------------------------------------------------- noise
_G = np.array([[1, 1], [-1, 1], [1, -1], [-1, -1], [1.41, 0], [-1.41, 0], [0, 1.41], [0, -1.41]], np.float32) * 0.7071
def perlin(x, y, seed):
    p = np.random.RandomState(seed).permutation(256).astype(np.int32); p = np.concatenate([p, p])
    xf0 = np.floor(x); yf0 = np.floor(y)
    xi = xf0.astype(np.int32) & 255; yi = yf0.astype(np.int32) & 255
    xf = (x - xf0).astype(np.float32); yf = (y - yf0).astype(np.float32)
    u = xf * xf * xf * (xf * (xf * 6 - 15) + 10); v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
    def g(h, dx, dy):
        gg = _G[h & 7]; return gg[..., 0] * dx + gg[..., 1] * dy
    a = p[xi] + yi; b = p[xi + 1] + yi
    n00 = g(p[a], xf, yf); n01 = g(p[a + 1], xf, yf - 1); n10 = g(p[b], xf - 1, yf); n11 = g(p[b + 1], xf - 1, yf - 1)
    x1 = n00 + u * (n10 - n00); x2 = n01 + u * (n11 - n01)
    return (x1 + v * (x2 - x1)) * 1.4
def fbm(x, y, octaves, seed, lac=2.0, gain=0.5):
    s = np.zeros(x.shape, np.float32); a = 1.0; f = 1.0; nrm = 0.0
    for o in range(octaves):
        s += a * perlin(x * f + o * 7.31, y * f - o * 3.17, seed + o * 31); nrm += a; a *= gain; f *= lac
    return s / nrm
def ridged(x, y, octaves, seed):
    s = np.zeros(x.shape, np.float32); a = 1.0; f = 1.0; nrm = 0.0; w = np.ones(x.shape, np.float32)
    for o in range(octaves):
        n = 1.0 - np.abs(perlin(x * f + o * 1.7, y * f + o * 2.3, seed + o * 17)); n = n * n
        s += a * n * w; w = np.clip(n * 1.6, 0, 1); nrm += a; a *= 0.5; f *= 2.0
    return s / nrm
def grid(n):
    c = (-HALF + np.arange(n, dtype=np.float32) * (SIZE / n)).astype(np.float32)
    return np.meshgrid(c, c)
def up2(a):
    def ax(a, axis):
        a = np.moveaxis(a, axis, 0); n = a.shape[0]
        p = np.concatenate([a[:1], a, a[-1:], a[-1:]], 0)
        mid = (-p[0:n] + 9 * p[1:n + 1] + 9 * p[2:n + 2] - p[3:n + 3]) / 16.0
        out = np.empty((2 * n,) + a.shape[1:], np.float32); out[0::2] = a; out[1::2] = mid
        return np.moveaxis(out, 0, axis)
    return ax(ax(a.astype(np.float32), 0), 1)
def down(a, f):
    n = a.shape[0] // f; return a[:n * f, :n * f].reshape(n, f, n, f).mean((1, 3)).astype(np.float32)
def _box(a, r, axis):
    a = np.moveaxis(a, axis, 0); n = a.shape[0]
    p = np.concatenate([np.repeat(a[:1], r + 1, 0), a, np.repeat(a[-1:], r, 0)], 0)
    cs = np.cumsum(p, 0, dtype=np.float64)
    out = (cs[2 * r + 1:2 * r + 1 + n] - cs[:n]) / (2 * r + 1)
    return np.moveaxis(out.astype(np.float32), 0, axis)
def blur(a, r):
    """Approximate gaussian blur (3 box passes) with radius r cells."""
    r = max(1, int(r / 1.7))
    for _ in range(3): a = _box(_box(a, r, 0), r, 1)
    return a
def seg_dist(X, Z, pts):
    d = np.full(X.shape, 1e9, np.float32)
    for (ax_, az), (bx, bz) in zip(pts[:-1], pts[1:]):
        vx, vz = bx - ax_, bz - az; L2 = max(vx * vx + vz * vz, 1e-6)
        t = np.clip(((X - ax_) * vx + (Z - az) * vz) / L2, 0, 1)
        dx = X - (ax_ + t * vx); dz = Z - (az + t * vz); d = np.minimum(d, np.sqrt(dx * dx + dz * dz))
    return d
def ell(X, Z, cx, cz, rx, rz, warp=None):
    e = np.sqrt(((X - cx) / rx) ** 2 + ((Z - cz) / rz) ** 2)
    if warp is not None: e = e + warp
    return e
def l1_dist(mask):
    """Manhattan distance (in cells) to nearest True cell, vectorised."""
    big = 1e6
    d = np.where(mask, 0.0, big).astype(np.float64)
    n0, n1 = d.shape
    j = np.arange(n1, dtype=np.float64)
    d = np.minimum(d, np.minimum.accumulate(d - j, axis=1) + j)
    d = np.minimum(d, (np.minimum.accumulate((d + j)[:, ::-1], axis=1))[:, ::-1] - j)
    i = np.arange(n0, dtype=np.float64)[:, None]
    d = np.minimum(d, np.minimum.accumulate(d - i, axis=0) + i)
    d = np.minimum(d, (np.minimum.accumulate((d + i)[::-1, :], axis=0))[::-1, :] - i)
    return d.astype(np.float32)

# ----------------------------------------------------------------- design
RIVER_GUIDES = [
    ([(-60, -1250), (-200, -600), (-150, 0), (-60, 700), (120, 1500), (40, 2300), (60, 3000)], 210, 34),
    ([(-1700, -1450), (-1600, -800), (-1450, -200), (-1550, 400), (-2100, 900), (-2700, 1300), (-3100, 1450)], 190, 30),
    ([(1250, -1250), (1450, -650), (1500, -300), (1250, 400), (950, 1100), (800, 1900), (760, 2600), (760, 3100)], 200, 32),
]
LAKES = [  # name, x, z, radius, depth, island (dx, dz, r, h) or None
    ('Mirrormere', 1520, -320, 340, 18, (0, 0, 95, 8)),
    ('Silverpool', -1560, 380, 200, 12, None),
    ('Frostmere', -1720, -1480, 240, 12, (60, -40, 34, 5)),
    ('Oasis of Qadir', 1720, 1640, 140, 9, None),
    ('Highlake', 380, -1520, 150, 14, None),
]
SETTLEMENTS = [  # name, type, x, z, wants_water
    ('Kingsbridge', 'town', -330, 260, True), ('Frosthold', 'town', -1950, -1020, False), ('Sandmere', 'town', 1980, 1430, True),
    ('Oakshade', 'village', -1150, -150, False), ('Millbrook', 'village', 300, 1450, True), ('Ashford', 'village', 900, 350, False),
    ('Pinecrest', 'village', -760, -1020, False), ('Snowfall', 'village', -2150, -1560, False), ('Dunewatch', 'village', 1300, 1250, False),
    ('Gullhaven', 'village', -1850, 1950, False), ('Highmoor', 'village', 1750, -1250, False),
    ('Castle Ravenmoor', 'castle', 420, -430, False), ('Castle Wintermere', 'castle', -1050, -1880, False), ('Castle Sunspire', 'castle', 2550, 950, False),
    ('Blackthorn Ruins', 'ruin', -2150, 420, False), ('Isle Keep', 'ruin_keep', 1520, -320, False), ('Graystone Ruins', 'ruin', 450, -2150, False),
]
POIS = [  # name, type, x, z
    ('Westwatch Tower', 'watchtower', -650, 900), ('Eastwatch Tower', 'watchtower', 1650, 520), ('Old North Tower', 'tower_ruin', -300, -1720),
    ('Broken Tower', 'tower_ruin', 2450, -560), ('Circle of the Ancients', 'stone_circle', -1000, 1250), ('Thornwood Bandit Camp', 'bandit_camp', -2450, -560),
    ('Redrock Bandit Camp', 'bandit_camp', 1650, 2450), ("Saint Aldric's Shrine", 'shrine', 300, 2300), ('Old Ironvein Mine', 'mine', -180, -1400),
    ("Hunter's Lodge", 'cabin', -2650, -1250), ('Woodcutter Camp', 'camp', -1700, -500), ('Desert Well', 'well', 2150, 1950),
]

# ----------------------------------------------------------------- macro terrain (2048)
log('macro terrain')
X, Z = grid(M)
wx = fbm(X / 1900, Z / 1900, 4, 11) * 700 + fbm(X / 520, Z / 520, 3, 18) * 140
wz = fbm(X / 1900 + 40, Z / 1900 + 40, 4, 12) * 700 + fbm(X / 520 + 9, Z / 520 + 9, 3, 19) * 140
d = np.sqrt(((X + wx) / 2650) ** 2 + ((Z + wz - 40) / 2760) ** 2) + fbm(X / 380, Z / 380, 4, 13) * 0.045
land = np.clip((1.0 - d) * 6.5, -1.0, 1.0)
inland = np.clip(land * 3.0, 0, 1)
h = np.where(land > 0, land * 16.0, land * 50.0).astype(np.float32)
mw = fbm(X / 900 + 9, Z / 900 + 9, 3, 14) * 0.25
mtn_mask = np.maximum(sstep(1.0, 0.55, ell(X, Z, 150, -1780, 2500, 720, mw)), sstep(1.0, 0.5, ell(X, Z, 1750, -1350, 900, 560, mw)))
mtn_mask = np.maximum(mtn_mask, 0.55 * sstep(1.0, 0.4, ell(X, Z, -2350, -2050, 600, 450, mw)))
tun = sstep(1.0, 0.55, ell(X, Z, -1850, -1350, 1350, 1050, fbm(X / 800, Z / 800, 3, 15) * 0.2))
des = sstep(1.0, 0.55, ell(X, Z, 1950, 1650, 1450, 1250, fbm(X / 700, Z / 700, 3, 16) * 0.22))
forest_m = sstep(1.0, 0.45, ell(X, Z, -1450, 250, 1350, 1450, fbm(X / 600, Z / 600, 3, 17) * 0.3))
hills = (fbm(X / 950, Z / 950, 6, 21) * 0.5 + 0.5) * 58.0
hills *= (1.0 - 0.55 * des)
mtn = ridged(X / 1250 + 3.1, Z / 1250 + 7.7, 7, 31)
mtn = np.clip((mtn - 0.18) / 0.82, 0, 1) ** 1.45 * 600.0
foot = (fbm(X / 500, Z / 500, 5, 32) * 0.5 + 0.5) * 70.0
dn = fbm(X / 600, Z / 600, 3, 41)
dunes = (0.5 + 0.5 * np.sin((X * 0.8 + Z * 0.6) / 36.0 + dn * 6.0)) ** 2.2 * 8.0 + (fbm(X / 220, Z / 220, 3, 42) * 0.5 + 0.5) * 6.0
mesa = sstep(0.18, 0.26, fbm(X / 650, Z / 650, 4, 43)) * 34.0 + sstep(0.42, 0.48, fbm(X / 650, Z / 650, 4, 43)) * 22.0
h += inland * (hills + mtn * mtn_mask + foot * np.clip(mtn_mask * 2, 0, 1) + tun * (48 + fbm(X / 400, Z / 400, 4, 44) * 14) + des * (dunes + mesa))
def sample_grid(a, x, z, cell):
    fx = np.clip((np.asarray(x) + HALF) / cell, 0, a.shape[1] - 1.001); fz = np.clip((np.asarray(z) + HALF) / cell, 0, a.shape[0] - 1.001)
    i = fx.astype(np.int32); j = fz.astype(np.int32); tx = fx - i; tz = fz - j
    return (a[j, i] * (1 - tx) + a[j, i + 1] * tx) * (1 - tz) + (a[j + 1, i] * (1 - tx) + a[j + 1, i + 1] * tx) * tz
def resample(pts, step):
    out = [list(pts[0])]
    for a, b in zip(pts[:-1], pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1]); n = max(1, int(L / step))
        for k in range(1, n + 1): out.append([a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n])
    return out
for pts, w, depth in RIVER_GUIDES:
    P = resample(pts, 12.0)
    for _ in range(3): P = [P[0]] + [[(P[i-1][0] + 2 * P[i][0] + P[i+1][0]) / 4, (P[i-1][1] + 2 * P[i][1] + P[i+1][1]) / 4] for i in range(1, len(P) - 1)] + [P[-1]]
    px_ = np.array([q[0] for q in P], np.float32); pz_ = np.array([q[1] for q in P], np.float32)
    px_ += perlin(px_ / 300.0, pz_ / 300.0, 5) * 0  # keep path
    hs = sample_grid(h, px_, pz_, TM).astype(np.float64)
    prof = np.minimum.accumulate(hs - depth * 0.35)
    k = 15; prof = np.convolve(np.pad(prof, (k // 2, k // 2), mode='edge'), np.ones(k) / k, mode='valid'); prof = np.minimum.accumulate(prof)
    best = np.full(h.shape, 1e9, np.float32); pa = np.zeros(h.shape, np.float32)
    w = w * 0.55; reach = w * 3.0
    for kk in range(len(P) - 1):
        ax_, az = P[kk]; bx, bz = P[kk + 1]
        i0 = int(max((min(ax_, bx) - reach + HALF) / TM, 0)); i1 = int(min((max(ax_, bx) + reach + HALF) / TM + 1, M))
        j0 = int(max((min(az, bz) - reach + HALF) / TM, 0)); j1 = int(min((max(az, bz) + reach + HALF) / TM + 1, M))
        if i0 >= i1 or j0 >= j1: continue
        sx_ = X[j0:j1, i0:i1]; sz_ = Z[j0:j1, i0:i1]
        vx, vz = bx - ax_, bz - az; L2 = max(vx * vx + vz * vz, 1e-6)
        t = np.clip(((sx_ - ax_) * vx + (sz_ - az) * vz) / L2, 0, 1)
        dd = np.hypot(sx_ - (ax_ + t * vx), sz_ - (az + t * vz))
        bsub = best[j0:j1, i0:i1]; upd = dd < bsub
        bsub[upd] = dd[upd]; pa[j0:j1, i0:i1][upd] = (prof[kk] + (prof[kk + 1] - prof[kk]) * t)[upd]
    near = best < reach
    target = pa + (best / w) ** 1.5 * 20.0
    h = np.where(near, np.minimum(h, target * 1.0), h).astype(np.float32)
for name, lx, lz, lr, depth, isl in LAKES:
    dd = np.sqrt((X - lx) ** 2 + (Z - lz) ** 2) / lr
    dd = dd * (1.0 + fbm(X / (lr * 0.9), Z / (lr * 0.9), 3, int(lx) & 255) * 0.32)
    ring = (dd > 1.2) & (dd < 1.6)
    P = float(np.percentile(h[ring], 65)); P = max(P, 6.0)
    target = P + 2.5 * sstep(0.85, 1.15, dd)
    w = sstep(1.9, 1.25, dd)
    h = h * (1 - w) + target * w
    h -= depth * np.clip(1 - dd ** 2, 0, 1) ** 0.6
    if isl:
        ix_, iz_, ir, ih = isl
        di = np.sqrt((X - lx - ix_) ** 2 + (Z - lz - iz_) ** 2) / ir
        dome = P + ih * (1.0 - sstep(0.55, 1.0, di)) - 3.0 * sstep(0.95, 1.5, di)
        h = np.where(di < 1.5, np.maximum(h, dome), h)
log('macro done, range', float(h.min()), float(h.max()))

# ----------------------------------------------------------------- full res
log('full resolution')
H = up2(h)
XN, ZN = grid(N)
det = fbm(XN / 60.0, ZN / 60.0, 3, 51) * 1.6 + fbm(XN / 14.0, ZN / 14.0, 2, 52) * 0.35
mtnN = up2(mtn_mask); desN = up2(des)
H += det * (0.6 + 1.8 * mtnN) * (1.0 - 0.6 * desN) * np.clip(H / 4.0, 0, 1)
del det

# ----------------------------------------------------------------- hydrology (1024)
log('hydrology')
hc = down(H, 4)
moistC = down(np.clip(0.55 + fbm(X / 1200, Z / 1200, 3, 61) * 0.25 + forest_m * 0.35 - des * 0.75, 0.05, 1.0), 2)
NB = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
hl = hc.ravel().tolist(); filled = list(hl); closed = [False] * (C * C); parent = [-1] * (C * C)
ocean = hc <= 0.0
heap = []
for idx in np.flatnonzero(ocean).tolist(): closed[idx] = True
oc = ocean
coast = oc & ~(np.roll(oc, 1, 0) & np.roll(oc, -1, 0) & np.roll(oc, 1, 1) & np.roll(oc, -1, 1))
border = np.zeros_like(oc); border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
for idx in np.flatnonzero(coast | (border & ~oc)).tolist():
    closed[idx] = True; heapq.heappush(heap, (filled[idx], idx))
order = []
eps = 0.002
while heap:
    hv, c = heapq.heappop(heap); order.append(c)
    r, q = divmod(c, C)
    for dr, dq in NB:
        rr = r + dr; qq = q + dq
        if rr < 0 or rr >= C or qq < 0 or qq >= C: continue
        n = rr * C + qq
        if closed[n]: continue
        closed[n] = True
        nh = hl[n]
        if nh < hv + eps: nh = hv + eps
        filled[n] = nh; parent[n] = c
        heapq.heappush(heap, (nh, n))
filledA = np.array(filled, np.float32).reshape(C, C)
rain = (0.15 + moistC).ravel().tolist()
acc = list(rain)
for c in reversed(order):
    p = parent[c]
    if p >= 0: acc[p] += acc[c]
accA = np.array(acc, np.float32).reshape(C, C)
log('flood/accumulation done, max acc', float(accA.max()))
# lakes = filled depressions
depth = filledA - hc
lakecell = (depth > 0.6) & ~ocean
lab = np.zeros((C, C), np.int32); lakes = []
lc_idx = np.flatnonzero(lakecell); lcset = lakecell.ravel()
labf = lab.ravel()
cur = 0
for s in lc_idx.tolist():
    if labf[s]: continue
    cur += 1; stack = [s]; labf[s] = cur; cells = []
    while stack:
        c = stack.pop(); cells.append(c); r, q = divmod(c, C)
        for dr, dq in NB:
            rr = r + dr; qq = q + dq
            if 0 <= rr < C and 0 <= qq < C:
                n = rr * C + qq
                if lcset[n] and not labf[n]: labf[n] = cur; stack.append(n)
    lakes.append(cells)
water = np.zeros((C, C), np.float32)      # water surface level (0 = sea)
lake_info = []
lake_mask = np.zeros((C, C), bool)
desC = down(des, 2)
cands = []
for li, cells in enumerate(lakes):
    if len(cells) < 120: continue
    ca = np.array(cells); rr, qq = np.divmod(ca, C)
    cx = float(-HALF + qq.mean() * TC + 2.25); cz = float(-HALF + rr.mean() * TC + 2.25)
    name = None
    for nm, lx, lz, lr, *_ in LAKES:
        if (cx - lx) ** 2 + (cz - lz) ** 2 < (lr * 1.6) ** 2: name = nm
    if name is None and (len(cells) > 1500 or desC[int(rr.mean()), int(qq.mean())] > 0.3): continue
    cands.append((name is not None, len(cells), cells, cx, cz, name))
cands.sort(key=lambda c: (not c[0], -c[1]))
kept = [c for c in cands if c[0]] + [c for c in cands if not c[0]][:14]
for _, _, cells, cx, cz, name in kept:
    ca = np.array(cells); lvl = float(filledA.ravel()[ca].max())
    m = np.zeros(C * C, bool); m[ca] = True; m = m.reshape(C, C)
    lake_mask |= m
    water = np.where(m, lvl, water)
    lake_info.append(dict(name=name or 'Pond', x=round(cx, 1), z=round(cz, 1), level=round(lvl, 2), area=len(cells) * TC * TC,
                          radius=round(math.sqrt(len(cells) * TC * TC / math.pi), 1)))
log('lakes', len(lake_info), [l['name'] for l in lake_info if l['name'] != 'Pond'])
# rivers: trace network
THR = 5200.0
isriv = (accA >= THR) & ~ocean
rflat = isriv.ravel()
has_up = np.zeros(C * C, bool)
par = np.array(parent, np.int64)
src_cells = np.flatnonzero(rflat)
up_targets = par[src_cells]
has_up[up_targets[up_targets >= 0]] = True
sources = [c for c in src_cells.tolist() if not has_up[c]]
visited = np.zeros(C * C, bool)
rivers = []
accf = accA.ravel(); ff = filledA.ravel(); lmf = lake_mask.ravel(); ocf = ocean.ravel()
sources.sort(key=lambda c: -accf[c])
for s in sources:
    path = []; c = s
    while c >= 0:
        path.append(c)
        if visited[c] or ocf[c]: break
        visited[c] = True
        c = parent[c]
    if len(path) < 12: continue
    pts = []
    for c in path:
        r, q = divmod(c, C)
        pts.append([-HALF + q * TC + 2.25, -HALF + r * TC + 2.25, ff[c], accf[c], bool(lmf[c])])
    rivers.append(pts)
log('river polylines', len(rivers))
def chaikin(pts, it=3):
    for _ in range(it):
        out = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            out.append([0.75 * a[i] + 0.25 * b[i] for i in range(4)] + [a[4] and b[4]])
            out.append([0.25 * a[i] + 0.75 * b[i] for i in range(4)] + [a[4] and b[4]])
        out.append(pts[-1]); pts = out
    return pts
river_out = []
riv_dist_buf = np.full((C, C), 1e9, np.float32)
riv_hw_buf = np.zeros((C, C), np.float32)
flow = np.zeros((C, C, 3), np.float32)
Hc = H  # carve on full res
for pts in rivers:
    pts = chaikin(pts, 3)
    # enforce monotonic level downstream
    for i in range(1, len(pts)): pts[i][2] = min(pts[i][2], pts[i - 1][2])
    # resample ~3 m
    rs = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1]); n = max(1, int(L / 3.0))
        for k in range(1, n + 1):
            t = k / n; rs.append([a[i] + (b[i] - a[i]) * t for i in range(4)] + [b[4]])
    out = []
    for i, (x, z, lvl, ac, inlake) in enumerate(rs):
        hw = float(np.clip(2.5 + math.sqrt(ac / THR) * 3.2, 3.0, 13.0))
        out.append([round(x, 2), round(z, 2), round(lvl - 0.35, 2), round(hw, 2), inlake])
    river_out.append(out)
# carve rivers into full-res and stamp water/flow
log('carving rivers')
for out in river_out:
    for i, (x, z, lvl, hw, inlake) in enumerate(out):
        if inlake: continue
        j = min(i + 1, len(out) - 1); k = max(i - 1, 0)
        dx = out[j][0] - out[k][0]; dz = out[j][1] - out[k][1]; L = math.hypot(dx, dz) or 1.0
        slope = max(0.0, (out[k][2] - out[j][2]) / L)
        depth_c = 1.2 + hw * 0.12
        Rr = hw + 22.0
        ci = int(round((x + HALF) / T)); cj = int(round((z + HALF) / T)); rad = int(Rr / T) + 1
        i0, i1 = max(ci - rad, 0), min(ci + rad + 1, N); j0, j1 = max(cj - rad, 0), min(cj + rad + 1, N)
        if i0 >= i1 or j0 >= j1: continue
        gx = -HALF + np.arange(i0, i1) * T; gz = -HALF + np.arange(j0, j1) * T
        DX, DZ = np.meshgrid(gx - x, gz - z); dd = np.sqrt(DX * DX + DZ * DZ)
        bed = np.where(dd < hw, lvl - depth_c * (1 - (dd / hw) ** 2) - 0.25, lvl - 0.25 + (dd - hw) * 0.42)
        sub = Hc[j0:j1, i0:i1]
        Hc[j0:j1, i0:i1] = np.where(dd < Rr, np.minimum(sub, bed), sub)
        # water level (nearest-centerline assignment) on 1024 grid
        ci2 = int(round((x + HALF - 2.25) / TC)); cj2 = int(round((z + HALF - 2.25) / TC)); rw = int((hw + 14.0) / TC) + 1
        a0, a1 = max(ci2 - rw, 0), min(ci2 + rw + 1, C); b0, b1 = max(cj2 - rw, 0), min(cj2 + rw + 1, C)
        gx2 = -HALF + np.arange(a0, a1) * TC + 2.25; gz2 = -HALF + np.arange(b0, b1) * TC + 2.25
        DX2, DZ2 = np.meshgrid(gx2 - x, gz2 - z); d2 = np.sqrt(DX2 * DX2 + DZ2 * DZ2)
        buf = riv_dist_buf[b0:b1, a0:a1]
        upd = (d2 < hw + 14.0) & (d2 < buf) & ~lake_mask[b0:b1, a0:a1]
        buf[upd] = d2[upd]
        water[b0:b1, a0:a1][upd] = lvl
        riv_hw_buf[b0:b1, a0:a1][upd] = hw
        sp = float(np.clip(0.25 + slope * 14.0, 0.2, 1.0))
        fl = flow[b0:b1, a0:a1]
        fl[upd, 0] = dx / L * sp; fl[upd, 1] = dz / L * sp; fl[upd, 2] = np.clip(slope * 18.0, 0, 1)
H = Hc
# dilate lake levels so shores interpolate cleanly
for _ in range(3):
    m = water > 0
    for sh in [(1, 0), (-1, 0), (1, 1), (-1, 1)]:
        rolled = np.roll(water, sh[0], axis=sh[1])
        water = np.where(~m & (rolled > 0), np.maximum(water, rolled), water)
river_mask_c = riv_dist_buf < 1e8
dep_fill = (filledA - hc > 0.05) & ~lake_mask
fillN = np.repeat(np.repeat(np.where(dep_fill, filledA - 0.15, -1e3).astype(np.float32), 4, 0), 4, 1)
H = np.maximum(H, fillN)
wet_body = lake_mask | (riv_dist_buf < riv_hw_buf + 1.0)
log('rivers carved')

# ----------------------------------------------------------------- settlement sites
log('placing settlements')
hC = down(H, 4)
wet = lake_mask | ocean | (riv_dist_buf < 30.0) | (hC < 1.5)
wdist = l1_dist(wet) * TC  # meters (manhattan)
def sample_h(x, z):
    fx = (x + HALF) / T; fz = (z + HALF) / T
    i = int(np.clip(fx, 0, N - 2)); j = int(np.clip(fz, 0, N - 2)); tx = fx - i; tz = fz - j
    a = H[j, i] * (1 - tx) + H[j, i + 1] * tx; b = H[j + 1, i] * (1 - tx) + H[j + 1, i + 1] * tx
    return float(a * (1 - tz) + b * tz)
def sample_h_arr(x, z):
    fx = np.clip((x + HALF) / T, 0, N - 1.001); fz = np.clip((z + HALF) / T, 0, N - 1.001)
    i = fx.astype(np.int32); j = fz.astype(np.int32); tx = fx - i; tz = fz - j
    a = H[j, i] * (1 - tx) + H[j, i + 1] * tx; b = H[j + 1, i] * (1 - tx) + H[j + 1, i + 1] * tx
    return (a * (1 - tz) + b * tz).astype(np.float32)
def wdist_at(x, z):
    i = int(np.clip((x + HALF) / TC, 0, C - 1)); j = int(np.clip((z + HALF) / TC, 0, C - 1)); return float(wdist[j, i])
RADIUS = {'town': 135, 'village': 80, 'castle': 72, 'ruin': 66, 'ruin_keep': 40, 'watchtower': 16, 'tower_ruin': 16, 'stone_circle': 20,
          'bandit_camp': 28, 'shrine': 16, 'mine': 22, 'cabin': 20, 'camp': 22, 'well': 10}
def site_score(x, z, rad, kind, want_water, dx0):
    hs = [sample_h(x + math.cos(a) * rad * f, z + math.sin(a) * rad * f) for f in (0.0, 0.5, 0.95) for a in np.linspace(0, 2 * math.pi, 9)[:-1]]
    hs = np.array(hs); h0 = hs[0]
    if hs.min() < 3.0: return 1e9, h0
    wd = wdist_at(x, z)
    if wd < rad * 1.15: return 1e9, h0
    s = float(hs.std()) * 2.0 + dx0 / 120.0
    if want_water: s += max(0.0, wd - (rad * 1.15 + 120)) / 40.0
    if kind == 'castle': s -= (h0 - np.mean([sample_h(x + math.cos(a) * 260, z + math.sin(a) * 260) for a in np.linspace(0, 6.28, 7)])) * 0.08
    return s, h0
settlements = []
for name, kind, sx, sz, ww in SETTLEMENTS:
    rad = RADIUS[kind]
    if kind == 'ruin_keep':
        settlements.append(dict(name=name, type=kind, x=float(sx), z=float(sz), radius=rad)); continue
    best = (1e9, sx, sz)
    for r_ in np.arange(0, 420, 24):
        for a in np.linspace(0, 2 * math.pi, max(1, int(r_ / 18)) + 1)[:-1] if r_ > 0 else [0.0]:
            x = sx + math.cos(a) * r_; z = sz + math.sin(a) * r_
            if any((x - o['x']) ** 2 + (z - o['z']) ** 2 < (rad + o['radius'] + 120) ** 2 for o in settlements): continue
            sc, _ = site_score(x, z, rad, kind, ww, r_)
            if sc < best[0]: best = (sc, x, z)
    if best[0] >= 1e9: log('  WARN no site for', name)
    settlements.append(dict(name=name, type=kind, x=float(best[1]), z=float(best[2]), radius=rad))
pois = []
for name, kind, sx, sz in POIS:
    rad = RADIUS[kind]; best = (1e9, sx, sz)
    for r_ in np.arange(0, 300, 16):
        for a in np.linspace(0, 2 * math.pi, max(1, int(r_ / 14)) + 1)[:-1] if r_ > 0 else [0.0]:
            x = sx + math.cos(a) * r_; z = sz + math.sin(a) * r_
            if any((x - o['x']) ** 2 + (z - o['z']) ** 2 < (rad + o['radius'] + 60) ** 2 for o in settlements + pois): continue
            sc, _ = site_score(x, z, rad, kind, False, r_ * 0.5)
            if sc < best[0]: best = (sc, x, z)
    pois.append(dict(name=name, type=kind, x=float(best[1]), z=float(best[2]), radius=rad))
# flatten
def flatten(x, z, rad, pct, soft=1.35, keep_noise=0.25):
    ci = int((x + HALF) / T); cj = int((z + HALF) / T); rr = int(rad * soft / T) + 2
    i0, i1 = max(ci - rr, 0), min(ci + rr, N); j0, j1 = max(cj - rr, 0), min(cj + rr, N)
    gx = -HALF + np.arange(i0, i1) * T; gz = -HALF + np.arange(j0, j1) * T
    DX, DZ = np.meshgrid(gx - x, gz - z); dd = np.sqrt(DX * DX + DZ * DZ)
    sub = H[j0:j1, i0:i1]
    P = float(np.percentile(sub[dd < rad * 0.8], pct))
    w = sstep(rad * soft, rad * 0.95, dd)
    tgt = P + (sub - blur(sub, 6)) * keep_noise
    H[j0:j1, i0:i1] = sub * (1 - w) + tgt * w
    return P
for s in settlements:
    if s['type'] == 'ruin_keep':
        s['y'] = round(sample_h(s['x'], s['z']), 2); continue
    s['y'] = round(flatten(s['x'], s['z'], s['radius'], 70 if s['type'] in ('castle', 'ruin') else 50), 2)
for p in pois:
    p['y'] = round(flatten(p['x'], p['z'], p['radius'], 55, 1.6, 0.4), 2)
log('settlements placed')

# ----------------------------------------------------------------- roads
log('roads')
hR = down(H, 8)
wR = (down(lake_mask.astype(np.float32), 2) > 0.3) | (down(ocean.astype(np.float32), 2) > 0.3) | (hR < 1.0)
rivR = down(river_mask_c.astype(np.float32), 2) > 0.2
gyR, gxR = np.gradient(hR, TR)
slopeR = np.sqrt(gxR ** 2 + gyR ** 2)
XR_, ZR_ = grid(R)
rivChan = down((riv_dist_buf < riv_hw_buf + 3.0).astype(np.float32), 2) > 0.1
base_cost = 1.0 + (slopeR * 9.0) ** 2 + (fbm(XR_ / 260, ZR_ / 260, 3, 77) * 0.5 + 0.5) * 0.9 + np.where(rivChan, 70.0, np.where(rivR, 3.0, 0.0)) + np.where(up2(mtn_mask)[::8, ::8][:R, :R] > 0.6, 2.0, 0.0)
base_cost = np.where(wR, 1e6, base_cost).astype(np.float32)
road_bonus = np.zeros((R, R), bool)
def astar(a, b):
    ai = (int((a[1] + HALF) / TR), int((a[0] + HALF) / TR)); bi = (int((b[1] + HALF) / TR), int((b[0] + HALF) / TR))
    cost = base_cost
    g = {ai: 0.0}; came = {}; pq = [(0.0, ai)]
    while pq:
        f, cur = heapq.heappop(pq)
        if cur == bi: break
        gc = g[cur]
        for dr, dq in NB:
            nr, nq = cur[0] + dr, cur[1] + dq
            if not (0 <= nr < R and 0 <= nq < R): continue
            step = 1.4142 if dr and dq else 1.0
            cc = cost[nr, nq]
            if cc >= 1e5: continue
            if road_bonus[nr, nq]: cc = 0.55
            ng = gc + step * cc
            if ng < g.get((nr, nq), 1e18):
                g[(nr, nq)] = ng; came[(nr, nq)] = cur
                heapq.heappush(pq, (ng + math.hypot(nr - bi[0], nq - bi[1]) * 0.9, (nr, nq)))
    if bi not in came: return None
    path = [bi]
    while path[-1] != ai: path.append(came[path[-1]])
    path.reverse()
    for p_ in path: road_bonus[p_] = True
    return [[-HALF + q * TR + TR / 2, -HALF + r * TR + TR / 2] for r, q in path]
nodes = [s for s in settlements if s['type'] in ('town', 'village', 'castle')]
nodes += [p for p in pois if p['type'] in ('watchtower', 'shrine', 'mine', 'cabin', 'well')]
edges = set()
# minimum spanning tree + nearest extra links
import itertools
dd_ = lambda a, b: math.hypot(a['x'] - b['x'], a['z'] - b['z'])
inT = {0}; mst = []
while len(inT) < len(nodes):
    best = None
    for i in inT:
        for j in range(len(nodes)):
            if j in inT: continue
            dval = dd_(nodes[i], nodes[j])
            if best is None or dval < best[0]: best = (dval, i, j)
    inT.add(best[2]); edges.add(tuple(sorted((best[1], best[2]))))
for i, n in enumerate(nodes):
    if n['type'] not in ('town', 'village'): continue
    near = sorted([(dd_(n, m), j) for j, m in enumerate(nodes) if j != i and m['type'] in ('town', 'village', 'castle')])[:2]
    for dval, j in near:
        if dval < 2200: edges.add(tuple(sorted((i, j))))
roads = []
for i, j in sorted(edges, key=lambda e: dd_(nodes[e[0]], nodes[e[1]])):
    pth = astar((nodes[i]['x'], nodes[i]['z']), (nodes[j]['x'], nodes[j]['z']))
    if pth is None: log('  no road', nodes[i]['name'], nodes[j]['name']); continue
    roads.append(dict(a=nodes[i]['name'], b=nodes[j]['name'], pts=pth))
log('roads found', len(roads))
def smooth_line(pts, it=4):
    for _ in range(it):
        o = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            o.append([0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]]); o.append([0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]])
        o.append(pts[-1]); pts = o
    rs = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1]); n = max(1, int(L / 3.0))
        for k in range(1, n + 1): rs.append([a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n])
    return rs
def in_settlement(x, z, pad=1.0):
    for s in settlements:
        if (x - s['x']) ** 2 + (z - s['z']) ** 2 < (s['radius'] * pad) ** 2: return s
    return None
water_full_mask = lambda x, z: bool(wet_body[int(np.clip((z + HALF - 2.25) / TC + 0.5, 0, C - 1)), int(np.clip((x + HALF - 2.25) / TC + 0.5, 0, C - 1))])
bridges = []; road_out = []
road_mask = np.zeros((M, M), np.float32)
for rd in roads:
    pts = smooth_line(rd['pts'])
    ys = np.array([sample_h(x, z) for x, z in pts], np.float32)
    k = 9; ker = np.ones(k) / k
    ysm = np.convolve(np.pad(ys, (k // 2, k // 2), mode='edge'), ker, mode='valid')
    wet_pts = [water_full_mask(x, z) for x, z in pts]
    for q in range(1, len(wet_pts) - 1):
        if wet_pts[q] and not wet_pts[q - 1] and not wet_pts[q + 1]: wet_pts[q] = False
    q = 0
    while q < len(wet_pts):
        if wet_pts[q]:
            r_ = q + 1
            while r_ < len(wet_pts) and not wet_pts[r_] and r_ - q < 10: r_ += 1
            if r_ < len(wet_pts) and wet_pts[r_] and r_ - q > 1:
                for t_ in range(q, r_): wet_pts[t_] = True
            q = r_
        else: q += 1
    # bridges
    bridged = [False] * len(pts)
    i = 0
    while i < len(pts):
        if wet_pts[i]:
            j = i
            while j < len(pts) and wet_pts[j]: j += 1
            a = max(i - 3, 0); b = min(j + 2, len(pts) - 1)
            if (j - i) * 3.0 > 70.0: i = j + 1; continue
            ya = sample_h(*pts[a]); yb = sample_h(*pts[b])
            bridges.append(dict(a=[round(pts[a][0], 2), round(ya + 0.15, 2), round(pts[a][1], 2)], b=[round(pts[b][0], 2), round(yb + 0.15, 2), round(pts[b][1], 2)], width=5.0))
            for q in range(a, b + 1): bridged[q] = True
            i = b + 1
        else: i += 1
    outp = []
    for idx, ((x, z), y) in enumerate(zip(pts, ysm)):
        s = in_settlement(x, z, 0.9)
        outp.append([round(x, 2), round(float(y), 2), round(z, 2)])
        if bridged[idx] or wet_pts[idx] or s is not None: continue
        ci = int((x + HALF) / T); cj = int((z + HALF) / T); rr = 7
        i0, i1 = max(ci - rr, 0), min(ci + rr + 1, N); j0, j1 = max(cj - rr, 0), min(cj + rr + 1, N)
        gx = -HALF + np.arange(i0, i1) * T; gz = -HALF + np.arange(j0, j1) * T
        DX, DZ = np.meshgrid(gx - x, gz - z); dd = np.sqrt(DX * DX + DZ * DZ)
        w = sstep(9.5, 3.5, dd) * 0.85
        sub = H[j0:j1, i0:i1]; H[j0:j1, i0:i1] = sub * (1 - w) + float(y) * w
    road_out.append(dict(a=rd['a'], b=rd['b'], pts=outp))
    for x, y, z in outp:
        if in_settlement(x, z, 0.35): continue
        mi = (x + HALF) / TM; mj = (z + HALF) / TM
        i0, i1 = int(max(mi - 3, 0)), int(min(mi + 4, M)); j0, j1 = int(max(mj - 3, 0)), int(min(mj + 4, M))
        gx = np.arange(i0, i1) - mi; gz = np.arange(j0, j1) - mj
        DX, DZ = np.meshgrid(gx, gz); dd = np.sqrt(DX * DX + DZ * DZ) * TM
        road_mask[j0:j1, i0:i1] = np.maximum(road_mask[j0:j1, i0:i1], sstep(3.8, 1.6, dd))
log('bridges', len(bridges), 'wet_body frac', float(wet_body.mean()), 'lake frac', float(lake_mask.mean()))
for rd in road_out[:0]: pass
import collections
spans = collections.Counter(round(math.hypot(b['b'][0]-b['a'][0], b['b'][2]-b['a'][2]) / 10) * 10 for b in bridges)
log('bridge span histogram (m):', sorted(spans.items())[:20])

# ----------------------------------------------------------------- settlement layouts
log('settlement layouts')
STYLE = {}
def biome_at_macro(x, z):
    i = int(np.clip((x + HALF) / TM, 0, M - 1)); j = int(np.clip((z + HALF) / TM, 0, M - 1))
    return i, j
def obb(x, z, hw, hd, yaw):
    c, s_ = math.cos(yaw), math.sin(yaw)
    ax_ = (c, -s_); az_ = (s_, c)  # local x axis, local z axis in world (x,z)
    return (x, z, hw, hd, ax_, az_)
def obb_overlap(A, B):
    for axis in (A[4], A[5], B[4], B[5]):
        def proj(O):
            return abs(O[2] * (O[4][0] * axis[0] + O[4][1] * axis[1])) + abs(O[3] * (O[5][0] * axis[0] + O[5][1] * axis[1]))
        dist = abs((B[0] - A[0]) * axis[0] + (B[1] - A[1]) * axis[1])
        if dist > proj(A) + proj(B): return False
    return True
def road_near(x, z, r):
    mi = int((x + HALF) / TM); mj = int((z + HALF) / TM); k = int(r / TM) + 1
    sub = road_mask[max(mj - k, 0):mj + k + 1, max(mi - k, 0):mi + k + 1]
    return sub.size > 0 and sub.max() > 0.25
streets_mask = np.zeros((M, M), np.float32); cobble_mask = np.zeros((M, M), np.float32)
def paint(mask, x, z, r, val=1.0):
    mi = (x + HALF) / TM; mj = (z + HALF) / TM; k = int(r / TM) + 2
    i0, i1 = int(max(mi - k, 0)), int(min(mi + k + 1, M)); j0, j1 = int(max(mj - k, 0)), int(min(mj + k + 1, M))
    DX, DZ = np.meshgrid(np.arange(i0, i1) - mi, np.arange(j0, j1) - mj); dd = np.sqrt(DX * DX + DZ * DZ) * TM
    mask[j0:j1, i0:i1] = np.maximum(mask[j0:j1, i0:i1], sstep(r + 1.5, r - 1.0, dd) * val)
def paint_line(mask, a, b, r, val=1.0):
    L = math.hypot(b[0] - a[0], b[1] - a[1]); n = max(1, int(L / 2.0))
    for k in range(n + 1): paint(mask, a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n, r, val)
def road_entry_yaw(s):
    """Yaw (radians) pointing from settlement centre toward the first road leaving it."""
    best = None
    for rd in road_out:
        for pt in rd['pts']:
            dval = math.hypot(pt[0] - s['x'], pt[2] - s['z'])
            if s['radius'] * 1.0 < dval < s['radius'] * 1.5:
                best = math.atan2(pt[0] - s['x'], pt[2] - s['z']); break
        if best is not None: break
    return best if best is not None else 0.0
def make_layout(s, rng):
    kind = s['type']; cx, cz = s['x'], s['z']
    yaw = road_entry_yaw(s); s['yaw'] = round(yaw, 4)
    B = []; P = []
    def try_place(btype, w, d_, floors, positions, face_center=True, margin=2.2):
        for (x, z, yw) in positions:
            ob = obb(x, z, w / 2 + margin, d_ / 2 + margin, yw)
            if any(obb_overlap(ob, o['_obb']) for o in B): continue
            if road_near(x, z, max(w, d_) * 0.5 + 1.5) and kind != 'castle': continue
            B.append(dict(type=btype, x=round(x, 2), z=round(z, 2), yaw=round(yw, 4), w=w, d=d_, floors=floors, _obb=ob)); return True
        return False
    def ring_positions(n, rmin, rmax, jitter=0.25):
        out = []
        for _ in range(n):
            a = rng.uniform(0, 2 * math.pi); r_ = rng.uniform(rmin, rmax)
            x = cx + math.sin(a) * r_; z = cz + math.cos(a) * r_
            out.append((x, z, math.atan2(cx - x, cz - z) + rng.uniform(-jitter, jitter)))
        return out
    if kind == 'village':
        paint(streets_mask, cx, cz, 11)
        P.append(dict(type='well', x=round(cx, 2), z=round(cz, 2), yaw=0))
        plan = [('tavern', 8, 12, 2), ('blacksmith', 6, 8, 1), ('stable', 6, 10, 1), ('house', 6, 8, 2), ('house', 6, 8, 1), ('house', 4, 6, 1),
                ('house', 6, 10, 2), ('house', 4, 6, 1), ('house', 6, 6, 1), ('chapel', 6, 12, 1), ('shop', 6, 6, 1)]
        for bt, w, d_, fl in plan: try_place(bt, w, d_, fl, ring_positions(400, 18, s['radius'] * 0.82))
        for b in B: paint_line(streets_mask, (cx, cz), (b['x'] + math.sin(b['yaw']) * (b['d'] / 2 + 3), b['z'] + math.cos(b['yaw']) * (b['d'] / 2 + 3)), 2.0, 0.8)
        for k in range(2): P.append(dict(type='stall', x=round(cx + math.sin(yaw + 1.6 + k * 0.5) * 8, 2), z=round(cz + math.cos(yaw + 1.6 + k * 0.5) * 8, 2), yaw=round(yaw + 1.6 + k * 0.5 + math.pi, 3)))
        # farm fields outside
        for k in range(int(rng.randint(2, 5))):
            a = rng.uniform(0, 2 * math.pi); r_ = s['radius'] * rng.uniform(1.05, 1.5)
            fx = cx + math.sin(a) * r_; fz = cz + math.cos(a) * r_
            if road_near(fx, fz, 14) or wdist_at(fx, fz) < 20: continue
            P.append(dict(type='field', x=round(fx, 2), z=round(fz, 2), yaw=round(a, 3), w=int(rng.choice([16, 20, 24])), d=int(rng.choice([12, 16, 20]))))
    elif kind == 'town':
        ax_ = (math.sin(yaw), math.cos(yaw)); px_ = (math.cos(yaw), -math.sin(yaw))
        L = s['radius'] * 0.95
        paint(cobble_mask, cx, cz, 22)
        paint_line(streets_mask, (cx - ax_[0] * L, cz - ax_[1] * L), (cx + ax_[0] * L, cz + ax_[1] * L), 4.5)
        paint_line(streets_mask, (cx - px_[0] * L, cz - px_[1] * L), (cx + px_[0] * L, cz + px_[1] * L), 4.5)
        P.append(dict(type='well', x=round(cx, 2), z=round(cz, 2), yaw=0))
        P.append(dict(type='statue', x=round(cx + ax_[0] * 12, 2), z=round(cz + ax_[1] * 12, 2), yaw=round(yaw, 3)))
        for k in range(10):
            a = yaw + k * (2 * math.pi / 10) + 0.3; r_ = 15.0 if k % 2 else 18.0
            P.append(dict(type='stall', x=round(cx + math.sin(a) * r_, 2), z=round(cz + math.cos(a) * r_, 2), yaw=round(a + math.pi, 3)))
        plan = [('tavern', 8, 12, 2), ('tavern', 8, 10, 2), ('blacksmith', 6, 8, 1), ('stable', 6, 10, 1), ('stable', 6, 10, 1), ('chapel', 8, 14, 1),
                ('townhall', 8, 14, 2), ('barracks', 6, 12, 1), ('shop', 6, 8, 1), ('shop', 6, 6, 1), ('shop', 6, 8, 2), ('warehouse', 8, 10, 1)]
        plan += [('house', int(rng.choice([4, 6, 6, 8])), int(rng.choice([6, 8, 8, 10])), int(rng.choice([1, 2, 2]))) for _ in range(22)]
        slots = []
        for street_axis, street_perp in ((ax_, px_), (px_, ax_)):
            for side in (-1, 1):
                for t in np.arange(-L + 8, L - 6, 11.0):
                    if abs(t) < 26: continue
                    for depth_off in (11.0, 26.0):
                        bx = cx + street_axis[0] * t + street_perp[0] * side * depth_off
                        bz = cz + street_axis[1] * t + street_perp[1] * side * depth_off
                        if (bx - cx) ** 2 + (bz - cz) ** 2 > (s['radius'] * 0.95) ** 2: continue
                        face = math.atan2(-street_perp[0] * side, -street_perp[1] * side)
                        slots.append((bx, bz, face, depth_off))
        rng.shuffle(slots)
        slots.sort(key=lambda q: q[3])
        for bt, w, d_, fl in plan:
            cand = [(x, z, yw) for x, z, yw, _ in slots]
            if try_place(bt, w, d_, fl, cand, margin=1.4):
                b = B[-1]; slots = [q for q in slots if (q[0] - b['x']) ** 2 + (q[1] - b['z']) ** 2 > 36]
        for b in B: paint_line(streets_mask, (b['x'], b['z']), (b['x'] + math.sin(b['yaw']) * (b['d'] / 2 + 4), b['z'] + math.cos(b['yaw']) * (b['d'] / 2 + 4)), 1.8, 0.8)
        for k in range(int(rng.randint(3, 6))):
            a = rng.uniform(0, 2 * math.pi); r_ = s['radius'] * rng.uniform(1.05, 1.35)
            fx = cx + math.sin(a) * r_; fz = cz + math.cos(a) * r_
            if road_near(fx, fz, 14) or wdist_at(fx, fz) < 20: continue
            P.append(dict(type='field', x=round(fx, 2), z=round(fz, 2), yaw=round(a, 3), w=int(rng.choice([20, 24])), d=int(rng.choice([16, 20]))))
    elif kind in ('castle', 'ruin'):
        paint(cobble_mask, cx, cz, 30)
        def L2W(lx, lz):
            c_, s_ = math.cos(yaw), math.sin(yaw)
            return cx + lx * c_ + lz * s_, cz - lx * s_ + lz * c_
        parts = [('keep', 0, -13, 0.0, 8, 14, 3), ('kitchen', -16, 2, math.pi / 2, 6, 8, 1), ('barracks', 16, 0, -math.pi / 2, 6, 12, 1),
                 ('stable', 16, 15, -math.pi / 2, 6, 8, 1), ('mews', -16, 14, math.pi / 2, 4, 6, 1), ('chapel', -15, -12, math.pi / 2, 6, 8, 1)]
        for bt, lx, lz, ly, w, d_, fl in parts:
            x, z = L2W(lx, lz)
            B.append(dict(type=bt, x=round(x, 2), z=round(z, 2), yaw=round(yaw + ly, 4), w=w, d=d_, floors=fl, _obb=obb(x, z, w / 2, d_ / 2, yaw + ly)))
        for lx, lz, t_ in [(-6, 8, 'dummy'), (-3, 9, 'dummy'), (5, 8, 'weaponstand'), (8, 6, 'well'), (0, 20, 'cart'), (-9, -2, 'banner'), (9, -2, 'banner')]:
            x, z = L2W(lx, lz); P.append(dict(type=t_, x=round(x, 2), z=round(z, 2), yaw=round(yaw, 3)))
        if kind == 'ruin':
            for b in B: b['ruined'] = True
    elif kind == 'ruin_keep':
        B.append(dict(type='keep', x=round(cx, 2), z=round(cz, 2), yaw=0.0, w=8, d=8, floors=2, ruined=True, _obb=obb(cx, cz, 4, 4, 0)))
    for b in B: b.pop('_obb', None)
    s['buildings'] = B; s['props'] = P
rng_l = np.random.RandomState(99)
for s in settlements: make_layout(s, rng_l)
for p in pois: p['yaw'] = round(float(rng_l.uniform(0, 2 * math.pi)), 3)
log('layouts:', sum(len(s['buildings']) for s in settlements), 'buildings')

# ----------------------------------------------------------------- biome & splat (2048)
log('biomes & splat')
Hm = down(H, 2)
gy, gx = np.gradient(Hm, TM); slope = np.sqrt(gx * gx + gy * gy)
waterM = up2(water)[:M, :M]
under = (up2(wet_body.astype(np.float32))[:M, :M] > 0.5) & (waterM > Hm + 0.05)
temp = np.clip(0.18 + 0.8 * sstep(-2700, 1200, Z) - np.maximum(Hm - 40, 0) / 650.0 + des * 0.3 - tun * 0.24 + fbm(X / 900, Z / 900, 3, 71) * 0.08, 0, 1)
moist = np.clip(0.52 + fbm(X / 1100, Z / 1100, 4, 61) * 0.25 + forest_m * 0.38 - des * 0.8 + sstep(0.5, 0.0, slope) * 0.0, 0, 1)
snowline = 385 + fbm(X / 300, Z / 300, 3, 72) * 55
BEACH, PLAINS, FOREST, TUNDRA, MOUNTAIN, SNOW, DESERT, WATER = 1, 2, 3, 4, 5, 6, 7, 8
biome = np.full((M, M), PLAINS, np.uint8)
biome[moist > 0.62] = FOREST
biome[temp < 0.36] = TUNDRA
biome[(des > 0.5) & (temp > 0.4)] = DESERT
biome[(Hm > 190 + fbm(X / 400, Z / 400, 2, 73) * 40) & (mtn_mask > 0.2)] = MOUNTAIN
biome[(Hm > snowline) | ((temp < 0.16) & (Hm > 200))] = SNOW
biome[(Hm < 3.2) & (land < 0.35) & (biome != DESERT)] = BEACH
biome[under] = WATER
biome[Hm <= 0.0] = 0
n1 = fbm(X / 90, Z / 90, 3, 81) * 0.5 + 0.5; n2 = fbm(X / 40, Z / 40, 3, 82) * 0.5 + 0.5
W = np.zeros((8, M, M), np.float32)  # grass, forest, dry, dirt, rock, snow, sand, cobble
def setw(mask, **kw):
    idx = dict(grass=0, forest=1, dry=2, dirt=3, rock=4, snow=5, sand=6, cobble=7)
    for k, v in kw.items(): W[idx[k]] = np.where(mask, v, W[idx[k]])
setw(biome == PLAINS, grass=0.8 + 0.2 * n1, dry=np.clip(n2 - 0.55, 0, 1) * 1.2, dirt=np.clip(n1 - 0.8, 0, 1) * 1.5)
setw(biome == FOREST, grass=0.45 * n2, forest=0.6 + 0.4 * n1, dirt=np.clip(n2 - 0.75, 0, 1))
setw(biome == TUNDRA, dry=0.55 + 0.3 * n1, rock=np.clip(n2 - 0.55, 0, 1) * 1.4, snow=np.clip(n1 - 0.6, 0, 1) * 1.8 * sstep(0.36, 0.15, temp), grass=0.15)
setw(biome == MOUNTAIN, rock=0.75 + 0.25 * n2, dry=np.clip(0.5 - n2, 0, 1) * sstep(320, 200, Hm), snow=np.clip(n1 - 0.65, 0, 1) * sstep(200, 300, Hm) * 2)
setw(biome == SNOW, snow=1.0, rock=np.clip(n2 - 0.7, 0, 1) * 2)
setw(biome == DESERT, sand=0.85 + 0.15 * n1, rock=np.clip(n2 - 0.62, 0, 1) * 1.5 + sstep(0.35, 0.8, slope) * 1.2, dirt=np.clip(n1 - 0.7, 0, 1) * 0.8)
setw((biome == BEACH) | (biome == 0), sand=1.0)
setw(biome == WATER, sand=0.4, rock=0.4, dirt=0.4)
# road / street / plaza
rm = np.clip(road_mask + streets_mask, 0, 1)
for k in range(8): W[k] *= (1 - rm) * (1 - cobble_mask)
W[3] += rm * (1 - cobble_mask); W[7] += cobble_mask
# fields
fields_mask = np.zeros((M, M), np.float32)
for s in settlements:
    for p in s['props']:
        if p['type'] == 'field':
            c_, s_ = math.cos(p['yaw']), math.sin(p['yaw'])
            hw_, hd_ = p['w'] / 2, p['d'] / 2
            i0, i1 = int((p['x'] - 20 + HALF) / TM), int((p['x'] + 20 + HALF) / TM); j0, j1 = int((p['z'] - 20 + HALF) / TM), int((p['z'] + 20 + HALF) / TM)
            DX, DZ = np.meshgrid(-HALF + np.arange(i0, i1) * TM - p['x'], -HALF + np.arange(j0, j1) * TM - p['z'])
            lx = DX * c_ - DZ * s_; lz = DX * s_ + DZ * c_
            fm = sstep(hw_ + 1, hw_ - 0.5, np.abs(lx)) * sstep(hd_ + 1, hd_ - 0.5, np.abs(lz))
            fields_mask[j0:j1, i0:i1] = np.maximum(fields_mask[j0:j1, i0:i1], fm)
for k in range(8): W[k] *= (1 - fields_mask * 0.85)
W[3] += fields_mask * 0.85
tot = W.sum(0) + 1e-5; W /= tot
def save_rgba(arrs, path):
    img = np.stack([np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8) for a in arrs], -1)
    Image.fromarray(img).save(path, optimize=False, compress_level=3)
save_rgba(W[0:4], os.path.join(OUT, 'splat0.png')); save_rgba(W[4:8], os.path.join(OUT, 'splat1.png'))
grass = np.clip(W[0] * 1.0 + W[1] * 0.35 + W[2] * 0.8, 0, 1) * sstep(0.9, 0.5, slope) * (1 - under) * (1 - rm) * (1 - cobble_mask)
grass *= np.where(biome == DESERT, 0.08, 1.0) * np.where(biome == SNOW, 0.0, 1.0)
for s in settlements:
    for b in s['buildings']:
        paint(grass, b['x'], b['z'], max(b['w'], b['d']) * 0.6 + 1.0, 0.0) if False else None
bimg = np.stack([np.clip(temp * 255, 0, 255).astype(np.uint8), np.clip(moist * 255, 0, 255).astype(np.uint8), biome * 20, np.clip(grass * 255, 0, 255).astype(np.uint8)], -1)
Image.fromarray(bimg.astype(np.uint8)).save(os.path.join(OUT, 'biome.png'), compress_level=3)
log('splat written')

# ----------------------------------------------------------------- vegetation
log('vegetation')
SPECIES = [  # id, name, path, scale_min, scale_max, collision radius at scale 1 (0 = none), kind
    ('CommonTree_1', 'res://assets/nature/CommonTree_1.gltf', 1.7, 2.4, 0.35, 'tree'), ('CommonTree_2', 'res://assets/nature/CommonTree_2.gltf', 1.7, 2.4, 0.35, 'tree'),
    ('CommonTree_3', 'res://assets/nature/CommonTree_3.gltf', 1.6, 2.2, 0.3, 'tree'), ('CommonTree_4', 'res://assets/nature/CommonTree_4.gltf', 1.6, 2.2, 0.3, 'tree'),
    ('CommonTree_5', 'res://assets/nature/CommonTree_5.gltf', 1.7, 2.4, 0.35, 'tree'),
    ('Pine_1', 'res://assets/nature/Pine_1.gltf', 1.8, 2.7, 0.3, 'tree'), ('Pine_2', 'res://assets/nature/Pine_2.gltf', 1.8, 2.7, 0.3, 'tree'),
    ('Pine_3', 'res://assets/nature/Pine_3.gltf', 1.8, 2.7, 0.3, 'tree'), ('Pine_4', 'res://assets/nature/Pine_4.gltf', 1.6, 2.3, 0.3, 'tree'),
    ('Pine_5', 'res://assets/nature/Pine_5.gltf', 1.7, 2.5, 0.3, 'tree'),
    ('DeadTree_1', 'res://assets/nature/DeadTree_1.gltf', 1.1, 1.6, 0.3, 'tree'), ('DeadTree_2', 'res://assets/nature/DeadTree_2.gltf', 1.0, 1.4, 0.3, 'tree'),
    ('DeadTree_3', 'res://assets/nature/DeadTree_3.gltf', 0.9, 1.3, 0.3, 'tree'),
    ('TwistedTree_1', 'res://assets/nature/TwistedTree_1.gltf', 1.1, 1.5, 0.45, 'tree'), ('TwistedTree_3', 'res://assets/nature/TwistedTree_3.gltf', 1.1, 1.5, 0.45, 'tree'),
    ('palm_1', 'res://assets/plants/palm_1.glb', 1.0, 1.4, 0.25, 'tree'), ('palm_2', 'res://assets/plants/palm_2.glb', 1.0, 1.4, 0.25, 'tree'),
    ('palm_3', 'res://assets/plants/palm_3.glb', 1.0, 1.4, 0.25, 'tree'),
    ('Bush_Common', 'res://assets/nature/Bush_Common.gltf', 0.8, 1.5, 0.0, 'bush'), ('Bush_Common_Flowers', 'res://assets/nature/Bush_Common_Flowers.gltf', 0.8, 1.4, 0.0, 'bush'),
    ('Fern_1', 'res://assets/nature/Fern_1.gltf', 0.7, 1.3, 0.0, 'bush'), ('Plant_1_Big', 'res://assets/nature/Plant_1_Big.gltf', 0.7, 1.2, 0.0, 'bush'),
    ('Rock_Medium_1', 'res://assets/nature/Rock_Medium_1.gltf', 0.5, 2.6, 0.45, 'rock'), ('Rock_Medium_2', 'res://assets/nature/Rock_Medium_2.gltf', 0.5, 2.6, 0.45, 'rock'),
    ('Rock_Medium_3', 'res://assets/nature/Rock_Medium_3.gltf', 0.5, 2.6, 0.45, 'rock'),
]
SID = {s[0]: i for i, s in enumerate(SPECIES)}
rng_v = np.random.RandomState(4242)
STEP = 4.0; G = int(SIZE / STEP)
gx_ = -HALF + (np.arange(G) + 0.5) * STEP
GXv, GZv = np.meshgrid(gx_, gx_)
px = GXv + rng_v.uniform(-1.9, 1.9, GXv.shape); pz = GZv + rng_v.uniform(-1.9, 1.9, GZv.shape)
mi = np.clip(((px + HALF) / TM).astype(np.int32), 0, M - 1); mj = np.clip(((pz + HALF) / TM).astype(np.int32), 0, M - 1)
b_ = biome[mj, mi]; sl = slope[mj, mi]; hh = Hm[mj, mi]; wv = waterM[mj, mi]
clump = fbm(px / 140, pz / 140, 3, 91) * 0.5 + 0.5
blocked = (rm[mj, mi] > 0.05) | (cobble_mask[mj, mi] > 0.05) | (fields_mask[mj, mi] > 0.1) | (wv > hh - 0.6) | (hh < 1.5)
for s in settlements:
    blocked |= ((px - s['x']) ** 2 + (pz - s['z']) ** 2) < (s['radius'] * (0.95 if s['type'] != 'ruin' else 0.55)) ** 2
for p in pois:
    blocked |= ((px - p['x']) ** 2 + (pz - p['z']) ** 2) < (p['radius'] * 1.1) ** 2
for br in bridges:
    blocked |= seg_dist(px, pz, [(br['a'][0], br['a'][2]), (br['b'][0], br['b'][2])]) < 8
tree_d = np.zeros(px.shape, np.float32)  # trees per m2
tree_d = np.where(b_ == FOREST, 0.019 * sstep(0.22, 0.5, clump) + 0.002, tree_d)
tree_d = np.where(b_ == PLAINS, 0.0012 * sstep(0.55, 0.8, clump) + 0.00008, tree_d)
tree_d = np.where(b_ == TUNDRA, 0.0045 * sstep(0.35, 0.65, clump), tree_d)
tree_d = np.where(b_ == MOUNTAIN, 0.006 * sstep(330, 230, hh) * sstep(0.35, 0.6, clump), tree_d)
tree_d = np.where(b_ == DESERT, 0.00005, tree_d)
tree_d *= sstep(1.1, 0.6, sl)
dw = np.clip((wv - hh + 40.0) / 40.0, 0, 1)  # near water in desert -> palms
oasis = (b_ == DESERT) & (wv > 0.5) & (hh - wv < 6.0)
tree_d = np.where(oasis, 0.004, tree_d)
r1 = rng_v.uniform(0, 1, px.shape)
is_tree = (r1 < tree_d * STEP * STEP) & ~blocked
bush_d = np.select([b_ == FOREST, b_ == PLAINS, b_ == TUNDRA, b_ == MOUNTAIN, b_ == DESERT], [0.010, 0.0028, 0.002, 0.0012, 0.0006], 0.0) * sstep(1.0, 0.5, sl)
r2 = rng_v.uniform(0, 1, px.shape)
is_bush = (r2 < bush_d * STEP * STEP) & ~blocked & ~is_tree
rock_d = np.select([b_ == MOUNTAIN, b_ == TUNDRA, b_ == DESERT, b_ == FOREST, b_ == PLAINS, b_ == SNOW, b_ == BEACH], [0.0028, 0.0016, 0.0009, 0.0005, 0.00025, 0.0012, 0.0003], 0.0)
r3 = rng_v.uniform(0, 1, px.shape)
is_rock = (r3 < rock_d * STEP * STEP) & ~blocked & ~is_tree & ~is_bush
inst = {i: [] for i in range(len(SPECIES))}
sel = rng_v.uniform(0, 1, px.shape)
def add(mask, names, weights=None):
    idx = np.flatnonzero(mask.ravel())
    if idx.size == 0: return
    w = np.array(weights if weights else [1] * len(names), np.float64); w /= w.sum()
    choice = np.searchsorted(np.cumsum(w), sel.ravel()[idx])
    choice = np.clip(choice, 0, len(names) - 1)
    for k, nm in enumerate(names):
        ii = idx[choice == k]
        if ii.size: inst[SID[nm]].append(ii)
add(is_tree & (b_ == FOREST) & (n1[mj, mi] > 0.42), ['CommonTree_1', 'CommonTree_2', 'CommonTree_3', 'CommonTree_4', 'CommonTree_5', 'TwistedTree_1', 'TwistedTree_3', 'Pine_2'], [3, 3, 2, 2, 3, 0.25, 0.25, 1])
add(is_tree & (b_ == FOREST) & (n1[mj, mi] <= 0.42), ['Pine_1', 'Pine_2', 'Pine_3', 'CommonTree_3', 'CommonTree_4', 'DeadTree_1'], [3, 3, 2, 1, 1, 0.2])
add(is_tree & (b_ == PLAINS), ['CommonTree_1', 'CommonTree_2', 'CommonTree_5', 'CommonTree_3', 'TwistedTree_3'], [3, 3, 3, 1, 0.3])
add(is_tree & ((b_ == TUNDRA) | (b_ == MOUNTAIN)), ['Pine_1', 'Pine_2', 'Pine_3', 'Pine_4', 'Pine_5', 'DeadTree_2'], [3, 3, 2, 2, 2, 0.6])
add(is_tree & (b_ == DESERT) & ~oasis, ['DeadTree_1', 'DeadTree_3'], [1, 1])
add(is_tree & oasis, ['palm_1', 'palm_2', 'palm_3'])
add(is_bush & (b_ == FOREST), ['Bush_Common', 'Fern_1', 'Plant_1_Big', 'Bush_Common_Flowers'], [3, 4, 1, 1])
add(is_bush & (b_ == PLAINS), ['Bush_Common', 'Bush_Common_Flowers'], [2, 1])
add(is_bush & ((b_ == TUNDRA) | (b_ == MOUNTAIN) | (b_ == DESERT)), ['Bush_Common'])
add(is_rock, ['Rock_Medium_1', 'Rock_Medium_2', 'Rock_Medium_3'])
# ruins get overgrowth
for s in settlements:
    if s['type'] in ('ruin',):
        for k in range(40):
            a = rng_v.uniform(0, 6.283); r_ = rng_v.uniform(10, s['radius'] * 0.9)
            x = s['x'] + math.sin(a) * r_; z = s['z'] + math.cos(a) * r_
            j = int(np.clip((z + HALF) / STEP, 0, G - 1)); i = int(np.clip((x + HALF) / STEP, 0, G - 1))
            px[j, i] = x; pz[j, i] = z
            inst[SID[rng_v.choice(['Bush_Common', 'Fern_1', 'Bush_Common']) if k % 4 else 'CommonTree_3']].append(np.array([j * G + i]))
total = 0
with open(os.path.join(OUT, 'veg.bin'), 'wb') as f:
    f.write(np.array([len(SPECIES)], np.int32).tobytes())
    for sid, (nm, path, smin, smax, crad, kind) in enumerate(SPECIES):
        idx = np.concatenate(inst[sid]) if inst[sid] else np.zeros(0, np.int64)
        x = px.ravel()[idx]; z = pz.ravel()[idx]
        y = sample_h_arr(x, z) if idx.size else np.zeros(0, np.float32)
        rot = rng_v.uniform(0, 2 * math.pi, idx.size); sc = rng_v.uniform(smin, smax, idx.size)
        if kind == 'rock': y -= sc * 0.35
        arr = np.stack([x, y, z, rot, sc], -1).astype(np.float32) if idx.size else np.zeros((0, 5), np.float32)
        f.write(np.array([sid, idx.size], np.int32).tobytes()); f.write(arr.tobytes()); total += idx.size
log('vegetation instances', total)

# ----------------------------------------------------------------- outputs
log('writing height / water')
H.astype('<f4').tofile(os.path.join(OUT, 'height.bin'))
water.astype('<f4').tofile(os.path.join(OUT, 'water.bin'))
fl = np.zeros((C, C, 3), np.uint8)
fl[..., 0] = np.clip(flow[..., 0] * 127 + 128, 0, 255); fl[..., 1] = np.clip(flow[..., 1] * 127 + 128, 0, 255); fl[..., 2] = np.clip(flow[..., 2] * 255, 0, 255)
Image.fromarray(fl).save(os.path.join(OUT, 'flow.png'))
# painted map
log('map')
Hm2 = down(H, 2)
gy2, gx2 = np.gradient(Hm2, TM)
shade = np.clip(0.75 + (-gx2 * 0.7 - gy2 * 0.7) * 1.6, 0.35, 1.25)
pal = {0: (54, 82, 110), BEACH: (214, 196, 150), PLAINS: (150, 160, 96), FOREST: (84, 112, 62), TUNDRA: (158, 160, 140), MOUNTAIN: (130, 120, 108), SNOW: (236, 238, 240),
       DESERT: (214, 180, 120), WATER: (70, 108, 140)}
col = np.zeros((M, M, 3), np.float32)
for k, v in pal.items(): col[biome == k] = v
col = col * shade[..., None]
col[biome == 0] = (np.array(pal[0]) * (0.8 + 0.2 * np.clip(Hm2[biome == 0][:, None] / -40 + 1, 0, 1)))
col[biome == WATER] = pal[WATER]
col = col * (1 - rm[..., None] * 0.6) + np.array([120, 92, 60]) * rm[..., None] * 0.6
col = col * (1 - cobble_mask[..., None] * 0.6) + np.array([110, 100, 90]) * cobble_mask[..., None] * 0.6
paper = (fbm(X / 30, Z / 30, 3, 99) * 0.5 + 0.5)[..., None]
col = col * (0.92 + paper * 0.12)
col = col * 0.85 + np.array([235, 215, 170]) * 0.15
Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).save(os.path.join(OUT, 'map.png'))
# json
spawn = next(s for s in settlements if s['name'] == 'Kingsbridge')
world = dict(size=SIZE, hm_res=N, texel=T, water_res=C, splat_res=M, sea_level=0.0,
             spawn=dict(x=round(spawn['x'] + 60, 2), z=round(spawn['z'] + 70, 2)),
             species=[dict(name=s[0], path=s[1], radius=s[4], kind=s[5]) for s in SPECIES],
             settlements=settlements, pois=pois, roads=road_out, bridges=bridges,
             rivers=[[[p[0], p[1], p[2], p[3]] for p in r[::4]] for r in river_out], lakes=lake_info,
             regions=[dict(name='The Frostlands', x=-1900, z=-1400), dict(name='Greyspine Mountains', x=300, z=-1850), dict(name='Thornwood Forest', x=-1500, z=200),
                      dict(name='The Heartland', x=200, z=500), dict(name='Qadir Desert', x=1900, z=1600), dict(name='Silver Coast', x=-1800, z=2100)])
def _np(o):
    if isinstance(o, (np.floating,)): return round(float(o), 3)
    if isinstance(o, (np.integer,)): return int(o)
    if isinstance(o, np.bool_): return bool(o)
    raise TypeError(type(o))
with open(os.path.join(OUT, 'world.json'), 'w') as f: json.dump(world, f, separators=(',', ':'), default=_np)
log('done.', 'height range', float(H.min()), float(H.max()))
