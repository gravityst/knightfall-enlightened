extends SceneTree
func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var inst: Node = (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		var line := path.get_file() + ": "
		for sk in inst.find_children("*", "Skeleton3D", true, false):
			line += "skel=" + str(inst.get_path_to(sk)) + " scale=" + str(sk.global_transform.basis.get_scale()) + " "
			var hb: int = sk.find_bone("Head")
			if hb < 0: hb = sk.find_bone("head")
			line += "rootbone=" + sk.get_bone_name(0) + " "
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			line += "[mi " + str(inst.get_path_to(mi)) + " skin=" + str(mi.skin != null) + (" bindname0=" + str(mi.skin.get_bind_name(0)) if mi.skin else "") + "] "
		for ap in inst.find_children("*", "AnimationPlayer", true, false):
			var a: Animation = ap.get_animation(ap.get_animation_list()[0])
			line += "AP=" + str(inst.get_path_to(ap)) + " root=" + str(ap.root_node) + " track0=" + str(a.track_get_path(0)) + " len=" + str(a.length)
		print(line)
		inst.free()
	quit()
