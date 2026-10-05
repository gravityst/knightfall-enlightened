extends SceneTree
## Packs the island's data (world/) and the recorded sounds (sounds/) into data packs of under
## 90 MB each for the browser build (GitHub refuses files over 100 MB), and writes
## scripts/core/web_build.gd listing them for the page to fetch.
##   godot --headless --path <work copy> -s res://tools/web/pack_data.gd -- <out dir>
const LIMIT := 90 * 1048576


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var files := []
	for dir in ["world", "sounds", "sounds/gen"]:
		for f in DirAccess.get_files_at("res://" + dir):
			if not f.begins_with("."):
				files.append("res://%s/%s" % [dir, f])
	files.sort_custom(func(a, b): return _len(a) > _len(b))
	var packs := []
	for f in files:
		var placed := false
		for p in packs:
			if int(p[1]) + _len(f) < LIMIT:
				p[0].append(f)
				p[1] = int(p[1]) + _len(f)
				placed = true
				break
		if not placed:
			packs.append([[f], _len(f)])
	var spec := []
	var sums := ""
	for i in packs.size():
		var tmp := out.path_join("data%d.pck" % (i + 1))
		var pk := PCKPacker.new()
		pk.pck_start(tmp)
		for f in packs[i][0]:
			pk.add_file(f, ProjectSettings.globalize_path(f))
		pk.flush()
		var size := FileAccess.open(tmp, FileAccess.READ).get_length()
		# named by content: a kept copy (see tools/web/sw.js) can never be out of date
		var md5 := FileAccess.get_md5(tmp)
		var name := "data%d-%s.pck" % [i + 1, md5.substr(0, 10)]
		DirAccess.rename_absolute(tmp, out.path_join(name))
		spec.append({"file": name, "size": size})
		sums += md5
		print("PACK %s %.1f MB (%d files)" % [name, size / 1048576.0, packs[i][0].size()])
	var src := FileAccess.get_file_as_string("res://scripts/core/web_build.gd")
	var build := sums.md5_text().substr(0, 12)
	var lines := []
	for l in src.split("\n"):
		if l.begins_with("const BUILD"):
			l = 'const BUILD := "%s"' % build
		elif l.begins_with("const PACKS"):
			l = "const PACKS := %s" % JSON.stringify(spec)
		lines.append(l)
	var f := FileAccess.open("res://scripts/core/web_build.gd", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	print("BUILD ", build)
	quit()


func _len(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0
