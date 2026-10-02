class_name Interactables
## Small interactive world objects: doors, beds, chests and the castle portcullis.


class Door extends Node3D:
	var body: AnimatableBody3D
	var open := false
	var _users := 0
	var _angle := 0.0
	var _target := 0.0
	var swing := -1.0
	func setup(mesh_parts: Array, width: float) -> void:
		body = AnimatableBody3D.new()
		body.collision_layer = 1 | 32
		body.collision_mask = 0
		body.sync_to_physics = false
		add_child(body)
		for p in mesh_parts:
			var mi := MeshInstance3D.new()
			mi.mesh = p[0]
			mi.transform = p[1]
			body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(width, 2.1, 0.12)
		cs.shape = bx
		cs.position = Vector3(width * 0.5, 1.05, 0.0)
		body.add_child(cs)
	func get_interaction(_p) -> String:
		return "[E] Close door" if open else "[E] Open door"
	func interact(_p) -> void:
		set_open(not open)
	func set_open(v: bool) -> void:
		if v == open:
			return
		open = v
		_target = deg_to_rad(95.0) * swing if v else 0.0
		Audio.play_at("door_open" if v else "door_close", global_position)
	func npc_pass() -> void:
		_users += 1
		if not open:
			set_open(true)
		get_tree().create_timer(3.5).timeout.connect(func():
			_users -= 1
			if _users <= 0 and open:
				var pl: Node3D = Game.player_ref
				if pl == null or pl.global_position.distance_to(global_position) > 2.5:
					set_open(false))
	func _physics_process(delta: float) -> void:
		if absf(_angle - _target) > 0.001:
			_angle = move_toward(_angle, _target, delta * 3.2)
			body.rotation.y = _angle


class Bed extends StaticBody3D:
	var owner_name := ""
	var inn := false
	var settlement := ""
	func get_interaction(_p) -> String:
		if inn:
			return "[E] Sleep in the rented bed" if Game.has_meta("rented_" + settlement) else "Inn bed (rent a room from the innkeeper)"
		if owner_name == "" or Game.reputation >= 40.0:
			return "[E] Sleep"
		return "%s's bed (private)" % owner_name
	func interact(_p) -> void:
		if inn and not Game.has_meta("rented_" + settlement):
			Game.notify.emit("You need to rent a room from the innkeeper first.", "warn")
			return
		if not inn and owner_name != "" and Game.reputation < 40.0:
			Game.notify.emit("This bed belongs to %s. You'd be trespassing." % owner_name, "warn")
			return
		if inn:
			Game.remove_meta("rented_" + settlement)
		Game.world_ref.call("sleep", 8.0, true)


class Chest extends StaticBody3D:
	var chest_id := ""
	var owner_name := ""
	var settlement := ""
	var loot: Dictionary = {}
	var silver := 0
	func get_interaction(_p) -> String:
		if Game.looted.has(chest_id):
			return "Empty chest"
		return "[E] Search chest" if owner_name == "" else "[E] Steal from %s's chest" % owner_name
	func interact(p) -> void:
		if Game.looted.has(chest_id):
			return
		if owner_name != "":
			var npcs = Game.world_ref.npcs if Game.world_ref else null
			if npcs and npcs.call("witnesses", global_position, 14.0) > 0:
				Game.commit_crime(settlement, 15.0, "You were seen stealing!")
				npcs.call("alert_guards", global_position, settlement)
		Game.looted[chest_id] = true
		Audio.play_at("chest", global_position)
		var got := []
		for id in loot:
			Game.add_item(id, int(loot[id]), false)
			got.append("%d %s" % [int(loot[id]), Items.display_name(id)])
		if silver > 0:
			Game.earn(silver)
			got.append(Items.price_text(silver))
		Game.notify.emit("Found: " + (", ".join(got) if got.size() > 0 else "nothing of value"), "item")


class Portcullis extends Node3D:
	var gate: Node3D
	var closed := false
	var settlement := ""
	var _y := 0.0
	var height := 4.5
	var body: AnimatableBody3D
	func _physics_process(delta: float) -> void:
		var target := 0.0 if closed else height
		if absf(_y - target) > 0.001:
			_y = move_toward(_y, target, delta * (2.5 if closed else 0.8))
			gate.position.y = _y
			body.position.y = _y
	func get_interaction(_p) -> String:
		return "Portcullis (lowered by the guards)" if closed else ""
	func set_closed(v: bool) -> void:
		if v != closed:
			closed = v
			Audio.play_at("portcullis", global_position)
