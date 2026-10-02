extends Node3D
## Forests, bushes and rocks from world/veg.bin, drawn directly through the RenderingServer:
##  * near trees: per-cell multimeshes of the real models (wind shader), fading out ~230 m
##  * far trees : per-cell impostor billboards captured from the models at load time
##  * bushes / rocks with their own draw distances
##  * trunk & boulder collisions streamed around the player

const TREE_CELL := 128.0
const BUSH_CELL := 64.0
const ROCK_CELL := 256.0
const IMP_COLS := 6
const IMP_ROWS := 3
const IMP_CW := 256
const IMP_CH := 512

var species: Array = []          # dicts: name, path, radius, kind, mesh, base, height, imp_index, imp_k
var inst_data: Array = []        # per species PackedFloat32Array (x, y, z, rot, scale)*
var _rids: Array[RID] = []
var _meshes: Array = []
var _foliage_shader: Shader
var _capture_shader: Shader
var _mat_cache := {}
var _imp_material: ShaderMaterial
var _imp_mesh: QuadMesh
var _col_grid := {}              # Vector2i(32 m) -> Array of [x, z, radius, height]
var _col_bodies: Array[StaticBody3D] = []
var _col_center := Vector2(INF, INF)
var grass: Node3D
var view_scale := 1.0
var _mm_jobs: Array = []         # [mesh, lod ratio, buffer, count, custom, cell key, cell, tier] from the worker
var _build_task := -1
const STREAM_CHUNK := 128.0
const IMP_CHUNK := 768.0
const SHADOW_LOD := 0.3
const MID_LOD := 0.35
var _stream_r := 250.0
var _stream_jobs := {}           # Vector2i chunk -> mesh-tier jobs (see finish)
var _stream_live := {}           # Vector2i chunk -> RIDs of its built instances
var _stream_todo: Array[Vector2i] = []
var _stream_center := Vector2i(1 << 30, 1 << 30)


func setup(progress: Callable) -> void:
	view_scale = clampf(float(Game.settings.view_distance), 0.5, 1.8)
	_foliage_shader = load("res://shaders/foliage.gdshader")
	_capture_shader = Shader.new()
	_capture_shader.code = """shader_type spatial; render_mode unshaded, cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap; uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_alpha = false; uniform int mode = 0;
uniform float hue_shift = 0.0; uniform float sat_mul = 1.0; uniform float val_mul = 1.0;
vec3 hsv_adjust(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	vec3 hsv = vec3(fract(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)) + hue_shift), clamp(d / (q.x + 1e-10) * sat_mul, 0.0, 1.0), clamp(q.x * val_mul, 0.0, 1.0));
	return hsv.z * mix(vec3(1.0), clamp(abs(fract(hsv.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0), hsv.y);
}
void fragment(){ vec4 c = texture(albedo_tex, UV) * albedo_color; if (use_alpha) { ALPHA = c.a; ALPHA_SCISSOR_THRESHOLD = 0.5; }
 if (mode == 0) { ALBEDO = hue_shift != 0.0 ? hsv_adjust(c.rgb) : c.rgb; } else { vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz); if (!FRONT_FACING) { wn = -wn; } ALBEDO = pow(wn * 0.5 + 0.5, vec3(2.2)); } }"""
	_load_bin()
	progress.call(0.1, "Planting the forests")
	await get_tree().process_frame
	_prepare_species()
	progress.call(0.3, "Planting the forests")
	await get_tree().process_frame
	await _capture_impostors()
	_build_task = WorkerThreadPool.add_task(_compute_instances)
	progress.call(0.6, "Sowing the meadows")
	await get_tree().process_frame
	grass = load("res://scripts/world/grass.gd").new()
	add_child(grass)
	grass.call("setup")
	progress.call(1.0, "Forests planted")


func _exit_tree() -> void:
	if _build_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1
	for r in _rids:
		RenderingServer.free_rid(r)
	for k in _stream_live:
		for r in _stream_live[k]:
			RenderingServer.free_rid(r)
	_stream_live.clear()
	_rids.clear()


# ------------------------------------------------------------------ data
func _load_bin() -> void:
	species = []
	for s in WorldData.info.species:
		species.append(s.duplicate())
	var f := FileAccess.open(WorldData.DIR + "veg.bin", FileAccess.READ)
	var n := f.get_32()
	inst_data.resize(n)
	for i in n:
		var sid := f.get_32()
		var count := f.get_32()
		var bytes := f.get_buffer(count * 20)
		inst_data[sid] = bytes.to_float32_array()
	f.close()
	_clear_built_ground()


