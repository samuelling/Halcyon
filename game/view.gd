class_name View
extends Node3D
## The first-person view: the camera, your own body (a full avatar, so there are arms on the pistol
## and legs when you look down), the pistol, its flash and the torch. The pistol is placed in view
## space; both hands are carried to it by two-bone IK and keep the grip they have in the aim clip.

var game: Game
var cam: Camera3D
var body := {}
var pistol: Node3D
var slide: Node3D
var slide_x := 0.0
var flash: OmniLight3D
var flash_quad: MeshInstance3D
var torch: SpotLight3D
var fingers := {}            # bone -> pose rotation in the grip
var r_hand := Basis.IDENTITY
var r_left := Basis.IDENTITY
var p_left := Vector3.ZERO
var flash_e := 0.0
var cur := ""
var retract := 0.0
var shake := 0.0
var show_body := true

func setup(g: Game) -> void:
	game = g
	cam = Camera3D.new(); cam.near = 0.04; cam.far = 4000.0; cam.fov = 72.0; add_child(cam); cam.make_current()
	body = Chars.make(Chars.PLAYER)
	var n: Node3D = body["node"]; add_child(n)
	var sk: Skeleton3D = body["sk"]; var ap: AnimationPlayer = body["ap"]; var B: Dictionary = body["bones"]
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false): mi.extra_cull_margin = 3.0
	# learn the grip from the aim clip: how each hand sits relative to the line of the forearm
	ap.play("a/Pistol_Aim_Neutral", 0.0); ap.seek(0.3, true); ap.advance(0.05)   # the clip has to be applied before the grip is read off it
	var hf := Chars.hand_frame(sk, B["RightHand"], B["RightLowerArm"])
	var wb := sk.global_transform.basis.orthonormalized()
	r_hand = hf.basis.inverse() * (wb * sk.get_bone_global_pose(B["RightHand"]).basis.orthonormalized())
	r_left = hf.basis.inverse() * (wb * sk.get_bone_global_pose(B["LeftHand"]).basis.orthonormalized())
	p_left = hf.affine_inverse() * Chars.bone_world(sk, B["LeftHand"])
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		if nm.contains("Thumb") or nm.contains("Index") or nm.contains("Middle") or nm.contains("Ring") or nm.contains("Little"): fingers[i] = sk.get_bone_pose_rotation(i)
	pistol = Chars.make_pistol(); add_child(pistol)
	slide = pistol.find_child("service_pistol_slide_a", true, false)
	if slide: slide_x = slide.position.x
	flash = OmniLight3D.new(); flash.light_color = Color(1.0, 0.76, 0.42); flash.omni_range = 11.0; flash.light_energy = 0.0; flash.visible = false
	flash.light_volumetric_fog_energy = 4.0; flash.shadow_enabled = true; add_child(flash)
	flash_quad = MeshInstance3D.new(); var q := QuadMesh.new(); q.size = Vector2(0.22, 0.22); flash_quad.mesh = q
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; fm.albedo_texture = Fx.radial_tex(Color(1, 0.95, 0.8, 1), Color(1, 0.5, 0.1, 0)); fm.albedo_color = Color(4, 3, 2, 1)
	flash_quad.material_override = fm; flash_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; flash_quad.visible = false; add_child(flash_quad)
	torch = SpotLight3D.new(); torch.light_color = Color(1.0, 0.95, 0.86); torch.spot_range = 34.0; torch.spot_angle = 24.0; torch.spot_angle_attenuation = 0.6; torch.spot_attenuation = 0.9
	torch.light_energy = 0.0; torch.visible = false; torch.shadow_enabled = true; torch.light_volumetric_fog_energy = 2.5; torch.light_specular = 1.0
	cam.add_child(torch); torch.position = Vector3(0.15, -0.16, -0.66)   # under the barrel, ahead of the hands

func fired() -> void:
	flash_e = 1.0; shake = 1.0

func _play(nm: String) -> void:
	if cur == nm: return
	cur = nm; (body["ap"] as AnimationPlayer).play(nm, 0.2)

