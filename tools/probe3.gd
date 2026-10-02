extends SceneTree
func _init() -> void:
	await process_frame
	for f in ["elk", "bear_black", "moose_antlers", "duck_mallard", "goose", "crow", "hen", "hawk", "gull_flying"]:
		var inst: Node3D = load("res://assets/animals/%s.glb" % f).instantiate()
		var holder := Node3D.new()
		holder.add_child(inst)
		var line: String = String(f) + ": "
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != holder:
				if cur is Node3D: xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			var a: AABB = xf * mi.mesh.get_aabb()
			var mats := []
			for s in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(s)
				mats.append("%s(tex=%s,vc=%s)" % [m.resource_name if m else "-", m.albedo_texture != null if m is BaseMaterial3D else "?", m.vertex_color_use_as_albedo if m is BaseMaterial3D else "?"])
			line += "[%s surf=%d aabb=%s..%s mats=%s] " % [mi.name, mi.mesh.get_surface_count(), a.position.snapped(Vector3.ONE * 0.01), a.end.snapped(Vector3.ONE * 0.01), mats]
		print(line)
		holder.free()
	quit()
