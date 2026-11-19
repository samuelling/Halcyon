class_name View
extends Node3D
## The first-person view: the camera, your own body (a full avatar, so there are arms on the pistol
## and legs when you look down), the pistol, its flash and the torch. The pistol is placed in view
## space; both hands are carried to it by two-bone IK and take a grip built from the pistol's shape.

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
# Finger curl in degrees about each joint (proximal, intermediate, distal[, spread at the knuckle]); + closes the
# finger on the palm. The hand bones' axes (Godot humanoid profile): +Y towards the fingers, +Z out of the palm,
# +X towards the thumb on the right hand and away from it on the left.
const CURL := {
	# fingers: [curl about x, spread about z]; + spread moves a right finger away from the thumb and a left one towards it
	"Index":  {"R": [[4, -22], [46, 0], [30, 0]],   "L": [[46, 8], [70, 0], [44, 0]]},
	"Middle": {"R": [[58, -2], [82, 0], [52, 0]],   "L": [[52, 1], [74, 0], [44, 0]]},
	"Ring":   {"R": [[63, 7], [85, 0], [54, 0]],    "L": [[58, -6], [78, 0], [46, 0]]},
	"Little": {"R": [[70, 15], [88, 0], [56, 0]],   "L": [[64, -13], [80, 0], [48, 0]]},
	# thumbs: [across the palm towards the index, towards the palm]; the palm is -z on the right thumb, +z on the left
	"Thumb":  {"R": [[22, -38], [0, -22], [0, -12]], "L": [[34, -8], [0, 6], [0, 4]]},
}
# The grip in the pistol's frame (+x along the barrel, +y up, +z to the shooter's right): where the middle
# knuckle of each hand sits, and the direction of the grip (down its back strap, raked back).
const G_AXIS := Vector3(-0.33, -0.94, 0.0)
const R_KNUCKLE := Vector3(-0.004, -0.024, 0.027)
const L_KNUCKLE := Vector3(0.02, -0.018, -0.03)
var k_off_r := Vector3(-0.006, 0.095, 0.004)      # the middle knuckle in the hand bone's frame (read off the skeleton)
var k_off_l := Vector3(0.006, 0.095, 0.004)
var g_r := Basis.IDENTITY; var g_l := Basis.IDENTITY; var w_r := Vector3.ZERO; var w_l := Vector3.ZERO
var flash_e := 0.0
var cur := ""
var retract := 0.0
var shake := 0.0
var show_body := true
# the hold, in view space: hip (hx, hy, hz) and aimed (ay, az; x is 0 so the sights sit on the view axis);
# clav: how far the shoulders turn towards the hands; pole: how far the elbows point out; sdrop, sfwd: where the
# arm roots sit against a real body's (lower and further forward, out of the camera's sight). vm_<key>=<value>
# on the command line overrides one, vm_fov the lens.
var tune := {"hx": 0.085, "hy": -0.135, "hz": -0.46, "ay": -0.084, "az": -0.56, "clav": 0.3, "pole": 1.2, "sdrop": 0.08, "sfwd": 0.04, "arm": 0.88, "tilt": 0.33, "cant": 0.15}
var rig: Node3D               # holds the body and the pistol; squeezed towards the view axis so they are drawn as through a narrower lens
var VM_FOV_ADS := 78.0      # aiming zooms the world (72 to 54) but not the arms: their lens widens instead, as in shooters
var VM_FOV := 58.0          # the lens the arms and pistol are drawn with (the world's is 72): larger, less stretched hands