## The baked scatter knows nothing of buildings: drop every plant, tree and rock that stands
## inside a house, a castle's walls or a landmark, and keep bushes and rocks off town squares.
func _clear_built_ground() -> void:
	const CELL := 32.0
	var grid := {}              # Vector2i -> Array of [inverse transform, half x, half z, keep trees?]
	var add_box := func(x: float, z: float, yaw: float, hx: float, hz: float, trees_too: bool) -> void:
		var inv := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z)).affine_inverse()
		var r := Vector2(hx, hz).length()
		for cz in range(floori((z - r) / CELL), floori((z + r) / CELL) + 1):
			for cx in range(floori((x - r) / CELL), floori((x + r) / CELL) + 1):
				var k := Vector2i(cx, cz)
				if not grid.has(k):
					grid[k] = []
				grid[k].append([inv, hx, hz, trees_too])
	for s in WorldData.settlements:
		for b in s.get("buildings", []):
			add_box.call(float(b.x), float(b.z), float(b.yaw), float(b.w) * 0.5 + 1.0, float(b.d) * 0.5 + 1.0, true)
		match String(s.type):
			"castle", "ruin":
				add_box.call(float(s.x), float(s.z), float(s.get("yaw", 0.0)), 31.0, 31.0, true)
			"town", "village":
				var plaza := 16.0 if s.type == "town" else 11.0
				add_box.call(float(s.x), float(s.z), 0.0, plaza, plaza, false)
	for q in WorldData.pois:
		var pr := minf(float(q.get("radius", 10.0)), 14.0)
		add_box.call(float(q.x), float(q.z), float(q.get("yaw", 0.0)), pr * 0.6, pr * 0.6, true)
	for w in preload("res://scripts/world/wilds.gd").plan():
		add_box.call(float(w.x), float(w.z), float(w.yaw), float(w.r), float(w.r), true)
	for sid in inst_data.size():
		var kind := String(species[sid].kind)
		var data: PackedFloat32Array = inst_data[sid]
		var n := data.size() / 5
		var drop := PackedByteArray()
		var drops := 0
		for i in n:
			var boxes = grid.get(Vector2i(floori(data[i * 5] / CELL), floori(data[i * 5 + 2] / CELL)))
			if boxes == null:
				continue
			var p := Vector3(data[i * 5], 0, data[i * 5 + 2])
			for bx in boxes:
				if kind == "tree" and not bx[3]:
					continue
				var lp: Vector3 = (bx[0] as Transform3D) * p
				if absf(lp.x) < bx[1] and absf(lp.z) < bx[2]:
					if drop.is_empty():
						drop.resize(n)
					drop[i] = 1
					drops += 1
					break
		if drops == 0:
			continue
		var keep := PackedFloat32Array()
		keep.resize((n - drops) * 5)
		var o := 0
		for i in n:
			if drop[i] == 0:
				for c in 5:
					keep[o + c] = data[i * 5 + c]
				o += 5
		inst_data[sid] = keep


func _prepare_species() -> void:
	var imp_i := 0
	for i in species.size():
		var s: Dictionary = species[i]
		var src: Mesh = Assets.merged_mesh(s.path)
		var bb: AABB = src.get_aabb()
		var base := 1.0
		if bb.size.y < 0.5:      # poly.pizza palms come in at centimetre scale
			base = 9.0 / maxf(bb.size.y, 0.0001)
		var mesh: Mesh = src.duplicate()
		for si in mesh.get_surface_count():
			var m = mesh.surface_get_material(si)
			if s.kind == "rock":
				continue
			mesh.surface_set_material(si, _foliage_material(m, s.kind, bb.size.y * base))
		s["mesh"] = mesh
		s["base"] = base
		s["height"] = bb.size.y * base
		s["width"] = maxf(bb.size.x, bb.size.z) * base
		s["aabb"] = bb
		_meshes.append(mesh)
		if s.kind == "tree" and imp_i < IMP_COLS * IMP_ROWS:
			s["imp_index"] = imp_i
			imp_i += 1
		for k in range(0, inst_data[i].size(), 5):
			var sc: float = inst_data[i][k + 4] * base
			if s.kind == "tree" or (s.kind == "rock" and sc > 0.9):
				var key := Vector2i(int(floor(inst_data[i][k] / 32.0)), int(floor(inst_data[i][k + 2] / 32.0)))
				if not _col_grid.has(key):
					_col_grid[key] = []
				var r: float = float(s.radius) * sc if s.kind == "tree" else 1.2 * sc
				_col_grid[key].append([inst_data[i][k], inst_data[i][k + 1], inst_data[i][k + 2], r, s.height * sc / base if s.kind == "tree" else 1.6 * sc])


