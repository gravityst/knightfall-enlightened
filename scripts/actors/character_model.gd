class_name CharacterModel
extends Node3D
## Builds a dressed, animated human from the Universal Base Characters (head), the Fantasy
## outfit kit (clothing), hairstyles and rigid attachments (crown, weapons, shield,
## falcon, torch). Animations come from the shared Universal Animation Library.

const C := "res://assets/characters/"
const HAIR_M := ["Hair_Buzzed", "Hair_SimpleParted", "Hair_Long", ""]
const HAIR_F := ["Hair_Buns", "Hair_Long", "Hair_BuzzedFemale", "Hair_SimpleParted"]

static var _lib: AnimationLibrary
static var _mats := {}
static var _keep := {}

var skeleton: Skeleton3D
var anim: AnimationPlayer
var root_scene: Node3D
var meshes: Array[MeshInstance3D] = []
var torch_light: OmniLight3D
var current := ""
var _hood: MeshInstance3D
var _hand_r: BoneAttachment3D
var _hand_l: BoneAttachment3D
var sword_node: Node3D           # in the right fist (shown while fighting / in sword poses)
var sheath_node: Node3D          # the same sword worn at the left hip
var shield_node: Node3D
var torch_node: Node3D
var weapon_out := false
var armed := false               # fighting: the sword stays drawn whatever the animation

const SWORD := "res://assets/items/antique_estoc/antique_estoc.gltf"
static var grip_tilt := -0.6     # the blade leans back over the wrist: a raised guard in Sword_Idle
static var torch_tilt := -0.6
const SHIELD := "res://assets/items/kite_shield/kite_shield.gltf"
const TORCH := "res://assets/props/Torch_Metal.gltf"


static func library() -> AnimationLibrary:
	if _lib == null:
		var inst: Node = Assets.scene(C + "UAL1_Standard.glb").instantiate()
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		_lib = ap.get_animation_library("").duplicate(true)
		inst.free()
		for n in ["Walk", "Idle", "Jog_Fwd", "Sprint", "Idle_Talking", "Sitting_Idle", "Sitting_Talking", "Crouch_Idle", "Swim_Fwd", "Swim_Idle", "Dance", "Driving", "Idle_Torch", "Push", "Walk_Formal", "Fixing_Kneeling", "Sword_Idle", "Pistol_Aim_Neutral", "Spell_Simple_Idle"]:
			if _lib.has_animation(n):
				_lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return _lib


