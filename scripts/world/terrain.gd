class_name Terrain
extends Node3D
## GPU terrain renderer (CDLOD quadtree of instanced grid chunks with vertex morphing)
## plus a streaming physics heightfield that follows the player.
## The same chunk selection drives the water surface.

const ROOT_ORIGIN := -4096.0
const LEAF := 32.0
const LEVELS := 9
const GRID := 32
const MAX_INST := 3000

var lod0_range := 90.0
var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var _mm_full: MultiMesh
var _mm_half: MultiMesh
var _minmax: Array[PackedFloat32Array] = []
var _buf_full := PackedFloat32Array()
var _buf_half := PackedFloat32Array()
var _n_full := 0
var _n_half := 0
var _last_cam := Vector3(INF, INF, INF)

# collision
const COL_N := 200            # samples per side (1.5 m) -> 300 m patch
var _col_body: StaticBody3D
var _col_shape: CollisionShape3D
var _col_center := Vector2(INF, INF)


func setup() -> void:
	_build_minmax()
	var full := _grid_mesh(GRID)
	var half := _grid_mesh(GRID / 2)
	_mm_full = _make_mm(full)
	_mm_half = _make_mm(half)
	_buf_full.resize(MAX_INST * 16)
	_buf_half.resize(MAX_INST * 16)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	var W := WorldData
	terrain_mat.set_shader_parameter("heightmap", W.height_tex)
	terrain_mat.set_shader_parameter("normalmap", W.normal_tex)
	terrain_mat.set_shader_parameter("splat0", W.splat0_tex)
	terrain_mat.set_shader_parameter("splat1", W.splat1_tex)
	terrain_mat.set_shader_parameter("biomemap", W.biome_tex)
	terrain_mat.set_shader_parameter("watermap", W.water_tex)
	terrain_mat.set_shader_parameter("albedo_array", W.albedo_array)
	terrain_mat.set_shader_parameter("normal_array", W.normal_array)
	terrain_mat.set_shader_parameter("macro_noise", _noise_tex(512, 0.01, 4))
	terrain_mat.set_shader_parameter("lod0_range", lod0_range)
	for mm in [_mm_full, _mm_half]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = terrain_mat
		mi.custom_aabb = AABB(Vector3(-5000, -200, -5000), Vector3(10000, 1400, 10000))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
	_col_body = StaticBody3D.new()
	_col_body.collision_layer = 1
	_col_body.collision_mask = 0
	_col_shape = CollisionShape3D.new()
	_col_shape.shape = HeightMapShape3D.new()
	_col_body.add_child(_col_shape)
	add_child(_col_body)


