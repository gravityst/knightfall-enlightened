#!/bin/bash
# Publishes docs/ (the browser build) as the single commit of an orphan `gh-pages` branch and
# force-pushes it, so every deploy replaces the last one instead of piling ~100 MB of game files
# into the repository's history. GitHub Pages must serve from gh-pages (root):
#   gh api -X PUT repos/<owner>/<repo>/pages -f "source[branch]=gh-pages" -f "source[path]=/"
#     tools/web/deploy.sh
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
REMOTE="$(git -C "$SRC" remote get-url origin)"
TMP="${TMPDIR:-/tmp}/knightfall_pages"
rm -rf "$TMP" && mkdir -p "$TMP"
rsync -a --exclude '.gdignore' "$SRC/docs/" "$TMP/"
touch "$TMP/.nojekyll"
cd "$TMP"
git init -q -b gh-pages
git add -A
git -c user.name="$(git -C "$SRC" config user.name)" -c user.email="$(git -C "$SRC" config user.email)" \
	commit -q -m "Browser build $(date -u +%Y-%m-%dT%H:%MZ) from $(git -C "$SRC" rev-parse --short HEAD)"
git push -q -f "$REMOTE" gh-pages
echo "pushed gh-pages ($(du -sh . | cut -f1))"
