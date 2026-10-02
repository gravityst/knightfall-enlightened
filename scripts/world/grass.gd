extends Node3D
## GPU ground cover rings (grass near & far, wild flowers, forest undergrowth, tall grass).
## Each ring is one multimesh drawn through the RenderingServer with an LOD mesh.

const LAYERS := [
	# mesh, side, spacing, fade_start, fade_end, scale min/max, kind, min_dist, lod ratio
	["res://assets/nature/Grass_Common_Short.gltf", 92, 0.44, 12.0, 21.0, Vector2(0.3, 0.55), 0, 0.0, 1.0],
	["res://assets/nature/Grass_Common_Short.gltf", 104, 0.92, 32.0, 50.0, Vector2(0.42, 0.72), 0, 15.0, 0.22],
	["res://assets/nature/Flower_3_Single.gltf", 46, 1.8, 26.0, 42.0, Vector2(0.3, 0.5), 1, 0.0, 0.4],
	["res://assets/nature/Flower_4_Single.gltf", 46, 1.9, 26.0, 42.0, Vector2(0.3, 0.5), 1, 0.0, 0.4],
	["res://assets/nature/Clover_2.gltf", 52, 1.5, 28.0, 42.0, Vector2(0.5, 0.9), 2, 0.0, 0.25],
	["res://assets/nature/Grass_Wispy_Tall.gltf", 46, 1.6, 30.0, 44.0, Vector2(0.45, 0.8), 3, 0.0, 0.35],
]

var _mats: Array[ShaderMaterial] = []
var _meshes: Array = []
var _rids: Array[RID] = []


func setup() -> void:
	var shader: Shader = load("res://shaders/grass.gdshader")
	var dens := clampf(float(Game.settings.grass_density), 0.2, 2.0)
	var scenario := get_world_3d().scenario
	for L in LAYERS:
		var mesh: Mesh = Assets.merged_mesh(L[0])
		if mesh == null:
			continue
		var side := int(L[1] * sqrt(dens))
		var count := side * side
		var m2: Mesh = mesh.duplicate()
		var bb := mesh.get_aabb()
		for s in m2.get_surface_count():
			var src = m2.surface_get_material(s)
			var sm := ShaderMaterial.new()
			sm.shader = shader
			if src is BaseMaterial3D:
				sm.set_shader_parameter("albedo_tex", src.albedo_texture if src.albedo_texture else _white())
				sm.set_shader_parameter("albedo_color", src.albedo_color)
				sm.set_shader_parameter("use_alpha", src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			sm.set_shader_parameter("heightmap", WorldData.height_tex)
			sm.set_shader_parameter("biomemap", WorldData.biome_tex)
			sm.set_shader_parameter("splat0", WorldData.splat0_tex)
			sm.set_shader_parameter("splat1", WorldData.splat1_tex)
			sm.set_shader_parameter("watermap", WorldData.water_tex)
			sm.set_shader_parameter("spacing", float(L[2]) / sqrt(dens))
			sm.set_shader_parameter("side", float(side))
			sm.set_shader_parameter("fade_start", float(L[3]))
			sm.set_shader_parameter("fade_end", float(L[4]))
			sm.set_shader_parameter("scale_range", L[5])
			sm.set_shader_parameter("kind", int(L[6]))
			sm.set_shader_parameter("min_dist", float(L[7]))
			sm.set_shader_parameter("mesh_height", maxf(bb.size.y + bb.position.y, 0.2))
			m2.surface_set_material(s, sm)
			_mats.append(sm)
		_meshes.append(m2)
		var mesh_rid := Assets.lod_rid(m2, float(L[8]))
		var buf := PackedFloat32Array()
		buf.resize(count * 12)
		for i in count:
			buf[i * 12] = 1.0
			buf[i * 12 + 5] = 1.0
			buf[i * 12 + 10] = 1.0
		var mm := RenderingServer.multimesh_create()
		RenderingServer.multimesh_allocate_data(mm, count, RenderingServer.MULTIMESH_TRANSFORM_3D)
		RenderingServer.multimesh_set_mesh(mm, mesh_rid)
		RenderingServer.multimesh_set_buffer(mm, buf)
		var inst := RenderingServer.instance_create2(mm, scenario)
		RenderingServer.instance_set_custom_aabb(inst, AABB(Vector3(-5000, -200, -5000), Vector3(10000, 1400, 10000)))
		RenderingServer.instance_geometry_set_cast_shadows_setting(inst, RenderingServer.SHADOW_CASTING_SETTING_OFF)
		_rids.append(inst)
		_rids.append(mm)


func _exit_tree() -> void:
	for r in _rids:
		RenderingServer.free_rid(r)


func set_mask(tex: Texture2D) -> void:
	for sm in _mats:
		sm.set_shader_parameter("block_mask", tex)
		sm.set_shader_parameter("use_mask", true)


static var _w: ImageTexture
static func _white() -> Texture2D:
	if _w == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_w = ImageTexture.create_from_image(img)
	return _w
