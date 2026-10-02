extends SceneTree
## Character line-up renderer for visual checks:
##   godot --path . -s res://tools/lineup.gd -- <scenes.json>
## scenes.json: [{"out": "file.jpg", "cam": [x, y, z], "look": [x, y, z], "fov": 35,
##   "chars": [{"x": 0, "yaw": 0, "anim": "Idle", "t": 0.3, ...CharacterModel.build params}]}]
## Colour params may be given as [r, g, b] arrays.
func _init() -> void:
	await process_frame
	var spec: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	for sc in spec:
		await _render(sc)
	quit()


func _render(sc: Dictionary) -> void:
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.47, 0.52)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.7)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var cam := Camera3D.new()
	var cp: Array = sc.get("cam", [0, 1.2, 4])
	var lk: Array = sc.get("look", [0, 1.0, 0])
	cam.fov = float(sc.get("fov", 35))
	w.add_child(cam)
	cam.look_at_from_position(Vector3(cp[0], cp[1], cp[2]), Vector3(lk[0], lk[1], lk[2]))
	cam.current = true
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	w.add_child(floor_mi)
	var models := []
	for c in sc.chars:
		var p: Dictionary = c.duplicate()
		for k in ["hair_color", "skin"]:
			if p.get(k) is Array:
				p[k] = Color(p[k][0], p[k][1], p[k][2])
		var cm := CharacterModel.new()
		w.add_child(cm)
		if c.has("tilt"):
			CharacterModel.grip_tilt = float(c.tilt)
		if c.has("torch_tilt"):
			CharacterModel.torch_tilt = float(c.torch_tilt)
		cm.build(p)
		cm.position = Vector3(float(c.get("x", 0)), 0, float(c.get("z", 0)))
		cm.rotation.y = deg_to_rad(float(c.get("yaw", 0)))
		var an: String = c.get("anim", "Idle")
		cm.armed = bool(c.get("armed", false))
		if cm.anim.has_animation(an):
			cm.play(an, 0.0)
			cm.anim.seek(float(c.get("t", 0.3)) * cm.anim.current_animation_length, true)
			cm.anim.pause()
		models.append(cm)
	for i in 30:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_jpg(sc.out, 0.88)
	print("LINEUP saved ", sc.out)
	w.queue_free()
	await process_frame
