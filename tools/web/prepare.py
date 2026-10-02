#!/usr/bin/env python3
"""Prepares a copy of the project for the browser build (never the project itself): colour
textures are capped at 1024 px and normal / roughness / AO maps at 512 (they lose little and
it keeps the main pack under GitHub's 100 MB a file), and the island's big maps become WebP.
    python3 tools/web/prepare.py <work copy>"""
import os, re, sys
from PIL import Image

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
for name, q in [("tex_albedo", 88), ("tex_normal", 92), ("normal", 92)]:
    src = os.path.join(world, name + ".png")
    if os.path.exists(src):
        Image.open(src).save(os.path.join(world, name + ".webp"), "WEBP", quality=q, method=6)
        os.remove(src)
        print("%s.webp %.1f MB" % (name, os.path.getsize(os.path.join(world, name + ".webp")) / 1048576))
