#!/usr/bin/env python3
"""Prepares a copy of the project for the browser build (never the project itself): colour
textures are capped at 1024 px and normal / roughness / AO maps at 512 (they lose little and
it keeps the main pack under GitHub's 100 MB a file), and the island's big maps become WebP
(the heights losslessly).
    python3 tools/web/prepare.py <work copy>"""
import hashlib, os, re, shutil, sys
from PIL import Image

# the big maps take minutes to encode: keep the results, keyed by the source's content
CACHE = os.path.join(os.environ.get("TMPDIR", "/tmp"), "knightfall_web_cache")
os.makedirs(CACHE, exist_ok=True)


def cached(src, tag, make):
    h = hashlib.md5()
    with open(src, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    out = os.path.join(CACHE, "%s-%s.webp" % (tag, h.hexdigest()[:16]))
    if not os.path.exists(out):
        make(out + ".tmp")
        os.replace(out + ".tmp", out)
    return out

LIMIT = 1024
DETAIL = 512
DETAIL_MAP = re.compile(r"(nor|normal|arm|orm|rough|_ao|metal|spec)", re.I)
work = sys.argv[1]

capped = 0
for root, _dirs, files in os.walk(os.path.join(work, "assets")):
    if os.sep + "ui" in root:
        continue                      # the icon atlas is cut up by pixel: leave it whole
    for f in files:
        if not f.endswith(".import"):
            continue
        src = os.path.join(root, f[:-7])
        if not os.path.exists(src) or not src.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
            continue
        imp = os.path.join(root, f)
        txt = open(imp).read()
        if 'importer="texture"' not in txt:
            continue
        try:
            w, h = Image.open(src).size
        except Exception:
            continue
        cap = DETAIL if DETAIL_MAP.search(os.path.basename(src)) else LIMIT
        if max(w, h) <= cap:
            continue
        txt = re.sub(r"process/size_limit=\d+", "process/size_limit=%d" % cap, txt)
        open(imp, "w").write(txt)
        capped += 1
print("textures capped (colour %d px, detail maps %d px): %d" % (LIMIT, DETAIL, capped))

world = os.path.join(work, "world")
# the material atlases and the terrain's normal map: lossy WebP. The normal atlas goes to half size
# (512 px a material): lossy WebP smears a normal map's fine grain at any quality anyway.
for name, q, scale in [("tex_albedo", 82, 1), ("tex_normal", 88, 2), ("normal", 92, 1)]:
    src = os.path.join(world, name + ".png")
    if os.path.exists(src):
        def make(out, src=src, q=q, scale=scale):
            im = Image.open(src)
            if scale > 1:
                im = im.resize((im.width // scale, im.height // scale), Image.LANCZOS)
            im.save(out, "WEBP", quality=q, method=6)
        shutil.copyfile(cached(src, "%s-q%d-s%d" % (name, q, scale), make), os.path.join(world, name + ".webp"))
        os.remove(src)
        print("%s.webp %.1f MB" % (name, os.path.getsize(os.path.join(world, name + ".webp")) / 1048576))

# the heights: the float32 bytes themselves as the pixels of a lossless WebP, rounded to 1/64 m
# (which zeroes each float's lowest byte): 64 MB becomes about 7 and decodes straight back
src = os.path.join(world, "height.bin")
if os.path.exists(src):
    import numpy as np
    h = np.fromfile(src, dtype="<f4")
    n = int(round(len(h) ** 0.5))
    q = (np.round(h.astype(np.float64) * 64.0) / 64.0).astype("<f4")
    dst = os.path.join(world, "height.webp")

    def make(out):
        Image.frombuffer("RGBA", (n, n), q.tobytes(), "raw", "RGBA", 0, 1).save(out, "WEBP", lossless=True, quality=100, method=5, exact=True)
    shutil.copyfile(cached(src, "height-64", make), dst)
    back = np.asarray(Image.open(dst).convert("RGBA")).reshape(-1).view("<f4")
    assert np.array_equal(back, q), "height.webp does not decode to the same heights"
    os.remove(src)
    print("height.webp %.1f MB" % (os.path.getsize(dst) / 1048576))
