extends Node3D
## Line-up of all animal species for scale / orientation / animation checks.
func _ready() -> void:
	await get_tree().process_frame
	var w := Node3D.new()
	add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.4, 0.45, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 20, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 6, 17)
	cam.rotation_degrees = Vector3(-14, 0, 0)
	cam.fov = 50
	w.add_child(cam)
	cam.current = true
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	w.add_child(floor_mi)
	var wl := load("res://scripts/actors/wildlife.gd")
	var names := ["deer", "stag", "fox", "wolf", "bear", "moose", "alpaca", "cow", "sheep", "pig", "dog", "donkey", "duck", "goose", "crow", "hen", "fish"]
	var i := 0
	for n in names:
		var spec: Dictionary = wl.SPECIES[n].duplicate()
		if spec.kind in ["water", "bird", "fish"]:
			spec.kind = "farm"
		var a := Animal.new()
		w.add_child(a)
		a.position = Vector3(-12.0 + (i % 9) * 3.0, 0, -2.0 - (i / 9) * 6.0)
		a.setup(spec, n, {"center": a.position, "members": []}, null)
		a.set_physics_process(false)
		a.rotation.y = PI * 0.5
		a._play("Walk")
		i += 1
	for k in 45:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.resize(1280, 720)
	img.save_jpg(OS.get_cmdline_user_args()[0], 0.85)
	get_tree().quit()
