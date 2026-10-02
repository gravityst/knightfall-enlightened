extends RefCounted
## Written by tools/web/build_web.sh for the browser build: the data packs that sit next to the
## page (the island's maps and the recorded sounds, split to stay under GitHub's 100 MB a file).
## Empty on the desktop, where res://world/ and res://sounds/ are plain folders.
const BUILD := ""
const PACKS := []