func build(p: Dictionary) -> void:
	var g := "Male" if p.get("gender", "m") == "m" else "Female"
	var outfit: String = p.get("outfit", "Peasant")
	root_scene = Assets.scene(C + "%s_%s.gltf" % [g, outfit]).instantiate()
	add_child(root_scene)
	skeleton = root_scene.find_children("*", "Skeleton3D", true, false)[0]
	# head / hands from the base body
	var base: Node = Assets.scene(C + "Superhero_%s_FullBody.gltf" % g).instantiate()
	for mi in base.find_children("*", "MeshInstance3D", true, false):
		# "SuperHero_Male" / "Superhero_Female": only the head (and a woman's hands) is kept
		_adopt(mi, String(mi.name).to_lower().begins_with("superhero"), g)
	base.free()
	# hair
	var hair: String = p.get("hair", "")
	if hair != "" and not p.get("hood", false):
		_adopt_scene(C + hair + ".gltf")
	if p.get("beard", false):
		_adopt_scene(C + "Hair_Beard.gltf")
	if outfit == "Peasant" and p.get("hood", false):
		_adopt_scene(C + "%s_Ranger_Head_Hood.gltf" % g)
	_adopt_scene(C + ("Eyebrows_Regular.gltf" if g == "Male" else "Eyebrows_Female.gltf"))
	# clothing materials & variation
	for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if not meshes.has(m):
			meshes.append(m)
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			if src is BaseMaterial3D:
				m.set_surface_override_material(s, _shader_mat(src, false))
		if String(m.name).contains("Hood"):
			_hood = m
			m.visible = bool(p.get("hood", false))
		if String(m.name).contains("Pauldron"):
			m.visible = bool(p.get("pauldron", true))
		Assets.set_iparam(m, "hue_shift", float(p.get("hue", 0.0)))
		Assets.set_iparam(m, "sat_mul", float(p.get("sat", 1.0)))
		Assets.set_iparam(m, "val_mul", float(p.get("val", 1.0)))
		Assets.set_iparam(m, "steel", float(p.get("steel", 0.0)))
		Assets.set_iparam(m, "skin_tint", p.get("skin", Color(1, 1, 1)))
		Assets.set_iparam(m, "dust", float(p.get("dust", 0.0)))
		Assets.set_iparam(m, "hair_color", p.get("hair_color", Color(0.3, 0.2, 0.12)))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# attachments
	if p.get("crown", false):
		_attach_model("Head", "res://assets/items/crown.glb", 0.2, "xz", Vector3(0, 1.79, -0.01), Vector3.ZERO, true)
	anim = AnimationPlayer.new()
	root_scene.add_child(anim)
	anim.add_animation_library("", library())
	# hand-held items sit in the fist (see _hold): the same fit works in every animation
	if p.get("sword", false):
		var sw: String = p.get("sword_model", SWORD)
		var sl := 1.0 if sw == SWORD else 0.92
		sword_node = _hold("r", sw, sl)
		sheath_node = _sheath(sw, sl)
	if p.get("shield", false):
		var sh: String = p.get("shield_model", SHIELD)
		shield_node = _strap_shield(sh, 0.92 if sh == SHIELD else 0.62)
	if p.get("falcon", false):
		_attach_posed("hand_l", "Idle_Torch", "res://assets/animals/hawk.glb", 0.34, "y", Basis(Vector3.UP, -0.4), Vector3(0, 0.05, 0.02))
	if p.get("torch", false):
		torch_node = _hold("l", TORCH, 0.55, true, torch_tilt)   # Idle_Torch raises the left fist
		var tg := Assets.grip(TORCH, true)
		var head: Vector3 = tg[0] + tg[1] * float(tg[3]) * 0.72   # just below the top of the torch head
		var fl := FireFX.flames(0.09, 0.4)
		fl.position = head
		torch_node.add_child(fl)
		torch_light = OmniLight3D.new()
		torch_light.light_color = Color(1.0, 0.6, 0.3)
		torch_light.light_energy = 1.6
		torch_light.omni_range = 9.0
		torch_light.position = head + tg[1] * 0.12
		torch_node.add_child(torch_light)
	draw_weapon(bool(p.get("drawn", false)))
	play("Idle", 0.0)


## Puts a hand-held item in the fist: the grip runs through the curled fingers, the blade (or
## torch head) leaves past the thumb and a crossguard lines up with the knuckles. Built from the
## hand's own knuckle positions, so it holds in every animation.
func _hold(side: String, path: String, length: float, shaft := false, tilt := INF) -> Node3D:
	var hand := skeleton.find_bone("hand_" + side)
	if hand < 0 or not ResourceLoader.exists(path):
		return null
	var k: Array[Vector3] = []
	for f in ["index", "middle", "ring", "pinky", "thumb"]:
		var b := skeleton.find_bone("%s_01_%s" % [f, side])
		k.append(skeleton.get_bone_rest(b).origin if b >= 0 else Vector3.ZERO)
	var knuckles := (k[0] + k[1] + k[2] + k[3]) * 0.25
	var palm := Vector3(signf(k[4].x), 0.0, 0.0)            # the thumb sits on the palm side
	var fingers := knuckles.normalized()
	var lean := grip_tilt if tilt == INF else tilt
	var along := ((k[0] - k[3]).normalized() + fingers * lean).normalized()   # out past the thumb
	var guard := (fingers - along * fingers.dot(along)).normalized()
	var g := Assets.grip(path, shaft)
	var gf: Vector3 = g[1]
	var gg: Vector3 = g[2]
	var model_frame := Basis(gf, gg, gf.cross(gg))
	var hand_frame := Basis(along, guard, along.cross(guard))
	var r := (hand_frame * model_frame.inverse()).scaled(Vector3.ONE * (length / float(g[3])))
	var at := knuckles * 0.8 + palm * 0.03
	return _mount(hand, path, Transform3D(r, at - r * (g[0] as Vector3)))


