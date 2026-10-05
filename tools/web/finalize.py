#!/usr/bin/env python3
"""Finishes the browser build in <out dir>:
  * every big file is named by its content (kf-<hash>.wasm, kf-<hash>.pck, data1-<hash>.pck ...),
    so a new version only re-downloads what really changed and a stale file is never served;
  * sw.js, a service worker, keeps those files in the browser's own storage. Browsers' download
    caches skip files this large, so without it every visit fetched the whole game again.
    python3 tools/web/finalize.py <out dir>"""
import hashlib, json, os, re, sys

out = sys.argv[1]


def digest(*names):
    h = hashlib.md5()
    for n in names:
        with open(os.path.join(out, n), "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()[:10]


ENGINE_FILES = ["index.js", "index.wasm", "index.audio.worklet.js", "index.audio.position.worklet.js"]
engine = "kf-" + digest(*ENGINE_FILES)
pack = "kf-" + digest("index.pck") + ".pck"
mpack = "kf-" + digest("index.mobile.pck") + ".pck"      # the same game with phones' ETC2 textures
for f in ENGINE_FILES:
    os.replace(os.path.join(out, f), os.path.join(out, engine + f[len("index"):]))
os.replace(os.path.join(out, "index.pck"), os.path.join(out, pack))
os.replace(os.path.join(out, "index.mobile.pck"), os.path.join(out, mpack))

html_path = os.path.join(out, "index.html")
html = open(html_path).read()
html = html.replace('<script src="index.js"></script>', '<script>window.KF_MOBILE_PACK = "%s";</script>\n\t\t<script src="%s.js"></script>' % (mpack, engine))
# start the engine through the service-worker hook in the page's head (export_presets.cfg)
assert "const engine = new Engine(GODOT_CONFIG);" in html
html = html.replace("const engine = new Engine(GODOT_CONFIG);", "const engine = kfWrapEngine(new Engine(GODOT_CONFIG));")
m = re.search(r"const GODOT_CONFIG = (\{.*?\});\n", html)
config = json.loads(m.group(1))
config["executable"] = engine
config["mainPack"] = pack
config["fileSizes"] = {pack: os.path.getsize(os.path.join(out, pack)),
                       mpack: os.path.getsize(os.path.join(out, mpack)),
                       engine + ".wasm": os.path.getsize(os.path.join(out, engine + ".wasm"))}
html = html[:m.start(1)] + json.dumps(config, separators=(",", ":")) + html[m.end(1):]
open(html_path, "w").write(html)

data = sorted(f for f in os.listdir(out) if re.match(r"data\d+-[0-9a-f]+\.pck$", f))
cached = [engine + f[len("index"):] for f in ENGINE_FILES] + [pack, mpack] + data
# the page's note on the first download: what actually crosses the wire (GitHub Pages gzips)
import zlib


def wire(f):
    z = zlib.compressobj(6, zlib.DEFLATED, 31)
    n = 0
    with open(os.path.join(out, f), "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            n += len(z.compress(chunk))
    return n + len(z.flush())


common = sum(wire(f) for f in cached if f not in (pack, mpack))
desktop = common + wire(pack)
phone = common + wire(mpack)
mb = lambda n: str(int(round(n / 1048576.0 / 10.0)) * 10)
html = open(html_path).read().replace("KF_SIZE", mb(desktop)).replace("KF_MSIZE", mb(phone))
open(html_path, "w").write(html)
# "add to home screen": full screen and sideways
json.dump({"name": "Knightfall Enlightened", "short_name": "Knightfall", "start_url": "./", "display": "fullscreen",
           "orientation": "landscape", "background_color": "#0b0806", "theme_color": "#0b0806",
           "icons": [{"src": "index.apple-touch-icon.png", "sizes": "180x180", "type": "image/png"}]},
          open(os.path.join(out, "manifest.json"), "w"))
sw = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sw.js")).read()
sw = sw.replace("const FILES = [];", "const FILES = %s;" % json.dumps(cached))
open(os.path.join(out, "sw.js"), "w").write(sw)
print("FINAL engine %s, packs %s (desktop) %s (phones), data %s; first download about %.0f MB (phones %.0f MB)" % (engine, pack, mpack, ", ".join(data), desktop / 1048576.0, phone / 1048576.0))
