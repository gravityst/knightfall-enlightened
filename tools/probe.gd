extends SceneTree
func _init() -> void:
	await process_frame
	var F := "res://assets/castle/modular_fort_01/modular_fort_01.gltf"
	for n in ["wall_thick_straight_01", "tower_round", "wall_thin_gate_01", "wall_walkway_straight_01", "wall_stairs_straight_01"]:
		var p: Array = Assets.part_named(F, n)
		if p.is_empty():
			print(n, " NOT FOUND"); continue
		var m: Mesh = p[0]
		var xf: Transform3D = p[1]
		print(n, " xf.origin=", xf.origin, " scale=", xf.basis.get_scale(), " rot=", xf.basis.get_euler(), " mesh_aabb=", m.get_aabb(), " world_aabb=", xf * m.get_aabb())
	var inst: Node = load(F).instantiate()
	print("root ", inst.name, " ", (inst as Node3D).transform)
	for c in inst.get_children():
		print("  child ", c.name, " ", c.get_class(), " ", (c as Node3D).transform.origin if c is Node3D else "")
		for c2 in c.get_children():
			print("     ", c2.name, " ", c2.get_class(), " ", (c2 as Node3D).transform if c2 is Node3D else "")
			break
	quit()
