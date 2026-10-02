extends Node
## Loads the baked island (see tools/worldgen) and answers spatial queries:
## terrain height, water level, biome, temperature, nearest settlement, etc.

const SIZE := 6144.0
const HALF := 3072.0
const HM_RES := 4096
const HM_TEXEL := 1.5
const WATER_RES := 1024
const WATER_TEXEL := 6.0
const SPLAT_RES := 2048
const DIR := "res://world/"

enum Biome { OCEAN, BEACH, PLAINS, FOREST, TUNDRA, MOUNTAIN, SNOW, DESERT, WATER }
const BIOME_NAMES := ["Ocean", "Coast", "Plains", "Forest", "Tundra", "Mountains", "Snowfields", "Desert", "Water"]

var heights := PackedFloat32Array()
var water_levels := PackedFloat32Array()
var minmax := PackedFloat32Array()
var biome_img: Image
var info: Dictionary = {}
var settlements: Array = []
var pois: Array = []
var roads: Array = []
var height_tex: ImageTexture
var normal_tex: ImageTexture
var water_tex: ImageTexture
var flow_tex: ImageTexture
var splat0_tex: ImageTexture
var splat1_tex: ImageTexture
var biome_tex: ImageTexture
var albedo_array: Texture2DArray
var normal_array: Texture2DArray
var loaded := false

# map textures are decoded on worker threads (started from the title screen)
var _jobs := {}         # file -> WorkerThreadPool task id
var _decoded := {}      # file -> Image, or Array[Image] for the material atlases
var _mutex := Mutex.new()


func prefetch() -> void:
	if loaded or not _jobs.is_empty():
		return
	for f in ["normal.png", "splat0.png", "splat1.png", "biome.png", "flow.png"]:
		_jobs[f] = WorkerThreadPool.add_task(_decode.bind(f, f == "normal.png"))
	for f in ["tex_albedo.png", "tex_normal.png"]:
		_jobs[f] = WorkerThreadPool.add_task(_decode_atlas.bind(f))


## The browser build ships the big maps as WebP (a fifth of the PNG's size); same name otherwise.
func _path(file: String) -> String:
	var webp := DIR + file.get_basename() + ".webp"
	return webp if FileAccess.file_exists(webp) else DIR + file


func _decode(file: String, mips: bool) -> void:
	var img := Image.load_from_file(_path(file))
	if mips:
		img.generate_mipmaps()
	_mutex.lock()
	_decoded[file] = img
	_mutex.unlock()


## Splits a 4x4 material atlas into the 13 mipmapped layers of a texture array.
func _decode_atlas(file: String) -> void:
	var atlas := Image.load_from_file(_path(file))
	var ts := atlas.get_width() / 4
	var imgs: Array[Image] = []
	for i in 13:
		var sub := atlas.get_region(Rect2i((i % 4) * ts, (i / 4) * ts, ts, ts))
		sub.generate_mipmaps()
		imgs.append(sub)
	_mutex.lock()
	_decoded[file] = imgs
	_mutex.unlock()


func _take(file: String):
	if not _jobs.has(file):
		prefetch()
	WorkerThreadPool.wait_for_task_completion(_jobs[file])
	_jobs.erase(file)
	_mutex.lock()
	var out = _decoded[file]
	_decoded.erase(file)
	_mutex.unlock()
	return out


func _exit_tree() -> void:
	for f in _jobs:
		WorkerThreadPool.wait_for_task_completion(_jobs[f])
	_jobs.clear()


