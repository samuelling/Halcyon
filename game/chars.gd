class_name Chars
## People: Microsoft Rocketbox avatars (MIT) on Godot's humanoid profile, moved by Quaternius's
## Universal Animation Library (CC0), plus the small procedural layer on top (aim, hands up, arm IK).

const POOL := [["Female_Adult_01", "f001"], ["Female_Adult_05", "f005"], ["Female_Adult_08", "f008"], ["Male_Adult_02", "m003"], ["Male_Adult_04", "m006"],
	["Male_Adult_06", "m011"], ["Male_Adult_11", "m001"], ["Business_Female_01", "f014"], ["Business_Male_02", "m008"], ["Business_Male_06", "m025"], ["Business_Male_01", "m005"]]
const PLAYER := 10
const DIR := "res://assets/avatars/"

static var libs := {}
static var mats := {}
static var packs := {}
static var pistol_pack: PackedScene

static func anim_lib(path: String) -> AnimationLibrary:
	if not libs.has(path):
		var n: Node = (load(path) as PackedScene).instantiate()
		var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
		libs[path] = ap.get_animation_library(&"")
		n.free()
	return libs[path]

## 3ds Max Biped parents the thighs to the spine and the clavicles to the neck: put them where the humanoid clips expect.
static func fix_hierarchy(sk: Skeleton3D) -> void:
	for pair: Array in [["LeftUpperLeg", "Hips"], ["RightUpperLeg", "Hips"], ["LeftShoulder", "UpperChest"], ["RightShoulder", "UpperChest"]]:
		var b := sk.find_bone(pair[0]); var p := sk.find_bone(pair[1])
		if b < 0 or p < 0 or sk.get_bone_parent(b) == p: continue
		var g := sk.get_bone_global_rest(b)
		sk.set_bone_parent(b, p)
		sk.set_bone_rest(b, sk.get_bone_global_rest(p).affine_inverse() * g)
	var bip := sk.find_bone("Bip01"); var hips := sk.find_bone("Hips")
	if bip >= 0 and hips >= 0:
		var gh := sk.get_bone_global_rest(hips)
		sk.set_bone_rest(bip, Transform3D.IDENTITY); sk.set_bone_rest(hips, gh)
	sk.reset_bone_poses()

static func _mat(code: String, part: String) -> StandardMaterial3D:
	var key := code + part
	if mats.has(key): return mats[key]
	var name: String = ""
	for q: Array in POOL:
		if q[1] == code: name = q[0]
	var d := DIR + name + "/" + code
	var m := StandardMaterial3D.new()
	if part == "opacity":
		m.albedo_texture = load(d + "_opacity_color.png"); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; m.alpha_scissor_threshold = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED; m.roughness = 0.6
	else:
		m.albedo_texture = load(d + "_" + part + "_color.jpg")
		m.normal_enabled = true; m.normal_texture = load(d + "_" + part + "_normal.jpg")
		m.roughness = 0.62 if part == "head" else 0.8
		if part == "head": m.subsurf_scatter_enabled = true; m.subsurf_scatter_strength = 0.25; m.subsurf_scatter_skin_mode = true
	m.metallic_specular = 0.4
	mats[key] = m
	return m

## A person: {node, sk, ap, bones{}}.
static func make(idx: int) -> Dictionary:
	var name: String = POOL[idx][0]; var code: String = POOL[idx][1]
	if not packs.has(name): packs[name] = load(DIR + name + "/" + name + ".fbx")
	var n: Node3D = (packs[name] as PackedScene).instantiate()
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	fix_hierarchy(sk)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(s)
			var nm := sm.resource_name if sm else ""
			mi.set_surface_override_material(s, _mat(code, "head" if nm.ends_with("head") else ("opacity" if nm.ends_with("opacity") else "body")))
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		mi.extra_cull_margin = 1.0
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	ap.add_animation_library(&"a", anim_lib("res://assets/anims/UAL1.glb")); ap.add_animation_library(&"b", anim_lib("res://assets/anims/UAL2.glb"))
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ap.playback_default_blend_time = 0.22
	var bones := {}
	for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"]:
		bones[b] = sk.find_bone(b)
	return {"node": n, "sk": sk, "ap": ap, "bones": bones}

