#!/bin/bash
# Builds the browser version into docs/ (published by GitHub Pages).
# Works on a copy of the project, so the desktop project is never changed:
#   textures capped at 1024 px, island maps as WebP, world data in separate packs (each under
#   GitHub's 100 MB limit), exported single-threaded for WebGL 2.
#     tools/web/build_web.sh            (GODOT=/path/to/Godot to override)
set -euo pipefail
GODOT="${GODOT:-/Users/curtis/Downloads/Godot.app/Contents/MacOS/Godot}"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${TMPDIR:-/tmp}/knightfall_web_build"
OUT="$WORK/web_out"

echo "== copying the project to $WORK"
mkdir -p "$WORK"
# the import cache is copied once; afterwards the copy keeps its own (web-sized) imports
[ -d "$WORK/.godot" ] || { mkdir -p "$WORK" && cp -R "$SRC/.godot" "$WORK/.godot" 2>/dev/null || true; }
rsync -a --delete --exclude '.git' --exclude 'docs' --exclude '.godot' "$SRC/" "$WORK/"
rm -rf "$OUT" && mkdir -p "$OUT"

echo "== preparing textures and maps"
python3 "$SRC/tools/web/prepare.py" "$WORK"

echo "== importing"
"$GODOT" --headless --path "$WORK" --import >/dev/null 2>&1 || true

echo "== rendering the synthesised sounds"
"$GODOT" --headless --path "$WORK" -- --render-sounds="$WORK/sounds/gen" 2>&1 | grep -E "RENDERED|ERROR" || true

echo "== packing the island's data"
"$GODOT" --headless --path "$WORK" -s res://tools/web/pack_data.gd -- "$OUT" 2>&1 | grep -E "PACK|BUILD|ERROR" || true

echo "== exporting for the web"
"$GODOT" --headless --path "$WORK" --export-release "Web" "$OUT/index.html" 2>&1 | grep -iE "error|warning: export" || true
[ -f "$OUT/index.pck" ] || { echo "export failed"; exit 1; }

echo "== publishing to docs/"
mkdir -p "$SRC/docs"
find "$SRC/docs" -mindepth 1 -maxdepth 1 ! -name '.gdignore' ! -name '.nojekyll' -exec rm -rf {} +
cp -R "$OUT/"* "$SRC/docs/"
touch "$SRC/docs/.gdignore" "$SRC/docs/.nojekyll"
ls -la "$SRC/docs" | awk '{printf "%8.1f MB  %s\n", $5/1048576, $9}'