func _foliage_material(m: Material, kind: String, height: float) -> Material:
	if m == null or not (m is BaseMaterial3D):
		return m
	var key := "%d|%s" % [m.get_instance_id(), kind]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var bm: BaseMaterial3D = m
	var sm := ShaderMaterial.new()
	sm.shader = _foliage_shader
	sm.set_shader_parameter("albedo_tex", bm.albedo_texture if bm.albedo_texture else _white())
	sm.set_shader_parameter("albedo_color", bm.albedo_color)
	var leafy := bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	sm.set_shader_parameter("use_alpha", leafy)
	sm.set_shader_parameter("alpha_scissor", bm.alpha_scissor_threshold if bm.alpha_scissor_threshold > 0.0 else 0.5)
	if bm.normal_enabled and bm.normal_texture:
		sm.set_shader_parameter("use_normal", true)
		sm.set_shader_parameter("normal_tex", bm.normal_texture)
	sm.set_shader_parameter("roughness", clampf(bm.roughness, 0.6, 1.0))
	sm.set_shader_parameter("bend_height", maxf(height, 1.0))
	match kind:
		"tree":
			sm.set_shader_parameter("wind_amount", 1.0 if leafy else 0.45)
			sm.set_shader_parameter("flutter", 1.0 if leafy else 0.0)
			sm.set_shader_parameter("translucency", 0.32 if leafy else 0.0)
		"bush":
			sm.set_shader_parameter("wind_amount", 0.5)
			sm.set_shader_parameter("flutter", 0.6)
			sm.set_shader_parameter("translucency", 0.3)
	if leafy and bm.albedo_texture and String(bm.albedo_texture.resource_path).contains("TwistedTree"):
		# the kit's twisted-tree foliage is a saturated crimson: grow it as deep summer green
		sm.set_shader_parameter("hue_shift", 0.255 if kind == "bush" else 0.235)
		sm.set_shader_parameter("sat_mul", 0.9 if kind == "bush" else 0.8)
		sm.set_shader_parameter("val_mul", 0.72 if kind == "bush" else 0.78)
	_mat_cache[key] = sm
	return sm


static var _white_tex: ImageTexture
static func _white() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


# ------------------------------------------------------------------ impostors
func _capture_impostors() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(IMP_CW * IMP_COLS, IMP_CH * IMP_ROWS)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(IMP_ROWS)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(IMP_COLS * 0.25, IMP_ROWS * 0.5, 50.0)
	cam.near = 1.0
	cam.far = 120.0
	vp.add_child(cam)
	cam.current = true
	var holders := []
	var cap_mats := []   # [mesh_instance, surface, albedo_mat, normal_mat]
	for s in species:
		if not s.has("imp_index"):
			continue
		var idx: int = s.imp_index
		var col := idx % IMP_COLS
		var row := idx / IMP_COLS
		var mi := MeshInstance3D.new()
		mi.mesh = s.mesh
		var bb: AABB = s.aabb
		var h := bb.size.y * float(s.base)
		var w := maxf(bb.size.x, bb.size.z) * float(s.base)
		var k := 0.97 / maxf(h, w * 2.0)
		s["imp_k"] = k
		mi.scale = Vector3.ONE * k * float(s.base)
		var cx := (col + 0.5) * 0.5
		var cy := float(IMP_ROWS - 1 - row)
		mi.position = Vector3(cx - (bb.position.x + bb.size.x * 0.5) * k * float(s.base), cy - bb.position.y * k * float(s.base) + 0.01, 0)
		vp.add_child(mi)
		holders.append(mi)
		for si in mi.mesh.get_surface_count():
			var src = mi.mesh.surface_get_material(si)
			var tex: Texture2D = _white()
			var col_c := Color.WHITE
			var alpha := false
			var hsv := {}
			if src is ShaderMaterial:
				tex = src.get_shader_parameter("albedo_tex")
				col_c = src.get_shader_parameter("albedo_color")
				alpha = src.get_shader_parameter("use_alpha")
				for p in ["hue_shift", "sat_mul", "val_mul"]:
					if src.get_shader_parameter(p) != null:
						hsv[p] = src.get_shader_parameter(p)
			var a := ShaderMaterial.new()
			a.shader = _capture_shader
			a.set_shader_parameter("albedo_tex", tex)
			a.set_shader_parameter("albedo_color", col_c)
			a.set_shader_parameter("use_alpha", alpha)
			for p in hsv:
				a.set_shader_parameter(p, hsv[p])
			var nmat: ShaderMaterial = a.duplicate()
			nmat.set_shader_parameter("mode", 1)
			mi.set_surface_override_material(si, a)
			cap_mats.append([mi, si, a, nmat])
	for i in 4:
		await RenderingServer.frame_post_draw
	var img_a := vp.get_texture().get_image()
	for c in cap_mats:
		(c[0] as MeshInstance3D).set_surface_override_material(c[1], c[3])
	for i in 3:
		await RenderingServer.frame_post_draw
	var img_n := vp.get_texture().get_image()
	vp.queue_free()
	img_a.convert(Image.FORMAT_RGBA8)
	img_a.fix_alpha_edges()
	img_a.generate_mipmaps()
	img_n.convert(Image.FORMAT_RGBA8)
	img_n.generate_mipmaps()
	_imp_material = ShaderMaterial.new()
	_imp_material.shader = load("res://shaders/impostor.gdshader")
	_imp_material.set_shader_parameter("atlas_albedo", ImageTexture.create_from_image(img_a))
	_imp_material.set_shader_parameter("atlas_normal", ImageTexture.create_from_image(img_n))
	_imp_material.set_shader_parameter("grid", Vector2(IMP_COLS, IMP_ROWS))
	_imp_material.set_shader_parameter("fade_near", 125.0 * view_scale - 30.0)
	_imp_material.set_shader_parameter("fade_len", 40.0)
	_imp_mesh = QuadMesh.new()
	_imp_mesh.size = Vector2(1, 1)
	_imp_mesh.center_offset = Vector3(0, 0.5, 0)
	_imp_mesh.material = _imp_material
	_imp_mesh.custom_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 40, 30))


