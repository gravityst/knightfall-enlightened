class_name Assets
## Loads imported model scenes once and hands out their meshes, materials and normalized
## instances. Kit pieces are returned as [mesh, transform] parts so buildings can be merged.

static var _parts := {}        # path -> Array of [Mesh, Transform3D]
static var _scenes := {}       # path -> PackedScene
static var _norm := {}         # "path|size" -> scale
static var _aabb := {}         # path -> AABB of all parts
static var _pending := {}      # path -> true while it loads on a worker thread
static var _used := {}         # every model this session has loaded (written to the manifest)

const MANIFEST := "user://asset_manifest.txt"
## True on the Compatibility renderer (the browser build). Its per-instance shader buffer holds
## only 4096 values, which a busy town overflows, so there each mesh gets its own material.
static var compat: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
static var _ushaders := {}


## A shader with per-instance uniforms; on the Compatibility renderer, its plain-uniform twin.
static func instanced_shader(path: String) -> Shader:
	if not compat:
		return load(path)
	if not _ushaders.has(path):
		var s := Shader.new()
		s.code = (load(path) as Shader).code.replace("instance uniform", "uniform")
		_ushaders[path] = s
	return _ushaders[path]


## Sets a per-instance shader value (on Compatibility: on the mesh's own materials).
static func set_iparam(gi: GeometryInstance3D, n: StringName, v) -> void:
	if not compat:
		gi.set_instance_shader_parameter(n, v)
		return
	if gi.material_override is ShaderMaterial:
		(gi.material_override as ShaderMaterial).set_shader_parameter(n, v)
	var mi := gi as MeshInstance3D
	if mi and mi.mesh:
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m:
				m.set_shader_parameter(n, v)
const SHIPPED_MANIFEST := "res://world/asset_manifest.txt"


## Starts loading, on worker threads, every model the world needed last time, so they are
## ready by the time the world is built. Called from the title screen and the world loader.
static func prefetch() -> void:
	for line in _manifest_lines():
		var p := line.strip_edges()
		if p.is_empty() or _scenes.has(p) or _pending.has(p) or not ResourceLoader.exists(p):
			continue
		if ResourceLoader.load_threaded_request(p) == OK:
			_pending[p] = true


## Takes ownership of finished background loads (at shutdown: waits for all of them), so no
## load request is left dangling.
static func settle_prefetch(wait := false) -> void:
	for p in _pending.keys():
		if wait or ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var res := ResourceLoader.load_threaded_get(p) as PackedScene
			if res:
				_scenes[p] = res
			_pending.erase(p)


## Adds this session's models to the manifest so the next launch can prefetch them.
static func save_manifest() -> void:
	var known := {}
	var added := false
	for line in _manifest_lines():
		var p := line.strip_edges()
		if ResourceLoader.exists(p):
			known[p] = true
		else:
			added = true          # a model that no longer exists: rewrite without it
	for p in _used:
		if not known.has(p):
			known[p] = true
			added = true
	if added or not FileAccess.file_exists(MANIFEST):
		var f := FileAccess.open(MANIFEST, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(PackedStringArray(known.keys())))


