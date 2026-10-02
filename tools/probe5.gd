extends Node
func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var st = get_parent().settlements
	var node: Node3D = st.infos[0].node
	var n := 0
	for c in node.get_children():
		if c is MultiMeshInstance3D and n < 12:
			var mm: MultiMesh = c.multimesh
			print("MMI mesh=", mm.mesh.resource_name, " path=", mm.mesh.resource_path.get_file(), " count=", mm.instance_count, " aabb=", mm.get_aabb(), " t0=", mm.get_instance_transform(0).origin if mm.instance_count > 0 else Vector3.ZERO)
			n += 1
	get_tree().quit()
