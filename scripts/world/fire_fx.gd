class_name FireFX
## Shared fire / smoke particle builders.

static var _flame_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
## Fires and smoke further than this from the player stop emitting and aren't processed or drawn:
## a town has hundreds, and on the browser's renderer each one costs a pass every frame.
static var lod_range: float = 45.0 if Assets.compat else 150.0


static func flames(radius: float, height: float) -> Node3D:
	var root := Node3D.new()
	var p := GPUParticles3D.new()
	p.amount = int(60 * radius + 30)
	p.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.6
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = height * 0.9
	pm.initial_velocity_max = height * 1.6
	pm.gravity = Vector3(0, 1.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.78, 0.38, 0.8))
	g.add_point(0.35, Color(1.0, 0.4, 0.07, 0.65))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.04, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(radius * 0.7, radius * 1.3)       # tongues of flame: taller than wide
	if _flame_mat == null:
		_flame_mat = StandardMaterial3D.new()
		_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_flame_mat.vertex_color_use_as_albedo = true
		_flame_mat.albedo_color = Color(0.95, 0.7, 0.45)   # additive: keep it from blooming to white
		# soft round tongues of flame (a bare quad stacks up into glowing squares)
		var ft := GradientTexture2D.new()
		var fg := Gradient.new()
		fg.set_color(0, Color(1, 1, 1, 1))
		fg.add_point(0.45, Color(1, 1, 1, 0.55))
		fg.set_color(fg.get_point_count() - 1, Color(1, 1, 1, 0))
		ft.gradient = fg
		ft.fill = GradientTexture2D.FILL_RADIAL
		ft.fill_from = Vector2(0.5, 0.5)
		ft.fill_to = Vector2(0.5, 0.0)
		_flame_mat.albedo_texture = ft
		_flame_mat.disable_receive_shadows = true
	q.material = _flame_mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	root.add_child(_for_renderer(p))
	root.add_child(_for_renderer(smoke(radius * 0.8, 2.4)))
	root.add_child(Lod.new())
	return root


## On the Compatibility renderer GPU particles run a transform-feedback pass each; CPU
## particles (simulated in C++, drawn as one multimesh) are far cheaper there.
static func _for_renderer(p: GPUParticles3D) -> GeometryInstance3D:
	if not Assets.compat or Game.debug_flag("gpufx"):
		return p
	var c := CPUParticles3D.new()
	c.convert_from_particles(p)
	c.mesh = p.draw_pass_1
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.local_coords = p.local_coords
	p.free()
	return c


## Switches its parent's fire and smoke off while the player is far away.
class Lod extends Node:
	var _t := 0.0
	var _on := true

	func _ready() -> void:
		_t = randf() * 0.4          # spread the checks over frames
		_apply(false)

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0:
			return
		_t = 0.5
		var me := get_parent() as Node3D
		var pl: Node3D = Game.player_ref
		if me == null or not me.is_inside_tree():
			return
		var near := pl == null or me.global_position.distance_squared_to(pl.global_position) < FireFX.lod_range * FireFX.lod_range
		if near != _on:
			_apply(near)

	func _apply(on: bool) -> void:
		_on = on
		if on:
			Game.mark("fires lit")
		for c in get_parent().get_children():
			if c is GPUParticles3D or c is CPUParticles3D:
				c.set("emitting", on)
				(c as GeometryInstance3D).visible = on


static func smoke(radius: float, rise: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 4.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.5
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = rise * 0.5
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0.6, 0.3, 0.2)
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.3, 0.28, 0.26, 0.0))
	g.add_point(0.15, Color(0.35, 0.33, 0.31, 0.35))
	g.set_color(g.get_point_count() - 1, Color(0.5, 0.5, 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.albedo_color = Color(0.8, 0.8, 0.8)
		_smoke_mat.disable_receive_shadows = true
		var gtex := GradientTexture2D.new()
		var gg := Gradient.new()
		gg.set_color(0, Color(1, 1, 1, 1))
		gg.set_color(1, Color(1, 1, 1, 0))
		gtex.gradient = gg
		gtex.fill = GradientTexture2D.FILL_RADIAL
		gtex.fill_from = Vector2(0.5, 0.5)
		gtex.fill_to = Vector2(0.5, 0.0)
		_smoke_mat.albedo_texture = gtex
	q.material = _smoke_mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 20, 12))
	return p


static var _dot: GradientTexture2D
static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0.8))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
	return _dot


## One-shot hit effects: "blood" (dark droplets that fall) or "sparks" (bright metal sparks).
static var _hit_mats := {}
static func burst(parent: Node, pos: Vector3, kind: String, dir := Vector3.UP) -> void:
	var p := GPUParticles3D.new()
	var sparks := kind == "sparks"
	p.amount = 16 if sparks else 22
	p.lifetime = 0.35 if sparks else 0.75
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 55.0 if sparks else 40.0
	pm.initial_velocity_min = 3.0 if sparks else 1.2
	pm.initial_velocity_max = 6.5 if sparks else 3.2
	pm.gravity = Vector3(0, -9.8 if not sparks else -6.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var g := Gradient.new()
	if sparks:
		g.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
		g.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	else:
		g.set_color(0, Color(0.32, 0.02, 0.015, 0.95))
		g.add_point(0.6, Color(0.24, 0.01, 0.01, 0.85))
		g.set_color(g.get_point_count() - 1, Color(0.18, 0.0, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03) if sparks else Vector2(0.035, 0.035)
	if not _hit_mats.has(kind):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _soft_dot()
		if sparks:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(2.0, 1.6, 1.0)
		else:
			m.roughness = 0.35
		_hit_mats[kind] = m
	q.material = _hit_mats[kind]
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.6).timeout.connect(p.queue_free)