func load_all(progress: Callable) -> void:
	if loaded:
		progress.call(0.28, "Reading the chronicles")
		return
	prefetch()
	progress.call(0.02, "Reading the lay of the land")
	await get_tree().process_frame
	var bytes := FileAccess.get_file_as_bytes(DIR + "height.bin")
	heights = bytes.to_float32_array()
	height_tex = ImageTexture.create_from_image(Image.create_from_data(HM_RES, HM_RES, false, Image.FORMAT_RF, bytes))
	progress.call(0.08, "Charting rivers and lakes")
	await get_tree().process_frame
	var wb := FileAccess.get_file_as_bytes(DIR + "water.bin")
	water_levels = wb.to_float32_array()
	water_tex = ImageTexture.create_from_image(Image.create_from_data(WATER_RES, WATER_RES, false, Image.FORMAT_RF, wb))
	minmax = FileAccess.get_file_as_bytes(DIR + "minmax.bin").to_float32_array()
	flow_tex = ImageTexture.create_from_image(_take("flow.png"))
	progress.call(0.12, "Surveying the realm")
	await get_tree().process_frame
	normal_tex = ImageTexture.create_from_image(_take("normal.png"))
	splat0_tex = ImageTexture.create_from_image(_take("splat0.png"))
	splat1_tex = ImageTexture.create_from_image(_take("splat1.png"))
	biome_img = _take("biome.png")
	biome_tex = ImageTexture.create_from_image(biome_img)
	progress.call(0.18, "Gathering soil and stone")
	await get_tree().process_frame
	albedo_array = Texture2DArray.new()
	albedo_array.create_from_images(_take("tex_albedo.png"))
	normal_array = Texture2DArray.new()
	normal_array.create_from_images(_take("tex_normal.png"))
	progress.call(0.26, "Reading the chronicles")
	await get_tree().process_frame
	info = JSON.parse_string(FileAccess.get_file_as_string(DIR + "world.json"))
	settlements = info.get("settlements", [])
	pois = info.get("pois", [])
	roads = info.get("roads", [])
	for i in settlements.size():
		settlements[i]["id"] = i
	loaded = true


# ------------------------------------------------------------------ queries
func height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / HM_TEXEL
	var fz := (z + HALF) / HM_TEXEL
	if fx < 0.0 or fz < 0.0 or fx >= HM_RES - 1 or fz >= HM_RES - 1:
		return -60.0
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * HM_RES + ix
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + HM_RES], heights[i + HM_RES + 1], tx)
	return lerpf(a, b, tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.5
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func water_level_at(x: float, z: float) -> float:
	var fx := (x + HALF - 2.25) / WATER_TEXEL
	var fz := (z + HALF - 2.25) / WATER_TEXEL
	if fx < 0.0 or fz < 0.0 or fx >= WATER_RES - 1 or fz >= WATER_RES - 1:
		return 0.0
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * WATER_RES + ix
	var a := lerpf(water_levels[i], water_levels[i + 1], tx)
	var b := lerpf(water_levels[i + WATER_RES], water_levels[i + WATER_RES + 1], tx)
	return lerpf(a, b, tz)


## Depth of water above the terrain at (x, z); negative on dry land.
func water_depth_at(x: float, z: float) -> float:
	return water_level_at(x, z) - height_at(x, z)


func _biome_px(x: float, z: float) -> Color:
	var i := clampi(int((x + HALF) / SIZE * SPLAT_RES), 0, SPLAT_RES - 1)
	var j := clampi(int((z + HALF) / SIZE * SPLAT_RES), 0, SPLAT_RES - 1)
	return biome_img.get_pixel(i, j)


func biome_at(x: float, z: float) -> int:
	return int(round(_biome_px(x, z).b * 255.0 / 20.0))


## 0 = arctic cold, 1 = desert heat. Includes altitude.
func temperature_at(x: float, z: float) -> float:
	return _biome_px(x, z).r


func moisture_at(x: float, z: float) -> float:
	return _biome_px(x, z).g


func grass_at(x: float, z: float) -> float:
	return _biome_px(x, z).a


## Clothing climate for people living around (x, z): "cold", "desert" or "temperate".
func climate_at(x: float, z: float) -> String:
	var b := biome_at(x, z)
	var t := temperature_at(x, z)
	if b == Biome.DESERT:
		return "desert"
	if b in [Biome.TUNDRA, Biome.SNOW, Biome.MOUNTAIN] or t < 0.4:
		return "cold"
	return "temperate"


func nearest_settlement(p: Vector3, max_dist := 1e9) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_dist * max_dist
	for s in settlements:
		var d := Vector2(s.x - p.x, s.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = s
	return best


func settlement_by_name(n: String) -> Dictionary:
	for s in settlements:
		if s.name == n:
			return s
	return {}


func location_name_at(p: Vector3) -> String:
	for s in settlements:
		if Vector2(s.x - p.x, s.z - p.z).length() < float(s.radius) * 1.15:
			return s.name
	for q in pois:
		if Vector2(q.x - p.x, q.z - p.z).length() < float(q.radius) * 1.6 + 10.0:
			return q.name
	var best := ""
	var bd := 1e12
	for r in info.get("regions", []):
		var d := Vector2(r.x - p.x, r.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = r.name
	return best


func is_inside_map(x: float, z: float) -> bool:
	return absf(x) < HALF - 10.0 and absf(z) < HALF - 10.0
