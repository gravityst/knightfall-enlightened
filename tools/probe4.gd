extends SceneTree
func _init() -> void:
	await process_frame
	print("screen size ", DisplayServer.screen_get_size(), " scale ", DisplayServer.screen_get_scale(), " window ", DisplayServer.window_get_size(), " vp tex ", root.get_texture().get_size())
	for p in ["res://assets/nature/CommonTree_1.gltf", "res://assets/nature/Pine_2.gltf", "res://assets/nature/Grass_Common_Short.gltf", "res://assets/nature/Clover_2.gltf", "res://assets/nature/Bush_Common.gltf"]:
		var m: Mesh = Assets.merged_mesh(p)
		var line: String = String(p).get_file() + ": "
		for s in m.get_surface_count():
			var d := RenderingServer.mesh_get_surface(m.get_rid(), s)
			var ib: int = 2 if int(d.vertex_count) < 65536 else 4
			var lods := []
			for l in d.get("lods", []):
				lods.append("%d" % ((l.index_data as PackedByteArray).size() / ib / 3))
			line += "[s%d tris=%d lods=%s] " % [s, int(d.index_count) / 3, ",".join(lods)]
		print(line)
	quit()
