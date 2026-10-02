extends Node
## Browser builds only: fetches the island's data packs from beside the page (or finds them in
## the browser's storage from an earlier visit) and mounts them, so res://world/ and
## res://sounds/ exist. On the desktop it finishes at once.

signal progress(frac: float, text: String)
signal finished(ok: bool)

const INFO := preload("res://scripts/core/web_build.gd")
static var mounted := false
var _http: HTTPRequest
var _queue: Array = []
var _total := 0.0
var _done := 0.0
var _current := {}
var _dir := ""


func start() -> void:
	if mounted or INFO.PACKS.is_empty() or not OS.has_feature("web"):
		mounted = true
		finished.emit.call_deferred(true)
		return
	_dir = "user://packs/%s/" % INFO.BUILD
	DirAccess.make_dir_recursive_absolute(_dir)
	_clear_old()
	for p in INFO.PACKS:
		_total += float(p.size)
		_queue.append(p)
	_http = HTTPRequest.new()
	_http.download_chunk_size = 1 << 20
	_http.accept_gzip = false       # the browser already unzips what GitHub Pages compresses
	_http.request_completed.connect(_on_done)
	add_child(_http)
	_next()


func _next() -> void:
	while not _queue.is_empty():
		_current = _queue.pop_front()
		var path: String = _dir + String(_current.file)
		if FileAccess.file_exists(path) and _size(path) == int(_current.size):
			_mount(path)          # kept from an earlier visit
			continue
		var base := str(JavaScriptBridge.eval("window.location.href.split('?')[0].split('#')[0].replace(/[^/]*$/, '')"))
		var err := _http.request(base + String(_current.file) + "?v=" + INFO.BUILD)
		if err != OK:
			finished.emit(false)
		return
	mounted = true
	progress.emit(1.0, "The island is ready")
	finished.emit(true)


func _process(_d: float) -> void:
	if _http and _http.get_http_client_status() == HTTPClient.STATUS_BODY:
		var got := _done + float(_http.get_downloaded_bytes())
		progress.emit(got / maxf(_total, 1.0), "Fetching the island: %d of %d MB (cached for next time)" % [int(got / 1048576.0), int(_total / 1048576.0)])


func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var path: String = _dir + String(_current.file)
	print("WEB pack %s: result %d, http %d, %d of %d bytes" % [_current.file, result, code, body.size(), int(_current.size)])
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() != int(_current.size):
		push_warning("Pack download failed: %s (%d, %d, %d bytes)" % [_current.file, result, code, body.size()])
		finished.emit(false)
		return
	# kept in the browser's storage, so the next visit skips the download
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:          # (no folder for this build: fall back to the top of the user folder)
		print("WEB cannot write %s (%s); using user://" % [path, error_string(FileAccess.get_open_error())])
		path = "user://" + String(_current.file)
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(body)
		f.close()
	_mount(path)
	_next()


func _mount(path: String) -> void:
	if not ProjectSettings.load_resource_pack(path):
		push_warning("Could not mount " + path)
	else:
		print("WEB mounted ", path)
	_done += float(_current.size)
	progress.emit(_done / maxf(_total, 1.0), "Fetching the island")


func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else -1


## Packs from older builds are dropped so the browser's storage doesn't fill up.
func _clear_old() -> void:
	for d in DirAccess.get_directories_at("user://packs/"):
		if d != INFO.BUILD:
			for f in DirAccess.get_files_at("user://packs/" + d):
				DirAccess.remove_absolute("user://packs/%s/%s" % [d, f])
			DirAccess.remove_absolute("user://packs/" + d)