# ------------------------------------------------------------------ instances
## Fills every multimesh buffer: pure data work, run on a worker thread while the settlements
## are built. finish() then hands the buffers to the renderer on the main thread.
func _compute_instances() -> void:
	var jobs: Array = []
	var tree_end := 125.0 * view_scale
	var shadow_r: float = [30.0, 40.0, 50.0, 80.0][clampi(int(Game.settings.shadows), 0, 3)]
	# tiers per kind: [cell, lod ratio, vis begin, vis end, begin margin, end margin, shadow mode]
	# shadow mode 0 = none, 1 = casts, 2 = shadow-only proxy. Near trees cast their shadows from
	# a reduced-LOD copy: far fewer overlapping leaf cards to rasterise into the shadow cascades.
	var tiers := {
		"tree": [[64.0, 1.0, 0.0, shadow_r, 0.0, 10.0, 0], [64.0, SHADOW_LOD, 0.0, shadow_r, 0.0, 10.0, 2],
			[128.0, MID_LOD, shadow_r - 10.0, tree_end, 10.0, 25.0, 0]],
		"bush": [[64.0, 1.0, 0.0, 115.0 * view_scale, 0.0, 25.0, 0]],
		"rock": [[128.0, 1.0, 0.0, 900.0 * view_scale, 0.0, 60.0, 1]],
	}
	for sid in species.size():
		var s: Dictionary = species[sid]
		var data: PackedFloat32Array = inst_data[sid]
		var base: float = s.base
		for tier in tiers[String(s.kind)]:
			var cell: float = tier[0]
			var buckets := {}
			for k in range(0, data.size(), 5):
				var ck := Vector2i(int(floor(data[k] / cell)), int(floor(data[k + 2] / cell)))
				if not buckets.has(ck):
					buckets[ck] = []
				buckets[ck].append(k)
			for ck in buckets:
				var list: Array = buckets[ck]
				var buf := PackedFloat32Array()
				buf.resize(list.size() * 12)
				var o := 0
				for k in list:
					var sc: float = data[k + 4] * base
					var bs := Basis(Vector3.UP, data[k + 3]).scaled(Vector3.ONE * sc)
					buf[o] = bs.x.x; buf[o + 1] = bs.y.x; buf[o + 2] = bs.z.x; buf[o + 3] = data[k]
					buf[o + 4] = bs.x.y; buf[o + 5] = bs.y.y; buf[o + 6] = bs.z.y; buf[o + 7] = data[k + 1] - 0.05
					buf[o + 8] = bs.x.z; buf[o + 9] = bs.y.z; buf[o + 10] = bs.z.z; buf[o + 11] = data[k + 2]
					o += 12
				jobs.append([s.mesh, tier[1], buf, list.size(), false, ck, cell, tier])
	# far impostors
	var imp := {}
	for sid in species.size():
		var s: Dictionary = species[sid]
		if s.kind != "tree" or not s.has("imp_index"):
			continue
		var data: PackedFloat32Array = inst_data[sid]
		for k in range(0, data.size(), 5):
			var ik := Vector2i(int(floor(data[k] / IMP_CHUNK)), int(floor(data[k + 2] / IMP_CHUNK)))
			if not imp.has(ik):
				imp[ik] = []
			imp[ik].append(Vector2i(sid, k))
	for ik in imp:
		var list: Array = imp[ik]
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var o := 0
		var y0 := INF
		var y1 := -INF
		for e in list:
			var s: Dictionary = species[e.x]
			var data: PackedFloat32Array = inst_data[e.x]
			var k: int = e.y
			var qh: float = data[k + 4] / float(s.imp_k)
			buf[o] = 1.0; buf[o + 3] = data[k]; buf[o + 5] = 1.0; buf[o + 7] = data[k + 1] - 0.1; buf[o + 10] = 1.0; buf[o + 11] = data[k + 2]
			buf[o + 12] = float(s.imp_index); buf[o + 13] = qh; buf[o + 14] = qh * 0.5
			o += 16
			y0 = minf(y0, data[k + 1])
			y1 = maxf(y1, data[k + 1] + qh)
		# large chunks (few draw calls): the near fade happens per tree in the impostor shader
		var box := AABB(Vector3(ik.x * IMP_CHUNK - 20.0, y0 - 5.0, ik.y * IMP_CHUNK - 20.0), Vector3(IMP_CHUNK + 40.0, y1 - y0 + 10.0, IMP_CHUNK + 40.0))
		jobs.append([_imp_mesh, 1.0, buf, list.size(), true, ik, IMP_CHUNK, [IMP_CHUNK, 1.0, 0.0, 3600.0 * view_scale, 0.0, 0.0, 0], box])
	_mm_jobs = jobs