## The sword worn at the left hip: hilt forward at the belt, blade angled down and back.
func _sheath(path: String, length: float) -> Node3D:
	var bone := skeleton.find_bone("pelvis")
	if bone < 0:
		return null
	var g := Assets.grip(path)
	var gf: Vector3 = g[1]
	var gg: Vector3 = g[2]
	var down := Vector3(0.12, -0.8, -0.58).normalized()
	var guard := Vector3.RIGHT.cross(down).normalized()
	var r := (Basis(down, guard, down.cross(guard)) * Basis(gf, gg, gf.cross(gg)).inverse()).scaled(Vector3.ONE * (length / float(g[3])))
	var model := Transform3D(r, Vector3(0.19, 1.0, 0.13) - r * (g[0] as Vector3))
	return _mount(bone, path, skeleton.get_bone_global_rest(bone).affine_inverse() * model)


## A kite shield strapped to the left forearm: its face points out from the back of the arm and
## its point down when the fist is held thumb-up.
func _strap_shield(path: String, size: float) -> Node3D:
	var bone := skeleton.find_bone("lowerarm_l")
	var hand := skeleton.find_bone("hand_l")
	var thumb := skeleton.find_bone("thumb_01_l")
	if bone < 0 or hand < 0 or thumb < 0 or not ResourceLoader.exists(path):
		return null
	var wrist_rest := skeleton.get_bone_rest(hand)                     # hand in forearm space
	var thumb_x := signf(skeleton.get_bone_rest(thumb).origin.x)
	var up := (wrist_rest.basis * Vector3(0, 0, 1)).normalized()      # the thumb / index side
	var out := (wrist_rest.basis * Vector3(-thumb_x, 0, 0)).normalized()  # the back of the forearm
	var bb := Assets.merged_mesh(path).get_aabb()
	var thin := bb.get_shortest_axis_index()                 # the shield's face normal in the model
	var tall := bb.get_longest_axis_index()
	var model_frame := Basis()
	model_frame[tall] = up
	model_frame[thin] = out
	model_frame[3 - tall - thin] = (up.cross(out) if (tall + 1) % 3 == thin else out.cross(up))   # keep it right-handed
	var s := size / bb.size[tall]
	var r := model_frame.scaled(Vector3.ONE * s)
	var mid := wrist_rest.origin * 0.55 + out * 0.07
	return _mount(bone, path, Transform3D(r, mid - r * bb.get_center()))


func _mount(bone: int, path: String, xf: Transform3D) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = skeleton.get_bone_name(bone)
	skeleton.add_child(ba)
	var pivot := Node3D.new()
	pivot.transform = xf
	ba.add_child(pivot)
	var inst: Node = Assets.scene(path).instantiate()
	pivot.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return pivot


## Sword in the right fist, or back at the hip.
func draw_weapon(on: bool) -> void:
	weapon_out = on and sword_node != null
	if sword_node:
		sword_node.visible = on
	if sheath_node:
		sheath_node.visible = not on


func _sync_weapon(anim_name: String) -> void:
	if sword_node:
		var out := armed or anim_name.begins_with("Sword_")
		if out != weapon_out:
			draw_weapon(out)


static var _head_cache := {}