func update(dt: float, inp: Game.Inp) -> void:
	var p := game.player; var H := game.human
	var sp := Vector2(p.vel.x, p.vel.z).length()
	# camera: head bob on the step, kick, a little roll with the strafe
	var ph0 := p.bob; p.bob += dt * sp * (2.3 if p.run else 2.6)
	if int(floor(p.bob / PI)) != int(floor(ph0 / PI)) and sp > 0.8 and game.fx: game.fx.step(game.surface(), p.run)
	var bob_a := minf(1.0, sp / 3.0) * (1.0 - 0.7 * p.ads) * (1.0 if H else 0.35)
	shake = maxf(0.0, shake - dt * 9.0)
	var hurt := maxf(0.0, 1.0 - (game.t - game.hurt_t) * 3.0)
	cam.position = Vector3(p.pos.x, p.pos.y + Game.EYE + absf(sin(p.bob)) * 0.035 * bob_a - 0.017 * bob_a, p.pos.z)
	cam.rotation = Vector3(p.pitch + p.kick, p.yaw + p.kick_yaw, sin(p.bob) * 0.006 * bob_a - p.sway.x * 0.02 + hurt * 0.03 * sin(game.t * 40.0))
	cam.fov = p.fov
	p.sway = p.sway.lerp(Vector2(inp.look_x, inp.look_y) * 6.0, minf(1.0, dt * 8.0))
	p.sway = p.sway.clampf(-0.6, 0.6)
	# the body: under the camera, legs walking with your speed
	var n: Node3D = body["node"]; var sk: Skeleton3D = body["sk"]; var ap: AnimationPlayer = body["ap"]; var B: Dictionary = body["bones"]
	var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	n.visible = show_body
	n.position = p.pos - f * 0.1; n.rotation.y = p.yaw + PI
	if sp > 3.6: _play("a/Jog_Fwd"); ap.speed_scale = clampf(sp / 3.6, 0.7, 1.5)
	elif sp > 0.3: _play("a/Walk"); ap.speed_scale = clampf(sp / 1.45, 0.6, 2.0)
	else: _play("a/Pistol_Idle"); ap.speed_scale = 1.0
	ap.advance(dt)
	sk.set_bone_pose_scale(B["Head"], Vector3.ONE * 0.001)
	for i: int in fingers: sk.set_bone_pose_rotation(i, fingers[i])
	# the pistol in view space: sway behind the look, bob with the step, kick on a shot, down for a
	# reload, up to the eye when aiming, pulled in when a wall is close
	var hitw = game.cast_world(-cam.global_transform.basis.z, 1.2)
	retract = lerpf(retract, clampf((0.95 - hitw["d"]) / 0.6, 0.0, 1.0) if hitw else 0.0, minf(1.0, dt * 10.0))
	var a := p.ads
	var bx := cos(p.bob) * 0.012 * bob_a; var by := -absf(sin(p.bob)) * 0.01 * bob_a
	var rl := 0.0
	if p.reload_t > 0.0: rl = sin(clampf((1.5 - p.reload_t) / 1.5, 0.0, 1.0) * PI)
	var run := 1.0 if p.run else 0.0
	var lp := Vector3(0.105 * (1.0 - a) + bx + p.sway.x * 0.04, -0.15 + 0.085 * a + by + p.sway.y * 0.03 - rl * 0.1 - run * 0.05 - retract * 0.06, -0.42 + 0.04 * a + p.kick * 1.6 + retract * 0.16)   # within easy reach: at full stretch the hands fall short of the grip
	# view-space pitch, then the turn that lays the barrel (+x) along the view, then the muzzle climb about the gun's own z
	var lb := Basis(Vector3.RIGHT, -p.sway.y * 0.3 - run * 0.3 - rl * 0.35 + retract * 0.9) * Basis(Vector3.UP, PI / 2.0 + p.sway.x * 0.3 + run * 0.4 - rl * 0.25 - 0.05 * (1.0 - a)) * Basis(Vector3.BACK, p.kick * 4.0)
	var ct := cam.global_transform
	pistol.global_transform = ct * Transform3D(lb, lp)
	if slide: slide.position.x = slide_x - minf(0.03, p.kick * 0.9)
	var pb := pistol.global_transform.basis.orthonormalized()
	var wrist := pistol.global_position - pb.x * 0.08 - pb.y * 0.035
	Chars.ik_arm(sk, B["RightUpperArm"], B["RightLowerArm"], B["RightHand"], wrist, ct.basis.x * 0.7 - Vector3.UP)
	Chars.set_bone_world_basis(sk, B["RightHand"], pb * r_hand)
	var lt := Transform3D(pb, wrist) * p_left
	if rl > 0.0: lt += (-Vector3.UP * 0.22 - ct.basis.x * 0.06 + ct.basis.z * 0.1) * rl   # the left hand goes for the magazine
	Chars.ik_arm(sk, B["LeftUpperArm"], B["LeftLowerArm"], B["LeftHand"], lt, -ct.basis.x * 0.6 - Vector3.UP)
	Chars.set_bone_world_basis(sk, B["LeftHand"], pb * r_left)
	# flash and torch
	flash_e = maxf(0.0, flash_e - dt * 16.0)
	var muzzle := pistol.global_position + pb.x * 0.17 + pb.y * 0.05
	flash.visible = flash_e > 0.01; flash.light_energy = 7.0 * flash_e; flash.global_position = muzzle + pb.x * 0.25
	flash_quad.visible = flash_e > 0.35; flash_quad.global_position = muzzle + pb.x * 0.06; flash_quad.scale = Vector3.ONE * (0.6 + 0.8 * flash_e)
	torch.visible = p.torch; torch.light_energy = 7.0 if p.torch else 0.0

func muzzle_pos() -> Vector3:
	var pb := pistol.global_transform.basis.orthonormalized()
	return pistol.global_position + pb.x * 0.17 + pb.y * 0.05
