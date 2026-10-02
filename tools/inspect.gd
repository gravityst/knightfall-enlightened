extends SceneTree
# Usage: godot --headless --path . -s tools/inspect.gd -- <dir> [anim]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var show_anim := args.size() > 1
	var files := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gltf") or f.ends_with(".glb") or f.ends_with(".fbx"):
			files.append(f)
	files.sort()
	for f in files:
		var ps: PackedScene = load(dir + "/" + f)
		if ps == null:
			print(f, " LOAD FAIL"); continue
		var inst: Node = ps.instantiate()
		root.add_child(inst)
		var aabb := AABB(); var first := true; var tris := 0; var mats := {}; var nmesh := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			if m == null: continue
			nmesh += 1
			var a: AABB = mi.global_transform * m.get_aabb()
			aabb = a if first else aabb.merge(a); first = false
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
				var mat = mi.get_active_material(s)
				if mat: mats[mat.resource_name] = true
		var line := "%s pos=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f) tris=%d meshes=%d mats=%s" % [f.get_basename(), aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z, tris, nmesh, ",".join(mats.keys())]
		if show_anim:
			for ap in inst.find_children("*", "AnimationPlayer", true, false):
				line += " ANIMS=" + ",".join(ap.get_animation_list())
			for sk in inst.find_children("*", "Skeleton3D", true, false):
				line += " BONES=%d" % sk.get_bone_count()
		print(line)
		inst.free()
	quit()