func finish() -> void:
	if _build_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1
	var scenario := get_world_3d().scenario
	var lods := {}
	for j in _mm_jobs:
		var mesh: Mesh = j[0]
		var key := "%d|%.2f" % [mesh.get_instance_id(), float(j[1])]
		if not lods.has(key):
			lods[key] = Assets.lod_rid(mesh, float(j[1]))
		j[0] = lods[key]
		var tier: Array = j[7]
		if j[4] or float(tier[3]) > 400.0:
			# impostors and rocks are visible across the island: always resident
			_rids.append_array(_add_mm(scenario, j[0], j[2], j[3], j[4], j[5], j[6], tier, j[8] if j.size() > 8 else AABB()))
		else:
			# full-detail trees and bushes only exist near the player: streamed in 128 m chunks
			var cell: float = j[6]
			var ck: Vector2i = j[5]
			var chunk := Vector2i(floori((ck.x + 0.5) * cell / STREAM_CHUNK), floori((ck.y + 0.5) * cell / STREAM_CHUNK))
			if not _stream_jobs.has(chunk):
				_stream_jobs[chunk] = []
			_stream_jobs[chunk].append(j)
	_mm_jobs = []
	# mesh tiers fade out by ~150 m (x view distance); keep a chunk's half-diagonal of margin
	_stream_r = 125.0 * view_scale + 25.0 + 100.0


func _add_mm(scenario: RID, mesh_rid: RID, buf: PackedFloat32Array, count: int, custom: bool, ck: Vector2i, cell: float, tier: Array, box := AABB()) -> Array[RID]:
	var mm := RenderingServer.multimesh_create()
	RenderingServer.multimesh_allocate_data(mm, count, RenderingServer.MULTIMESH_TRANSFORM_3D, false, custom)
	RenderingServer.multimesh_set_mesh(mm, mesh_rid)
	RenderingServer.multimesh_set_buffer(mm, buf)
	var inst := RenderingServer.instance_create2(mm, scenario)
	var x0: float = ck.x * cell
	var z0: float = ck.y * cell
	var cy := WorldData.height_at(x0 + cell * 0.5, z0 + cell * 0.5)
	RenderingServer.instance_set_custom_aabb(inst, box if box.size != Vector3.ZERO else AABB(Vector3(x0, cy - 80.0, z0), Vector3(cell, 160.0, cell)))
	RenderingServer.instance_geometry_set_visibility_range(inst, tier[2], tier[3], tier[4], tier[5], RenderingServer.VISIBILITY_RANGE_FADE_SELF)
	RenderingServer.instance_geometry_set_cast_shadows_setting(inst, [RenderingServer.SHADOW_CASTING_SETTING_OFF, RenderingServer.SHADOW_CASTING_SETTING_ON, RenderingServer.SHADOW_CASTING_SETTING_SHADOWS_ONLY][int(tier[6])])
	return [inst, mm]