## Where a hand-held item is gripped, in model space: [grip point, axis towards the business end,
## guard axis, length]. Blades: the crossguard is the widest slice near one end and the hand sits
## between it and the pommel. Shafts (torches): held a quarter of the way up from the narrow end.
static var _grips := {}
static func grip(path: String, shaft := false) -> Array:
	var key := path + ("|shaft" if shaft else "")
	if _grips.has(key):
		return _grips[key]
	var m := merged_mesh(path)
	var bb := m.get_aabb()
	var ax := bb.get_longest_axis_index()
	var c := bb.get_center()
	var n := 20
	var width := PackedFloat32Array()
	width.resize(n)
	var ext: Array[Vector3] = []
	ext.resize(n)
	ext.fill(Vector3.ZERO)
	for s in m.get_surface_count():
		for v in (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var i := clampi(int((v[ax] - bb.position[ax]) / bb.size[ax] * n), 0, n - 1)
			var o := v - c
			o[ax] = 0.0
			width[i] = maxf(width[i], o.length())
			ext[i] = ext[i].max(o.abs())
	var best := 0
	for i in n:
		if (shaft or i < n * 0.4 or i >= n * 0.6) and width[i] > width[best]:
			best = i
	var wide_low := best < n / 2
	var t := 0.0
	if shaft:
		t = 0.75 if wide_low else 0.25           # away from the torch head
		wide_low = not wide_low
	else:
		var gt := (best + 0.5) / n
		t = gt * 0.55 if wide_low else 1.0 - (1.0 - gt) * 0.55
	var p := c
	p[ax] = bb.position[ax] + bb.size[ax] * t
	var fwd := Vector3.ZERO
	fwd[ax] = 1.0 if wide_low else -1.0          # from the hand towards the tip / torch head
	var e: Vector3 = ext[best]
	e[ax] = -1.0
	var guard := Vector3.ZERO
	guard[e.max_axis_index()] = 1.0
	var out := [p, fwd, guard, bb.size[ax]]
	_grips[key] = out
	return out


## This machine's manifest, else the one shipped with the game.
static func _manifest_lines() -> PackedStringArray:
	for path in [MANIFEST, SHIPPED_MANIFEST]:
		if FileAccess.file_exists(path):
			return FileAccess.get_file_as_string(path).split("\n", false)
	return PackedStringArray()


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		var res: PackedScene = null
		if _pending.has(path):
			_pending.erase(path)
			res = ResourceLoader.load_threaded_get(path) as PackedScene
		_scenes[path] = res if res else load(path)
		_used[path] = true
	return _scenes[path]


## Returns Array[[Mesh, Transform3D]] for every MeshInstance3D in the model.
static func parts(path: String) -> Array:
	if _parts.has(path):
		return _parts[path]
	var out := []
	var ps := scene(path)
	if ps == null:
		push_warning("Missing model " + path)
		_parts[path] = out
		return out
	var inst := ps.instantiate()
	var holder := Node3D.new()
	holder.add_child(inst)
	var bb := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var xf := _rel_xform(holder, mi)
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		# bake surface override materials into a copy so merging keeps them
		var has_override := false
		for s in mesh.get_surface_count():
			if mi.get_surface_override_material(s) != null:
				has_override = true
		if has_override:
			mesh = mesh.duplicate()
			for s in mesh.get_surface_count():
				var om = mi.get_surface_override_material(s)
				if om:
					mesh.surface_set_material(s, om)
		out.append([mesh, xf])
		var a := xf * mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	holder.free()
	_parts[path] = out
	_aabb[path] = bb
	return out


## A single named node of a multi-piece kit file (e.g. the fort kit): [Mesh, Transform3D].
static var _named := {}
static func part_named(path: String, node_name: String) -> Array:
	var key := path + "|" + node_name
	if _named.has(key):
		return _named[key]
	var inst := scene(path).instantiate()
	var holder := Node3D.new()
	holder.add_child(inst)
	var out := []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).ends_with(node_name) or String(mi.get_parent().name).ends_with(node_name):
			var xf := _rel_xform(holder, mi)
			out = [mi.mesh, Transform3D(xf.basis, Vector3.ZERO)]   # kit files lay pieces out side by side: keep each piece's own pivot
			break
	holder.free()
	_named[key] = out
	return out


static func aabb(path: String) -> AABB:
	if not _aabb.has(path):
		parts(path)
	return _aabb.get(path, AABB())


static func _rel_xform(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## First mesh of a model (for MultiMesh use). Merges multi-part models into one mesh.
## A skinned surface without its bone data, so it can be merged with static geometry
## (mixing the two in one SurfaceTool leaves the static vertices without weights).
static var _unskinned := {}
static func unskinned(mesh: Mesh, s: int) -> Array:
	if not (mesh is ArrayMesh) or not ((mesh as ArrayMesh).surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES):
		return [mesh, s]
	var key := "%d:%d" % [mesh.get_instance_id(), s]
	if not _unskinned.has(key):
		var arr := mesh.surface_get_arrays(s)
		arr[Mesh.ARRAY_BONES] = null
		arr[Mesh.ARRAY_WEIGHTS] = null
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mesh.surface_get_material(s))
		_unskinned[key] = m
	return [_unskinned[key], 0]


static var _merged := {}
static func merged_mesh(path: String) -> Mesh:
	if _merged.has(path):
		return _merged[path]
	var ps := parts(path)
	if ps.size() == 1 and ps[0][1].is_equal_approx(Transform3D.IDENTITY):
		_merged[path] = ps[0][0]
		return ps[0][0]
	var by_mat := {}
	var order := []
	for p in ps:
		var mesh: Mesh = p[0]
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			var key := mat.get_instance_id() if mat else 0
			if not by_mat.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[key] = [st, mat]
				order.append(key)
			var u := unskinned(mesh, s)
			(by_mat[key][0] as SurfaceTool).append_from(u[0], u[1], p[1])
	var out := ArrayMesh.new()
	for key in order:
		var st: SurfaceTool = by_mat[key][0]
		out = st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, by_mat[key][1])
	_merged[path] = out
	return out


