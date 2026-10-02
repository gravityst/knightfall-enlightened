extends SceneTree
## Loads every script and shader in the project so parse/compile errors are reported.
func _init() -> void:
	await process_frame
	var files := []
	_scan("res://scripts", files)
	for f in files:
		var s = load(f)
		if s == null or (s is Script and not s.can_instantiate() and not f.ends_with("items.gd")):
			print("LINT FAIL ", f)
	for f in ["res://shaders/terrain.gdshader", "res://shaders/water.gdshader", "res://shaders/sky.gdshader"]:
		load(f)
	print("LINT_DONE")
	quit()

func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_scan(dir + "/" + d, out)