# ------------------------------------------------------------------ streaming
## Builds the full-detail chunks around `pos`: one chunk per frame while moving, all at once
## after a teleport (respawn, loading a save) or when forced.
func update_stream(pos: Vector3, force := false) -> void:
	var c := Vector2i(floori(pos.x / STREAM_CHUNK), floori(pos.z / STREAM_CHUNK))
	var p2 := Vector2(pos.x, pos.z)
	if c != _stream_center:
		force = force or absi(c.x - _stream_center.x) > 2 or absi(c.y - _stream_center.y) > 2
		_stream_center = c
		_stream_todo.clear()
		var r := int(ceil(_stream_r / STREAM_CHUNK)) + 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var k := c + Vector2i(dx, dz)
				if _stream_jobs.has(k) and not _stream_live.has(k) and _chunk_dist(k, p2) < _stream_r:
					_stream_todo.append(k)
		_stream_todo.sort_custom(func(a, b): return _chunk_dist(a, p2) < _chunk_dist(b, p2))
		for k in _stream_live.keys():
			if _chunk_dist(k, p2) > _stream_r + STREAM_CHUNK:
				for rid in _stream_live[k]:
					RenderingServer.free_rid(rid)
				_stream_live.erase(k)
	var budget := 1000 if force else 1
	while budget > 0 and not _stream_todo.is_empty():
		var k: Vector2i = _stream_todo.pop_front()
		budget -= 1
		if _stream_live.has(k):
			continue
		var rids: Array[RID] = []
		var scenario := get_world_3d().scenario
		for j in _stream_jobs[k]:
			rids.append_array(_add_mm(scenario, j[0], j[2], j[3], j[4], j[5], j[6], j[7]))
		_stream_live[k] = rids


func _chunk_dist(k: Vector2i, p2: Vector2) -> float:
	return Vector2((k.x + 0.5) * STREAM_CHUNK, (k.y + 0.5) * STREAM_CHUNK).distance_to(p2)


# ------------------------------------------------------------------ collisions
func _process(_delta: float) -> void:
	var p: Node3D = Game.player_ref
	if p == null:
		return
	update_stream(p.global_position)
	var c := Vector2(p.global_position.x, p.global_position.z)
	if c.distance_to(_col_center) < 8.0:
		return
	_col_center = c
	var cx := int(floor(c.x / 32.0))
	var cz := int(floor(c.y / 32.0))
	var used := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var arr = _col_grid.get(Vector2i(cx + dx, cz + dz))
			if arr == null:
				continue
			for t in arr:
				if used >= 260:
					break
				var body := _get_body(used)
				used += 1
				var shape: CylinderShape3D = (body.get_child(0) as CollisionShape3D).shape
				shape.radius = maxf(float(t[3]), 0.15)
				shape.height = clampf(float(t[4]), 1.5, 8.0)
				body.global_position = Vector3(t[0], float(t[1]) + shape.height * 0.5, t[2])
				body.process_mode = Node.PROCESS_MODE_INHERIT
	for i in range(used, _col_bodies.size()):
		_col_bodies[i].global_position = Vector3(0, -2000, 0)


func _get_body(i: int) -> StaticBody3D:
	while _col_bodies.size() <= i:
		var b := StaticBody3D.new()
		b.collision_layer = 1
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = CylinderShape3D.new()
		b.add_child(cs)
		add_child(b)
		_col_bodies.append(b)
	return _col_bodies[i]


## Nearest trees (for animals/NPC avoidance & gameplay). Returns Array of Vector3.
func trees_near(p: Vector3, r: float) -> Array:
	var out := []
	var cx := int(floor(p.x / 32.0))
	var cz := int(floor(p.z / 32.0))
	var n := int(ceil(r / 32.0))
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			for t in _col_grid.get(Vector2i(cx + dx, cz + dz), []):
				var q := Vector3(t[0], t[1], t[2])
				if q.distance_squared_to(p) < r * r:
					out.append(q)
	return out
