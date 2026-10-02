extends SceneTree
## Renders the inventory icon atlas (assets/ui/item_icons.png) from ItemModels: every item lit
## like a studio product shot on a transparent background, in ItemModels.SPECS order.
##   godot --path . -s res://tools/bake_icons.gd [-- --only=id,id --out=path]
const IM := preload("res://scripts/core/item_models.gd")
const SS := 2         # supersampling


func _init() -> void:
	await process_frame
	var only := []
	var out := "res://assets/ui/item_icons.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		if a.begins_with("--out="):
			out = a.substr(6)
	var px: int = IM.ICON_PX
	var ids: Array = IM.SPECS.keys()
	var rows := int(ceil(ids.size() / float(IM.ICON_COLS)))
	var atlas := Image.create(px * IM.ICON_COLS, px * rows, false, Image.FORMAT_RGBA8)
	var vp := SubViewport.new()
	vp.size = Vector2i(px * SS, px * SS)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var stage := Node3D.new()
	vp.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	# a studio sky to reflect in metal (the background itself stays transparent)
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.85, 0.82, 0.78)
	psm.sky_horizon_color = Color(0.6, 0.55, 0.5)
	psm.ground_bottom_color = Color(0.36, 0.33, 0.3)
	psm.ground_horizon_color = Color(0.62, 0.58, 0.54)
	sky.sky_material = psm
	e.sky = sky
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.52, 0.5)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.15
	env.environment = e
	stage.add_child(env)
	for l in [[Vector3(-45, -40, 0), Color(1.0, 0.94, 0.84), 2.4], [Vector3(-20, 120, 0), Color(0.75, 0.82, 1.0), 0.8], [Vector3(-10, 200, 0), Color(1.0, 0.9, 0.75), 1.6]]:
		var d := DirectionalLight3D.new()
		d.rotation_degrees = l[0]
		d.light_color = l[1]
		d.light_energy = l[2]
		stage.add_child(d)
	var cam := Camera3D.new()
	cam.fov = 26.0
	stage.add_child(cam)
	cam.current = true
	for i in ids.size():
		var id: String = ids[i]
		if not only.is_empty() and not only.has(id):
			continue
		var sp: Dictionary = IM.SPECS[id]
		var holder := Node3D.new()
		stage.add_child(holder)
		var item: Node3D = IM.build(id, 1.0)
		holder.add_child(item)
		var r: Array = sp.get("rot", [0, 0, 0])
		holder.rotation_degrees = Vector3(r[0], r[1], r[2])
		for gi in holder.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		await process_frame
		# frame the bounding sphere of the posed item
		var bb := AABB()
		var first := true
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			bb = a if first else bb.merge(a)
			first = false
		var c := bb.get_center()
		var rad := maxf(bb.size.x, bb.size.y) * 0.5 * 1.12 + bb.size.z * 0.05
		var dist := rad / tan(deg_to_rad(cam.fov * 0.5))
		cam.look_at_from_position(c + Vector3(0, 0, dist), c)
		cam.near = maxf(dist - bb.size.length(), 0.01)
		cam.far = dist + bb.size.length() * 2.0
		for f in 10:          # big textures can stall a frame: give the render a moment to catch up
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(img, Rect2i(0, 0, px, px), Vector2i((i % IM.ICON_COLS) * px, (i / IM.ICON_COLS) * px))
		holder.queue_free()
		print("ICON ", id)
	if not only.is_empty() and FileAccess.file_exists(out):
		# re-baking a few: keep the rest of the existing atlas
		var old := Image.load_from_file(ProjectSettings.globalize_path(out))
		for i in ids.size():
			if not only.has(ids[i]):
				var rr := Rect2i((i % IM.ICON_COLS) * px, (i / IM.ICON_COLS) * px, px, px)
				atlas.blit_rect(old, rr, rr.position)
	atlas.save_png(ProjectSettings.globalize_path(out))
	print("ATLAS saved ", out)
	quit()