## The base body is only needed for the head (and a woman's hands): cut those triangles
## out once per body so the rest of the body is never skinned or rasterised.
static func _head_only(src: Mesh, skin: Skin, female: bool) -> Mesh:
	var key := "%d|%s" % [src.get_instance_id(), female]
	if _head_cache.has(key):
		return _head_cache[key]
	var keep := {}
	for i in skin.get_bind_count():
		var n := String(skin.get_bind_name(i))
		if n in ["Head", "neck_01"] or (female and (n.begins_with("hand") or n.contains("index") or n.contains("middle") or n.contains("pinky") or n.contains("ring") or n.contains("thumb"))):
			keep[i] = true
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var vcount: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := bones.size() / maxi(vcount, 1)
		var vkeep := PackedByteArray()
		vkeep.resize(vcount)
		for v in vcount:
			var w := 0.0
			for k in per:
				if keep.has(bones[v * per + k]):
					w += weights[v * per + k]
			vkeep[v] = 1 if w >= 0.5 else 0
		var nidx := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if vkeep[idx[t]] + vkeep[idx[t + 1]] + vkeep[idx[t + 2]] >= 2:
				nidx.append_array([idx[t], idx[t + 1], idx[t + 2]])
		arr[Mesh.ARRAY_INDEX] = nidx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, src.surface_get_format(s) & ~Mesh.ARRAY_FORMAT_INDEX | Mesh.ARRAY_FORMAT_INDEX)
		out.surface_set_material(s, src.surface_get_material(s))
	_head_cache[key] = out
	return out


func _adopt(mi: MeshInstance3D, is_body: bool, g: String) -> void:
	var skin: Skin = mi.skin
	if is_body and skin:
		mi.mesh = _head_only(mi.mesh, skin, g == "Female")
	mi.owner = null
	mi.get_parent().remove_child(mi)
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skin
	meshes.append(mi)
	if is_body:
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is BaseMaterial3D:
				var sm := _shader_mat(src, false)
				mi.set_surface_override_material(s, sm)
		Assets.set_iparam(mi, "skin_tint", Color(1, 1, 1))