## Instantiates a model scaled so that its largest horizontal/vertical extent matches `size`.
## axis: "y" = height, "xz" = longest horizontal side, "max" = largest dimension.
static func instance_sized(path: String, size: float, axis := "y") -> Node3D:
	var inst: Node3D = scene(path).instantiate()
	var holder := Node3D.new()
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child(inst)
	var key := "%s|%s|%s" % [path, size, axis]
	if not _norm.has(key):
		var bb := _visual_aabb(pivot)
		var ext := bb.size.y
		if axis == "xz":
			ext = maxf(bb.size.x, bb.size.z)
		elif axis == "max":
			ext = maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		_norm[key] = [size / maxf(ext, 0.0001), bb]
	var sc: float = _norm[key][0]
	var b: AABB = _norm[key][1]
	pivot.scale = Vector3.ONE * sc
	pivot.position = Vector3(-(b.position.x + b.size.x * 0.5) * sc, -b.position.y * sc, -(b.position.z + b.size.z * 0.5) * sc)
	return holder


## Visual bounds of a (possibly skinned) model in its own space. For skinned meshes the bind
## pose may be in different units than the posed result, so skeleton bone extents are used too.
static func _visual_aabb(root: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		var sk: Skeleton3D = skels[0]
		var sx := _rel_xform(root, sk)
		for i in sk.get_bone_count():
			var p := sx * sk.get_bone_global_rest(i).origin
			if first:
				bb = AABB(p, Vector3.ZERO)
				first = false
			else:
				bb = bb.expand(p)
		# bones sit inside the body: pad a little
		bb = bb.grow(bb.size.length() * 0.06)
		bb.position.y = minf(bb.position.y, 0.0)
		return bb
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var a: AABB = _rel_xform(root, mi) * mi.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	return bb


## A rendering-server mesh that reuses `mesh`'s vertices with its precomputed LOD index
## buffer closest to `ratio` of the full triangle count (materials are shared).
static var _lod_cache := {}
static func lod_rid(mesh: Mesh, ratio: float) -> RID:
	var key := "%d|%.2f" % [mesh.get_rid().get_id(), ratio]
	if _lod_cache.has(key):
		return _lod_cache[key]
	if ratio >= 0.99:
		_lod_cache[key] = mesh.get_rid()
		return mesh.get_rid()
	var rid := RenderingServer.mesh_create()
	for s in mesh.get_surface_count():
		var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		var ib := 2 if int(d.vertex_count) < 65536 else 4
		var base := maxi(int(d.index_count), 1)
		var lods: Array = d.get("lods", [])
		var best := -1
		var best_diff := absf(1.0 - ratio)
		for i in lods.size():
			var cnt: int = (lods[i].index_data as PackedByteArray).size() / ib
			var diff := absf(float(cnt) / base - ratio)
			if diff < best_diff:
				best_diff = diff
				best = i
		if best >= 0:
			d["index_data"] = lods[best].index_data
			d["index_count"] = (lods[best].index_data as PackedByteArray).size() / ib
		d["lods"] = []
		RenderingServer.mesh_add_surface(rid, d)
		var mat := mesh.surface_get_material(s)
		if mat:
			RenderingServer.mesh_surface_set_material(rid, s, mat.get_rid())
	_lod_cache[key] = rid
	_lod_owned.append(rid)
	return rid


## LOD meshes are shared by every world load in a session; freed once at shutdown.
static var _lod_owned: Array[RID] = []
static func free_lods() -> void:
	for rid in _lod_owned:
		RenderingServer.free_rid(rid)
	_lod_owned.clear()
	_lod_cache.clear()


## Builds a StandardMaterial3D-based tint copy of a mesh's materials (used for variants).
static func tinted(mesh: Mesh, tint: Color) -> Mesh:
	var m := mesh.duplicate()
	for s in m.get_surface_count():
		var mat = m.surface_get_material(s)
		if mat is BaseMaterial3D:
			var c: BaseMaterial3D = mat.duplicate()
			c.albedo_color = c.albedo_color * tint
			m.surface_set_material(s, c)
	return m
