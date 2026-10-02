extends SceneTree
func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var inst: Node = (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		print("== ", path)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			var mats := []
			for s in mi.mesh.get_surface_count():
				var m = mi.get_active_material(s)
				mats.append(m.resource_name if m else "-")
			print("  %s pos=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f) origin=(%.2f,%.2f,%.2f) mats=%s" % [mi.name, a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z, mi.global_position.x, mi.global_position.y, mi.global_position.z, ",".join(mats)])
		inst.free()
	quit()
