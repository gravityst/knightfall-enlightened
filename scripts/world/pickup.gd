extends RigidBody3D
## An item lying in the world: falls and tumbles as a rigid body, comes to rest (and stops
## simulating), can be knocked about, and E picks it back up. Kept in Game.world_drops.

const IM := preload("res://scripts/core/item_models.gd")
var item := ""
var count := 1

func get_interaction(_p) -> String:
	return "[E] Pick up %s%s" % [Items.display_name(item), " (%d)" % count if count > 1 else ""]

func interact(_p) -> void:
	Game.add_item(item, count)
	Audio.play_at("item_pick", global_position, 2.0)
	Game.world_drops = Game.world_drops.filter(func(d): return d.get("node") != self)
	queue_free()

var _rest := 0.0

func _physics_process(delta: float) -> void:
	var g := WorldData.height_at(global_position.x, global_position.z)
	if global_position.y < g - 1.5:
		global_position.y = g + 0.3
		linear_velocity = Vector3.ZERO
	if freeze:
		return
	_rest = _rest + delta if linear_velocity.length() < 0.08 else 0.0
	if _rest > 1.0:          # at rest: stop simulating (terrain collision only exists near the player)
		freeze = true
		_save_pos()

func wake(impulse: Vector3) -> void:
	freeze = false
	_rest = 0.0
	apply_central_impulse(impulse)

func _save_pos() -> void:
	for d in Game.world_drops:
		if d.get("node") == self:
			d.x = global_position.x
			d.y = global_position.y
			d.z = global_position.z

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.get_contact_count() > 0 and state.linear_velocity.length() > 2.5 and not has_meta("clunk"):
		set_meta("clunk", true)
		Audio.play_at("item_drop", global_position, -4.0)


## Drops `count` of an item at `at` with a toss (world velocity); returns the body.
static func drop(parent: Node, id: String, count: int, at: Vector3, toss: Vector3) -> RigidBody3D:
	var b = load("res://scripts/world/pickup.gd").new()
	b.item = id
	b.count = count
	b.collision_layer = 32
	b.collision_mask = 1 | 32
	b.contact_monitor = true
	b.max_contacts_reported = 2
	b.continuous_cd = true
	var vis := IM.build(id, maxf(float(IM.SPECS.get(id, {}).get("size", 0.3)), 0.12))
	b.add_child(vis)
	var bb := IM._bounds(vis)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(bb.size.x, 0.06), maxf(bb.size.y, 0.04), maxf(bb.size.z, 0.06))
	cs.shape = box
	cs.position = bb.get_center()
	b.add_child(cs)
	var vol := box.size.x * box.size.y * box.size.z
	b.mass = clampf(vol * 400.0, 0.2, 8.0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.15
	b.physics_material_override = pm
	parent.add_child(b)
	b.global_position = at
	b.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.linear_velocity = toss
	b.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	Game.world_drops.append({"id": id, "count": count, "x": at.x, "y": at.y, "z": at.z, "node": b})
	if Game.world_drops.size() > 80:       # the oldest litter is tidied away
		var old: Dictionary = Game.world_drops.pop_front()
		if is_instance_valid(old.get("node")):
			(old.node as Node).queue_free()
	return b


## Puts saved drops back where they lay (resting, until disturbed).
static func restore(parent: Node, drops: Array) -> void:
	Game.world_drops = []
	for d in drops:
		var b: RigidBody3D = drop(parent, String(d.id), int(d.count), Vector3(float(d.x), float(d.y) + 0.05, float(d.z)), Vector3.ZERO)
		b.angular_velocity = Vector3.ZERO
		b.rotation = Vector3(0, randf() * TAU, 0)
		b.freeze = true