func setup(g: Game) -> void:
	game = g
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() == 2 and kv[0].begins_with("vm_") and tune.has(kv[0].substr(3)): tune[kv[0].substr(3)] = float(kv[1])
		if kv.size() == 2 and kv[0] == "vm_fov": VM_FOV = float(kv[1])
		if kv.size() == 2 and kv[0] == "vm_fov_ads": VM_FOV_ADS = float(kv[1])
	cam = Camera3D.new(); cam.near = 0.04; cam.far = 4000.0; cam.fov = 72.0; add_child(cam); cam.make_current()
	body = Chars.make(Chars.PLAYER)
	rig = Node3D.new(); add_child(rig)
	var n: Node3D = body["node"]; rig.add_child(n)
	var sk: Skeleton3D = body["sk"]; var ap: AnimationPlayer = body["ap"]; var B: Dictionary = body["bones"]
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false): mi.extra_cull_margin = 3.0
	# the grip, built from the pistol's own shape (see _grip): the shooting hand round the grip, the support hand over it
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		var side := "R" if nm.begins_with("Right") else ("L" if nm.begins_with("Left") else "")
		if side == "": continue
		for fg: String in CURL:
			if not nm.contains(fg): continue
			var seg := 0
			if fg == "Thumb": seg = 0 if nm.ends_with("Metacarpal") else (1 if nm.ends_with("Proximal") else 2)
			else: seg = 0 if nm.ends_with("Proximal") else (1 if nm.ends_with("Intermediate") else 2)
			var c: Array = CURL[fg][side][seg]   # [about x, about z] in degrees
			var q := Quaternion(Vector3.BACK, deg_to_rad(float(c[1]))) * Quaternion(Vector3.RIGHT, deg_to_rad(float(c[0])))
			fingers[i] = sk.get_bone_rest(i).basis.get_rotation_quaternion() * q
	for side in ["Right", "Left"]:
		var hg := sk.get_bone_global_rest(sk.find_bone(side + "Hand")); var kg := sk.get_bone_global_rest(sk.find_bone(side + "MiddleProximal"))
		var ko := hg.basis.orthonormalized().inverse() * (kg.origin - hg.origin)
		if side == "Right": k_off_r = ko
		else: k_off_l = ko
	_grip()
	pistol = Chars.make_pistol(); rig.add_child(pistol)
	# your own hands and pistol are seen close and at a slant: sharper texture filtering for them alone
	for root: Node in [n, pistol]:
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var m := mi.get_active_material(si)
				if m is BaseMaterial3D:
					var m2 := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
					m2.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					mi.set_surface_override_material(si, m2)
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

