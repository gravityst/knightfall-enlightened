extends Node3D
## A crackling campfire: stone ring, flames, embers, warm flickering light and warmth.

var light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	var pit := Assets.instance_sized("res://assets/items/stone_fire_pit/stone_fire_pit.gltf", 1.3, "xz")
	add_child(pit)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.58, 0.26)
	light.light_energy = 3.0
	light.omni_range = 11.0
	light.shadow_enabled = not Assets.compat
	light.position.y = 0.7
	add_child(light)
	add_child(FireFX.flames(0.5, 1.0))
	if Game.world_ref:
		Game.world_ref.call("register_fire", self)


func _process(delta: float) -> void:
	_t += delta
	light.light_energy = 2.8 + sin(_t * 13.0) * 0.25 + sin(_t * 23.7) * 0.18 + sin(_t * 5.3) * 0.2


func get_interaction(_p) -> String:
	return "[E] Cook food over the fire" if _has_raw() else "Campfire (warmth)"


func _has_raw() -> bool:
	for id in Game.inventory:
		if Items.get_item(id).has("cookable"):
			return true
	return false


func interact(_p) -> void:
	var n := Game.cook_all()
	if n > 0:
		Game.notify.emit("You cook %d item%s over the fire." % [n, "s" if n > 1 else ""], "item")