func setup_water(mat: ShaderMaterial) -> void:
	water_mat = mat
	water_mat.set_shader_parameter("lod0_range", lod0_range)
	for mm in [_mm_full, _mm_half]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 800, 10000))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _make_mm(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = MAX_INST
	mm.visible_instance_count = 0
	return mm


func _grid_mesh(res: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for z in res + 1:
		for x in res + 1:
			verts.append(Vector3(float(x) / res, 0.0, float(z) / res))
	for z in res:
		for x in res:
			var i := z * (res + 1) + x
			idx.append_array([i, i + 1, i + res + 1, i + 1, i + res + 2, i + res + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(0, -200, 0), Vector3(1, 1400, 1))
	return m


func _noise_tex(size: int, freq: float, octaves: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	return t


func _build_minmax() -> void:
	_minmax.clear()
	_minmax.append(WorldData.minmax)
	var n := 256
	for l in range(1, LEVELS):
		var prev: PackedFloat32Array = _minmax[l - 1]
		var pn := n
		n >>= 1
		var cur := PackedFloat32Array()
		cur.resize(n * n * 2)
		for j in n:
			for i in n:
				var a := ((j * 2) * pn + i * 2) * 2
				var b := a + 2
				var c := a + pn * 2
				var d := c + 2
				cur[(j * n + i) * 2] = minf(minf(prev[a], prev[b]), minf(prev[c], prev[d]))
				cur[(j * n + i) * 2 + 1] = maxf(maxf(prev[a + 1], prev[b + 1]), maxf(prev[c + 1], prev[d + 1]))
		_minmax.append(cur)


# ------------------------------------------------------------------ selection
func update_view(cam: Vector3, force := false) -> void:
	if not force and cam.distance_squared_to(_last_cam) < 1.0:
		return
	_last_cam = cam
	_n_full = 0
	_n_half = 0
	_select(LEVELS - 1, 0, 0, cam)
	_mm_full.buffer = _buf_full
	_mm_full.visible_instance_count = _n_full
	_mm_half.buffer = _buf_half
	_mm_half.visible_instance_count = _n_half
	terrain_mat.set_shader_parameter("sel_cam", cam)
	if water_mat:
		water_mat.set_shader_parameter("sel_cam", cam)


func _select(level: int, ix: int, iz: int, cam: Vector3) -> bool:
	var size := LEAF * float(1 << level)
	var x0 := ROOT_ORIGIN + ix * size
	var z0 := ROOT_ORIGIN + iz * size
	var n := 256 >> level
	var mmv: PackedFloat32Array = _minmax[level]
	var k := (iz * n + ix) * 2
	var ymin := mmv[k]
	var ymax := mmv[k + 1]
	var rng := lod0_range * float(1 << level)
	if not _hit(cam, rng, x0, z0, size, ymin, ymax):
		return false
	if level == 0:
		_add(x0, z0, size, 0, true)
		return true
	if not _hit(cam, rng * 0.5, x0, z0, size, ymin, ymax):
		_add(x0, z0, size, level, true)
		return true
	var cs := size * 0.5
	for c in 4:
		var cx := ix * 2 + (c & 1)
		var cz := iz * 2 + (c >> 1)
		if not _select(level - 1, cx, cz, cam):
			_add(ROOT_ORIGIN + cx * cs, ROOT_ORIGIN + cz * cs, cs, level, false)
	return true


func _hit(c: Vector3, r: float, x0: float, z0: float, size: float, ymin: float, ymax: float) -> bool:
	var dx := maxf(maxf(x0 - c.x, 0.0), c.x - (x0 + size))
	var dz := maxf(maxf(z0 - c.z, 0.0), c.z - (z0 + size))
	var dy := maxf(maxf(ymin - c.y, 0.0), c.y - ymax)
	return dx * dx + dy * dy + dz * dz <= r * r


func _add(x0: float, z0: float, size: float, lod: int, full: bool) -> void:
	# Packed arrays are value types in GDScript: write straight into the member arrays.
	if full:
		if _n_full >= MAX_INST: return
		var i := _n_full * 16
		_n_full += 1
		_buf_full[i] = 1.0; _buf_full[i + 3] = x0; _buf_full[i + 5] = 1.0; _buf_full[i + 10] = 1.0; _buf_full[i + 11] = z0
		_buf_full[i + 12] = float(lod); _buf_full[i + 13] = size; _buf_full[i + 14] = float(GRID)
	else:
		if _n_half >= MAX_INST: return
		var i := _n_half * 16
		_n_half += 1
		_buf_half[i] = 1.0; _buf_half[i + 3] = x0; _buf_half[i + 5] = 1.0; _buf_half[i + 10] = 1.0; _buf_half[i + 11] = z0
		_buf_half[i + 12] = float(lod); _buf_half[i + 13] = size; _buf_half[i + 14] = float(GRID / 2)


# ------------------------------------------------------------------ collision
func update_collision(p: Vector3) -> void:
	var c := Vector2(p.x, p.z)
	if c.distance_to(_col_center) < 40.0:
		return
	_col_center = c
	var H := WorldData.heights
	var res := WorldData.HM_RES
	var t := WorldData.HM_TEXEL
	var ci := int(round((p.x + WorldData.HALF) / t))
	var cj := int(round((p.z + WorldData.HALF) / t))
	var i0 := ci - COL_N / 2
	var j0 := cj - COL_N / 2
	var data := PackedFloat32Array()
	data.resize(COL_N * COL_N)
	for j in COL_N:
		var jj := clampi(j0 + j, 0, res - 1) * res
		var row := j * COL_N
		for i in COL_N:
			data[row + i] = H[jj + clampi(i0 + i, 0, res - 1)] / t
	var shape := HeightMapShape3D.new()
	shape.map_width = COL_N
	shape.map_depth = COL_N
	shape.map_data = data
	_col_shape.shape = shape
	# HeightMapShape3D is centred on its origin with 1-unit spacing; uniform scale by texel size.
	var cx := -WorldData.HALF + (i0 + (COL_N - 1) * 0.5) * t
	var cz := -WorldData.HALF + (j0 + (COL_N - 1) * 0.5) * t
	_col_body.transform = Transform3D(Basis.from_scale(Vector3(t, t, t)), Vector3(cx, 0.0, cz))
