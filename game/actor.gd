class_name Actor
extends RefCounted
## Someone in the hotel: a gunman, a guest or a member of staff. What tells them apart is what is in
## the hand and how it is held, never the clothes (every role draws from the same pool of people).

var game: Game
var role := "guest"
var hostile := false
var id := 0
var group := 0
var L := 0
var pos := Vector3.ZERO
var yaw := 0.0
var hp := 60.0
var alive := true
var state := "idle"          # idle, approach, alert, fight, pass
var t := 0.0
var pose := "none"           # aim, low (gunmen); phone, hands (bystanders); none
var react := 1.0
var fire_t := 0.0
var escort := false
var objective := false
var leader: Actor = null
var off := Vector2.ZERO
var route: Array = []        # [[L, x, z]]
var ri := 0
var walk_sp := 1.5
var alert_t := 0.0
var dead_t := 0.0
var muzzle_t := -9.0
var hit_t := -9.0
var speed := 0.0             # for the animation
var avatar := 0
var seen_t := -1.0
var repath_t := 0.0
# visuals
var vis := {}
var node: Node3D
var item: Node3D
var cur := ""
var shoot_t := -9.0
var flash: OmniLight3D

func _init(g: Game, role_: String, L_: int, x: float, z: float, yaw_: float, pose_: String) -> void:
	game = g; role = role_; hostile = role_ == "gunman"; L = L_; yaw = yaw_; pose = pose_
	hp = 100.0 if hostile else 60.0
	g.serial += 1; id = g.serial
	pos = Vector3(x, L_ * Plan.LH, z)
	react = 0.6 + g.rng.randf() * 0.9
	walk_sp = 1.4 + g.rng.randf() * 0.4
	avatar = g.rng.randi_range(0, Chars.POOL.size() - 2)
	if g.visual: _build()

func _build() -> void:
	vis = Chars.make(avatar); node = vis["node"]
	game.people.add_child(node)
	(vis["ap"] as AnimationPlayer).speed_scale = 1.0
	if pose == "aim" or pose == "low": item = Chars.make_pistol()
	elif pose == "phone": item = Chars.make_phone()
	if item: game.people.add_child(item)
	if hostile:
		flash = OmniLight3D.new(); flash.light_color = Color(1.0, 0.75, 0.4); flash.omni_range = 9.0; flash.light_energy = 0.0; flash.visible = false
		flash.light_volumetric_fog_energy = 3.0; game.people.add_child(flash)
	sync(0.0)
	var ap: AnimationPlayer = vis["ap"]
	ap.advance(game.rng.randf() * 2.0)

func play(n: String, blend := 0.22) -> void:
	if cur == n: return
	cur = n
	var ap: AnimationPlayer = vis["ap"]
	if ap.has_animation(n): ap.play(n, blend)

func head() -> Vector3: return Vector3(pos.x, pos.y + 1.6, pos.z)

func dispose() -> void:
	if node: node.queue_free(); node = null
	if item: item.queue_free(); item = null
	if flash: flash.queue_free(); flash = null

static func _dir(f: Vector3, r: Vector3, a: float, b: float, c: float) -> Vector3:
	return (f * a + Vector3.UP * b + r * c).normalized()

func sync(dt: float) -> void:
	if node == null: return
	var ap: AnimationPlayer = vis["ap"]; var sk: Skeleton3D = vis["sk"]; var B: Dictionary = vis["bones"]
	node.position = pos; node.rotation.y = yaw + PI
	var moving := speed > 0.25
	var fighting := hostile and (state == "fight" or state == "alert")
	var p := "dead" if not alive else ("aim" if fighting else pose)
	# the clip underneath
	if not alive: play("a/Death01", 0.12)
	elif game.t - hit_t < 0.45 and not fighting: play("a/Hit_Chest", 0.08)
	elif moving:
		play("a/Jog_Fwd" if speed > 2.6 else "a/Walk")
		ap.speed_scale = clampf(speed / (3.6 if speed > 2.6 else 1.45), 0.6, 1.5)
	else:
		ap.speed_scale = 1.0
		if p == "aim": play("a/Pistol_Shoot" if game.t - shoot_t < 0.35 else "a/Pistol_Aim_Neutral", 0.1)
		elif p == "low": play("a/Pistol_Idle")
		elif p == "phone": play("b/Idle_TalkingPhone")
		else: play("a/Idle")
	ap.advance(dt)
	if not alive:
		if item: item.visible = dead_t < 0.4
		if flash: flash.visible = false
		return
	# the layer on top: arms
	var f := Vector3(-sin(yaw), 0, -cos(yaw)); var r := Vector3(-f.z, 0, f.x)
	if p == "hands":
		Chars.aim_bone(sk, B["RightUpperArm"], B["RightLowerArm"], _dir(f, r, 0.1, 0.8, 0.55)); Chars.aim_bone(sk, B["RightLowerArm"], B["RightHand"], _dir(f, r, 0.15, 1.0, 0.12))
		Chars.aim_bone(sk, B["LeftUpperArm"], B["LeftLowerArm"], _dir(f, r, 0.1, 0.8, -0.55)); Chars.aim_bone(sk, B["LeftLowerArm"], B["LeftHand"], _dir(f, r, 0.15, 1.0, -0.12))
	elif p == "aim" and (moving or fighting):
		var dd := _dir(f, r, 1.0, -0.12, 0.0)
		if fighting:
			var tg := game.player.pos + Vector3(0, 1.35, 0)
			dd = (tg - Chars.bone_world(sk, B["RightUpperArm"])).normalized()
		Chars.aim_bone(sk, B["RightUpperArm"], B["RightLowerArm"], (dd - r * 0.12).normalized()); Chars.aim_bone(sk, B["RightLowerArm"], B["RightHand"], dd)
		Chars.aim_bone(sk, B["LeftUpperArm"], B["LeftLowerArm"], (dd + r * 0.55 - Vector3.UP * 0.2).normalized())
		Chars.aim_bone(sk, B["LeftLowerArm"], B["LeftHand"], (Chars.bone_world(sk, B["RightHand"]) - Chars.bone_world(sk, B["LeftLowerArm"])).normalized())
	elif p == "phone" and moving:
		Chars.aim_bone(sk, B["RightUpperArm"], B["RightLowerArm"], _dir(f, r, 0.25, -1.0, 0.15)); Chars.aim_bone(sk, B["RightLowerArm"], B["RightHand"], _dir(f, r, 0.55, 0.55, -0.35))
	if item:
		item.visible = true
		var hf := Chars.hand_frame(sk, B["RightHand"], B["RightLowerArm"])
		if pose == "phone":
			item.global_transform = Transform3D(hf.basis.rotated(hf.basis.y, -0.6), hf.origin + hf.basis.x * 0.07 + hf.basis.y * 0.02)
		else:
			item.global_transform = Transform3D(hf.basis, hf.origin + hf.basis.x * 0.08 + hf.basis.y * 0.035)
			if flash:
				var e := maxf(0.0, 1.0 - (game.t - muzzle_t) * 14.0)
				flash.visible = e > 0.0; flash.light_energy = 6.0 * e
				flash.global_position = hf.origin + hf.basis.x * 0.3 + hf.basis.y * 0.06