static func make_pistol() -> Node3D:
	if pistol_pack == null: pistol_pack = load("res://assets/models/service_pistol/service_pistol.gltf")
	var src := pistol_pack.instantiate()
	var out := Node3D.new()
	for nm in ["service_pistol_pistol_a", "service_pistol_slide_a", "service_pistol_hammer_a", "service_pistol_trigger_a"]:
		var o := src.find_child(nm, true, false)
		if o == null: continue
		var xf := (o as Node3D).transform   # the parts' own transforms; the asset's root turns them
		o.owner = null; o.get_parent().remove_child(o); out.add_child(o); (o as Node3D).transform = xf
		if o is GeometryInstance3D: (o as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	src.free()
	return out

static func make_phone() -> MeshInstance3D:
	var m := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = Vector3(0.15, 0.012, 0.075); m.mesh = b
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.03, 0.03, 0.035); mat.roughness = 0.2; mat.metallic = 0.5
	mat.emission_enabled = true; mat.emission = Color(0.45, 0.65, 1.0); mat.emission_energy_multiplier = 0.9
	m.material_override = mat
	return m

static func bone_world(sk: Skeleton3D, b: int) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(b).origin

## Turn bone b so that its child c lies along a world direction.
static func aim_bone(sk: Skeleton3D, b: int, c: int, dir_world: Vector3, w := 1.0) -> void:
	var gb := sk.get_bone_global_pose(b); var gc := sk.get_bone_global_pose(c)
	var cur := (gc.origin - gb.origin).normalized()
	var d := (sk.global_transform.basis.orthonormalized().inverse() * dir_world).normalized()
	if cur.is_equal_approx(d) or cur.length_squared() < 0.5: return
	var q := Quaternion(cur, d) if cur.dot(d) > -0.9999 else Quaternion(Vector3.UP, PI)
	if w < 1.0: q = Quaternion.IDENTITY.slerp(q, w)
	var nb := Basis(q) * gb.basis.orthonormalized()
	var par := sk.get_bone_parent(b)
	var gp := sk.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(b, (gp.inverse() * nb).get_rotation_quaternion())

## Two-bone reach: put the hand at a world point with the elbow swung towards a pole direction.
static func ik_arm(sk: Skeleton3D, upper: int, lower: int, hand: int, target: Vector3, pole: Vector3) -> void:
	var inv := sk.global_transform.affine_inverse()
	var a := sk.get_bone_global_pose(upper).origin
	var l1 := sk.get_bone_global_pose(lower).origin.distance_to(a)
	var l2 := sk.get_bone_global_pose(hand).origin.distance_to(sk.get_bone_global_pose(lower).origin)
	var tg := inv * target
	var d := tg - a
	var dist := clampf(d.length(), 0.08, l1 + l2 - 0.002)
	var dir := d.normalized()
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var pl := inv.basis.orthonormalized() * pole
	var pp := pl - dir * pl.dot(dir)
	pp = pp.normalized() if pp.length_squared() > 1e-6 else Vector3.DOWN
	var elbow := a + dir * (ca * l1) + pp * (sqrt(maxf(0.0, 1.0 - ca * ca)) * l1)
	var wb := sk.global_transform.basis.orthonormalized()
	aim_bone(sk, upper, lower, wb * (elbow - a))
	var e2 := sk.get_bone_global_pose(lower).origin
	aim_bone(sk, lower, hand, wb * (a + dir * dist - e2))

static func set_bone_world_basis(sk: Skeleton3D, b: int, world_basis: Basis) -> void:
	var par := sk.get_bone_parent(b)
	var gp := sk.get_bone_global_pose(par).basis.orthonormalized()
	var local := (sk.global_transform.basis.orthonormalized() * gp).inverse() * world_basis
	sk.set_bone_pose_rotation(b, local.get_rotation_quaternion())

## The frame an item is held in: x along the forearm, y up.
static func hand_frame(sk: Skeleton3D, hand: int, forearm: int) -> Transform3D:
	var h := bone_world(sk, hand); var e := bone_world(sk, forearm)
	var x := (h - e).normalized()
	var y := (Vector3.UP - x * x.y).normalized() if absf(x.y) < 0.98 else Vector3.BACK
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), h)