func _adopt_scene(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var inst: Node = Assets.scene(path).instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		_adopt(mi, false, "")
	inst.free()


## Converts a kit material to the recolourable outfit shader (cached per source material).
func _shader_mat(src: BaseMaterial3D, body_mask: bool) -> ShaderMaterial:
	var key := "%s|%s|%d" % [src.resource_name, body_mask, src.get_instance_id() if body_mask else 0]
	if body_mask:
		key = src.resource_name + "|body|" + str(skeleton.get_bone_count())
	if _mats.has(key):
		return (_mats[key] as ShaderMaterial).duplicate() if Assets.compat else _mats[key]
	var sm := ShaderMaterial.new()
	sm.shader = Assets.instanced_shader("res://shaders/outfit.gdshader")
	sm.set_shader_parameter("albedo_tex", src.albedo_texture)
	if src.normal_enabled and src.normal_texture:
		sm.set_shader_parameter("use_normal", true)
		sm.set_shader_parameter("normal_tex", src.normal_texture)
	if src.roughness_texture:
		sm.set_shader_parameter("use_orm", true)
		sm.set_shader_parameter("orm_tex", src.roughness_texture)
	sm.set_shader_parameter("base_roughness", src.roughness)
	var n := src.resource_name
	sm.set_shader_parameter("is_skin", "Regular" in n or "Superhero" in n or "Eye" in n)
	sm.set_shader_parameter("is_hair", "Hair" in n)
	if body_mask:
		sm.set_shader_parameter("mask_body", true)
	_mats[key] = sm
	return sm.duplicate() if Assets.compat else sm


## Per-bind keep mask for the base body: only the head, neck and hands render.
func set_body_mask(mi: MeshInstance3D, female: bool) -> void:
	var keep := PackedFloat32Array()
	keep.resize(96)
	var skin: Skin = mi.skin
	for i in mini(skin.get_bind_count(), 96):
		var n := String(skin.get_bind_name(i))
		var k := n in ["Head", "neck_01"] or (female and (n.begins_with("hand") or n.contains("index") or n.contains("middle") or n.contains("pinky") or n.contains("ring") or n.contains("thumb")))
		keep[i] = 1.0 if k else 0.0
	for s in mi.mesh.get_surface_count():
		var m := mi.get_surface_override_material(s) as ShaderMaterial
		if m:
			m.set_shader_parameter("keep", keep)


func finalize(_female: bool) -> void:
	pass


## Attaches a rigid model to a bone. model_pos/model_rot are given in the character's
## rest pose (model space) unless local_offset is used (then expressed in bone space).
func _attach_model(bone: String, path: String, size: float, axis: String, model_pos: Vector3, model_rot: Vector3, rest_space: bool, local_offset := Vector3.ZERO, flip := false, upright := false) -> Node3D:
	var idx := skeleton.find_bone(bone)
	if idx < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	var holder := Assets.instance_sized(path, size, axis)
	var wrap := Node3D.new()
	wrap.add_child(holder)
	ba.add_child(wrap)
	var rest := skeleton.get_bone_global_rest(idx)
	if rest_space:
		var model := Transform3D(Basis.from_euler(model_rot), model_pos)
		wrap.transform = rest.affine_inverse() * model
	else:
		# orient the item in model space (blade forward / shield facing out), positioned at the bone
		var basis := Basis()
		if path.contains("estoc"):
			basis = Basis(Vector3.RIGHT, -PI * 0.5)   # blade along -Z in the model -> point it up the forearm line
		elif flip:
			basis = Basis(Vector3.UP, -PI * 0.5)
		var model := Transform3D(basis, rest.origin + rest.basis * local_offset)
		wrap.transform = rest.affine_inverse() * model
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return wrap


## Attaches a rigid item so that it has `model_basis` / offset (character model space) while
## the reference animation is playing; it then follows the bone through every other pose.
func _attach_posed(bone: String, ref_anim: String, path: String, size: float, axis: String, model_basis: Basis, offset: Vector3) -> Node3D:
	var idx := skeleton.find_bone(bone)
	if idx < 0:
		return null
	if anim.has_animation(ref_anim):
		anim.play(ref_anim, 0.0)
		anim.seek(0.25, true)
	var pose := skeleton.get_bone_global_pose(idx)
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	var holder := Assets.instance_sized(path, size, axis)
	var wrap := Node3D.new()
	wrap.add_child(holder)
	ba.add_child(wrap)
	wrap.transform = pose.affine_inverse() * Transform3D(model_basis, pose.origin + offset)
	return wrap


func play(name: String, blend := 0.25, speed := 1.0) -> void:
	if anim == null:
		return
	anim.speed_scale = speed
	if current == name:
		return
	current = name
	_sync_weapon(name)
	if anim.has_animation(name):
		anim.play(name, blend)


func play_once(name: String, blend := 0.12) -> void:
	if anim and anim.has_animation(name):
		current = name
		_sync_weapon(name)
		anim.speed_scale = 1.0
		anim.play(name, blend)


func freeze_end(name: String) -> void:
	if anim and anim.has_animation(name):
		current = name
		anim.play(name, 0.0)
		anim.seek(anim.get_animation(name).length - 0.02, true)
		anim.pause()


# ------------------------------------------------------------------ ragdoll
## Bone, the bone whose head sets its length ("" = fixed), capsule radius, mass, cone swing and twist (degrees).
const RAGDOLL := [
	["pelvis", "spine_02", 0.13, 11.0, 0.0, 0.0],
	["spine_02", "neck_01", 0.15, 14.0, 28.0, 18.0],
	["Head", "", 0.11, 4.5, 38.0, 30.0],
	["upperarm_l", "lowerarm_l", 0.055, 2.5, 75.0, 25.0],
	["lowerarm_l", "hand_l", 0.045, 1.6, 65.0, 10.0],
	["upperarm_r", "lowerarm_r", 0.055, 2.5, 75.0, 25.0],
	["lowerarm_r", "hand_r", 0.045, 1.6, 65.0, 10.0],
	["thigh_l", "calf_l", 0.075, 8.0, 55.0, 12.0],
	["calf_l", "foot_l", 0.06, 4.0, 65.0, 5.0],
	["thigh_r", "calf_r", 0.075, 8.0, 55.0, 12.0],
	["calf_r", "foot_r", 0.06, 4.0, 65.0, 5.0],
]
var _ragdoll: PhysicalBoneSimulator3D


## Goes limp: physical bones take over the skeleton from the current pose and `push` (world
## velocity) sends the body where the blow came from. Returns false if it can't (no skeleton).
func ragdoll(push: Vector3) -> bool:
	if skeleton == null or _ragdoll or skeleton.find_bone("pelvis") < 0:
		return false
	if anim:
		anim.pause()
	var sim := PhysicalBoneSimulator3D.new()
	skeleton.add_child(sim)
	for r in RAGDOLL:
		var bi := skeleton.find_bone(r[0])
		if bi < 0:
			continue
		var gb := skeleton.get_bone_global_rest(bi)
		var ci := skeleton.find_bone(r[1]) if r[1] != "" else -1
		var tip: Vector3 = (gb.affine_inverse() * skeleton.get_bone_global_rest(ci)).origin if ci >= 0 else Vector3(0, 0.22, 0)
		var half := tip.length() * 0.5
		var up := Vector3.UP if not Vector3.UP.cross(tip).is_zero_approx() else Vector3.BACK
		var body := Transform3D(Basis.looking_at(tip, up), Vector3.ZERO)
		body.origin = body.basis * Vector3(0, 0, -half)
		var pb := PhysicalBone3D.new()
		pb.bone_name = r[0]
		pb.body_offset = body
		pb.joint_offset = Transform3D(Basis(), Vector3(0, 0, half))
		pb.mass = r[3]
		pb.friction = 0.9
		pb.linear_damp = 0.15
		pb.angular_damp = 2.5
		pb.collision_layer = 64
		pb.collision_mask = 1
		if r[0] != "pelvis":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", r[4])
			pb.set("joint_constraints/twist_span", r[5])
			pb.set("joint_constraints/softness", 0.8)
			pb.set("joint_constraints/relaxation", 1.0)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = r[2]
		cap.height = maxf(half * 2.0, r[2] * 2.0 + 0.02)
		cs.shape = cap
		cs.transform.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
		pb.add_child(cs)
		sim.add_child(pb)
	sim.physical_bones_start_simulation()
	for pb in sim.get_children():
		var k := 1.0 if String((pb as PhysicalBone3D).bone_name) in ["spine_02", "Head"] else 0.6
		(pb as PhysicalBone3D).linear_velocity = push * k
	_ragdoll = sim
	return true


## Once the body has come to rest: keeps the pose, frees the physics, returns where it lies.
func settle_ragdoll() -> Vector3:
	if _ragdoll == null:
		return Vector3.INF
	var n := skeleton.get_bone_count()
	var bodies := {}
	for pb in _ragdoll.get_children():
		var b := pb as PhysicalBone3D
		bodies[skeleton.find_bone(b.bone_name)] = skeleton.global_transform.affine_inverse() * b.global_transform * b.body_offset.affine_inverse()
	var g := []
	g.resize(n)
	for i in n:       # parents come before children in the skeleton
		var par := skeleton.get_bone_parent(i)
		g[i] = bodies[i] if bodies.has(i) else ((g[par] as Transform3D) * skeleton.get_bone_pose(i) if par >= 0 else skeleton.get_bone_pose(i))
	var at := skeleton.global_transform * (g[skeleton.find_bone("pelvis")] as Transform3D).origin
	_ragdoll.physical_bones_stop_simulation()
	_ragdoll.active = false
	_ragdoll.queue_free()
	_ragdoll = null
	if anim:
		anim.active = false
	for i in bodies:
		var par := skeleton.get_bone_parent(i)
		var local: Transform3D = (g[par] as Transform3D).affine_inverse() * (g[i] as Transform3D) if par >= 0 else g[i]
		skeleton.set_bone_pose_position(i, local.origin)
		skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	return at


func set_shadows(on: bool) -> void:
	for m in meshes:
		if is_instance_valid(m):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
