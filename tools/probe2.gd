extends SceneTree
func _init() -> void:
	await process_frame
	for f in ["Superhero_Male_FullBody", "Male_Peasant", "Male_Ranger", "Female_Peasant"]:
		var inst: Node3D = load("res://assets/characters/%s.gltf" % f).instantiate()
		root.add_child(inst)
		print("== ", f)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			var mats := []
			for s in m.get_surface_count():
				var mt = mi.get_active_material(s)
				mats.append(mt.resource_name if mt else "-")
			var a: AABB = m.get_aabb()
			print("  ", mi.name, " y=", snapped(a.position.y, 0.01), "..", snapped(a.end.y, 0.01), " mats=", mats)
		inst.queue_free()
	quit()