## Both hands in the pistol's frame: the shooting hand's fingers run forward across the right of the grip,
## square to it, palm against the grip, thumb side up; the support hand's palm on the left, its wrist low and
## the hand rising to the grip, fingers wrapped round the front of the shooting fingers, thumb forward. Wrist = knuckle minus the knuckle's offset in the hand.
func _grip() -> void:
	var g := G_AXIS.normalized()
	var fwd := (Vector3.RIGHT - g * g.x).normalized()     # square to the grip, pointing forward
	var yr := (fwd - Vector3.BACK * 0.18).normalized()
	var xr := yr.cross(Vector3.FORWARD).normalized(); g_r = Basis(xr, yr, xr.cross(yr).normalized())
	var yl := (fwd + Vector3.UP * 0.22 + Vector3.BACK * 0.1).normalized()
	var xl := yl.cross(Vector3.BACK).normalized(); g_l = Basis(xl, yl, xl.cross(yl).normalized())
	w_r = R_KNUCKLE - g_r * k_off_r
	w_l = L_KNUCKLE - g_l * k_off_l

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
	# the body: under the camera, legs walking with your speed (posed unsqueezed, squeezed at the end)
	rig.transform = Transform3D.IDENTITY
	var n: Node3D = body["node"]; var sk: Skeleton3D = body["sk"]; var ap: AnimationPlayer = body["ap"]; var B: Dictionary = body["bones"]
	var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	n.visible = show_body
	# the body eases back as you look down, so the open collar stays behind the eye
	n.position = p.pos - f * (0.02 + 0.17 * clampf((-p.pitch - 0.45) / 0.7, 0.0, 1.0)); n.rotation.y = p.yaw + PI
	if sp > 3.6: _play("a/Jog_Fwd"); ap.speed_scale = clampf(sp / 3.6, 0.7, 1.5)
	elif sp > 0.3: _play("a/Walk"); ap.speed_scale = clampf(sp / 1.45, 0.6, 2.0)
	else: _play("a/Pistol_Idle"); ap.speed_scale = 1.0
	ap.advance(dt)
	sk.set_bone_pose_scale(B["Head"], Vector3.ONE * 0.001); sk.set_bone_pose_scale(B["Neck"], Vector3.ONE * 0.001)   # no head or neck: from the eye only the collar shows
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
	var lp := Vector3(tune.hx * (1.0 - a) + bx + p.sway.x * 0.04, lerpf(tune.hy, tune.ay, a) + by + p.sway.y * 0.03 - rl * 0.1 - run * 0.05 - retract * 0.06, lerpf(tune.hz, tune.az, a) + p.kick * 1.6 + retract * 0.14)   # low and close: the eye looks down on the slide and the backs of the hands, the forearms leave by the bottom of the frame
	# view-space cant and pitch (at the hip the muzzle rides up and the top leans left, which turns the backs of the hands
	# to the eye; the grip's rake otherwise puts the wrists in front of them), then the turn that lays the barrel (+x)
	# along the view, then the muzzle climb about the gun's own z
	var lb := Basis(Vector3.BACK, tune.cant * (1.0 - a)) * Basis(Vector3.RIGHT, tune.tilt * (1.0 - a) - p.sway.y * 0.3 - run * 0.3 - rl * 0.35 + retract * 0.9) * Basis(Vector3.UP, PI / 2.0 + p.sway.x * 0.3 + run * 0.4 - rl * 0.25 - 0.05 * (1.0 - a)) * Basis(Vector3.BACK, p.kick * 4.0)
	var ct := cam.global_transform
	pistol.global_transform = ct * Transform3D(lb, lp)
	if slide: slide.position.x = slide_x - minf(0.03, p.kick * 0.9)
	var pb := pistol.global_transform.basis.orthonormalized()
	var pt := Transform3D(pb, pistol.global_position)
	var down := clampf((-p.pitch - 0.35) / 0.4, 0.0, 1.0)   # looking down at your own body: no cheats on its shape
	# the shoulders come forward a little towards the hands, as they do when a pistol is pushed out; the arm roots
	# sit lower than a real body's (the camera never sees them), so the forearms rise into the hands from below
	for sb: String in ["RightShoulder", "LeftShoulder"]:
		var bi: int = B[sb]; var gp := sk.get_bone_global_pose(sk.get_bone_parent(bi)).basis.orthonormalized()
		sk.set_bone_pose_position(bi, sk.get_bone_rest(bi).origin + gp.inverse() * Vector3(0.0, -tune.sdrop - 0.06 * a, tune.sfwd + 0.04 * a) * (1.0 - down))
	# the forearms a little slimmer (the jacket sleeves are what fills the bottom of the frame); the hands keep their size
	for side: String in ["Right", "Left"]:
		sk.set_bone_pose_scale(B[side + "LowerArm"], Vector3.ONE * tune.arm); sk.set_bone_pose_scale(B[side + "Hand"], Vector3.ONE / tune.arm)
	Chars.aim_bone(sk, B["RightShoulder"], B["RightUpperArm"], pt * w_r - Chars.bone_world(sk, B["RightShoulder"]), tune.clav + 0.25 * a)
	Chars.aim_bone(sk, B["LeftShoulder"], B["LeftUpperArm"], pt * w_l - Chars.bone_world(sk, B["LeftShoulder"]), tune.clav + 0.25 * a)
	Chars.ik_arm(sk, B["RightUpperArm"], B["RightLowerArm"], B["RightHand"], pt * w_r, ct.basis.x * (tune.pole + 1.0 * a) - Vector3.UP)
	Chars.untwist_forearm(sk, B["RightLowerArm"], B["RightHand"], pb * g_r)
	Chars.set_bone_world_basis(sk, B["RightHand"], pb * g_r)
	var lt := pt * w_l
	if rl > 0.0: lt += (-Vector3.UP * 0.22 - ct.basis.x * 0.06 + ct.basis.z * 0.1) * rl   # the left hand goes for the magazine
	Chars.ik_arm(sk, B["LeftUpperArm"], B["LeftLowerArm"], B["LeftHand"], lt, -ct.basis.x * (tune.pole + 1.0 * a) - Vector3.UP)
	Chars.untwist_forearm(sk, B["LeftLowerArm"], B["LeftHand"], pb * g_l)
	Chars.set_bone_world_basis(sk, B["LeftHand"], pb * g_l)
	# the lens: k = tan(world fov / 2) / tan(viewmodel fov / 2), applied across the view axis only, so depth (and
	# with it the light, fog and the order against the world) is untouched and the view centre stays put for the sights
	var k := lerpf(tan(deg_to_rad(p.fov) * 0.5) / tan(deg_to_rad(lerpf(VM_FOV, VM_FOV_ADS, a)) * 0.5), 1.0, down)
	rig.transform = ct * Transform3D(Basis.from_scale(Vector3(k, k, 1.0)), Vector3.ZERO) * ct.affine_inverse()
	pb = pistol.global_transform.basis.orthonormalized()
	# flash and torch
	flash_e = maxf(0.0, flash_e - dt * 16.0)
	var muzzle := pistol.global_position + pb.x * 0.17 + pb.y * 0.05
	flash.visible = flash_e > 0.01; flash.light_energy = 7.0 * flash_e; flash.global_position = muzzle + pb.x * 0.25
	flash_quad.visible = flash_e > 0.35; flash_quad.global_position = muzzle + pb.x * 0.06; flash_quad.scale = Vector3.ONE * (0.6 + 0.8 * flash_e)
	torch.visible = p.torch; torch.light_energy = 7.0 if p.torch else 0.0

func muzzle_pos() -> Vector3:
	var pb := pistol.global_transform.basis.orthonormalized()
	return pistol.global_position + pb.x * 0.17 + pb.y * 0.05
