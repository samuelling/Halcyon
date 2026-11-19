class_name Fx
extends Node3D
## Everything you hear and the small things you see: shots, steps, doors, the power; tracers, sparks,
## bullet holes, blood, supply crates. The game calls these hooks; none of it changes the play.

var game: Game
var view: View
var sfx := {}
var pool3d: Array = []
var pool2d: Array = []
var loops := {}
var decals: Array = []
var decal_i := 0
var tracers: Array = []
var puffs: Array = []
var puff_i := 0
var crate_packs := {}
var hole_tex: Texture2D
var blood_tex: Texture2D
var beat_t := 0.0
var muted := false

static func radial_tex(inner: Color, outer: Color, size := 64) -> GradientTexture2D:
	var g := Gradient.new(); g.set_color(0, inner); g.set_color(1, outer)
	var t := GradientTexture2D.new(); t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL; t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(1.0, 0.5); t.width = size; t.height = size
	return t

func setup(g: Game, v: View, quiet := false) -> void:
	game = g; view = v; muted = quiet
	var d := DirAccess.open("res://assets/sfx")
	if d:
		for f in d.get_files():
			if f.ends_with(".wav.import") or f.ends_with(".wav"):
				var nm := f.trim_suffix(".import").trim_suffix(".wav")
				if not sfx.has(nm): sfx[nm] = load("res://assets/sfx/" + nm + ".wav")
	if not muted:
		for i in 14:
			var p := AudioStreamPlayer3D.new(); p.unit_size = 6.0; p.max_distance = 70.0; p.attenuation_filter_cutoff_hz = 9000.0; add_child(p); pool3d.append(p)
		for i in 10:
			var p2 := AudioStreamPlayer.new(); add_child(p2); pool2d.append(p2)
		for nm in ["room", "sea", "drone"]:
			var st: AudioStreamWAV = sfx[nm]; st.loop_mode = AudioStreamWAV.LOOP_FORWARD; st.loop_begin = 0; st.loop_end = st.data.size() / 2
			var lp := AudioStreamPlayer.new(); lp.stream = st; lp.volume_db = -60.0; add_child(lp); lp.play(); loops[nm] = lp
	hole_tex = radial_tex(Color(0.02, 0.02, 0.02, 1.0), Color(0.05, 0.05, 0.05, 0.0), 32)
	blood_tex = radial_tex(Color(0.28, 0.0, 0.0, 0.95), Color(0.2, 0.0, 0.0, 0.0), 64)
	for i in 48:
		var dc := Decal.new(); dc.texture_albedo = hole_tex; dc.size = Vector3(0.09, 0.2, 0.09); dc.visible = false; dc.cull_mask = 1; add_child(dc); decals.append(dc)
	for i in 10:
		var cp := CPUParticles3D.new(); cp.emitting = false; cp.one_shot = true; cp.explosiveness = 0.95; cp.amount = 14; cp.lifetime = 0.5
		cp.direction = Vector3.UP; cp.spread = 50.0; cp.initial_velocity_min = 1.0; cp.initial_velocity_max = 3.5; cp.gravity = Vector3(0, -6, 0)
		cp.scale_amount_min = 0.5; cp.scale_amount_max = 1.2
		var qm := QuadMesh.new(); qm.size = Vector2(0.05, 0.05)
		var pm := StandardMaterial3D.new(); pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; pm.vertex_color_use_as_albedo = true
		pm.albedo_texture = radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 32); qm.material = pm; cp.mesh = qm
		var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 0.9)); gr.set_color(1, Color(1, 1, 1, 0)); cp.color_ramp = gr
		add_child(cp); puffs.append(cp)
	for k in [["ammo", "ammo_box"], ["aid", "medical_box"]]:
		crate_packs[k[0]] = load("res://assets/models/%s/%s.gltf" % [k[1], k[1]])

func play3d(name: String, pos: Vector3, db := 0.0, pitch := 1.0) -> void:
	if muted or not sfx.has(name): return
	for p: AudioStreamPlayer3D in pool3d:
		if not p.playing:
			p.stream = sfx[name]; p.global_position = pos; p.volume_db = db; p.pitch_scale = pitch; p.play(); return

func play2d(name: String, db := 0.0, pitch := 1.0) -> void:
	if muted or not sfx.has(name): return
	for p: AudioStreamPlayer in pool2d:
		if not p.playing:
			p.stream = sfx[name]; p.volume_db = db; p.pitch_scale = pitch; p.play(); return

func puff(pos: Vector3, n: Vector3, col: Color, amount := 14, speed := 3.0, life := 0.5) -> void:
	var cp: CPUParticles3D = puffs[puff_i]; puff_i = (puff_i + 1) % puffs.size()
	cp.global_position = pos; cp.direction = n; cp.color = col; cp.amount = amount; cp.initial_velocity_max = speed; cp.lifetime = life; cp.restart(); cp.emitting = true

func decal(pos: Vector3, n: Vector3, tex: Texture2D, size: float) -> void:
	var dc: Decal = decals[decal_i]; decal_i = (decal_i + 1) % decals.size()
	dc.texture_albedo = tex; dc.size = Vector3(size, 0.3, size); dc.visible = true
	var up := n.normalized(); var x := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	dc.global_transform = Transform3D(Basis(x, up, x.cross(up)), pos)

func tracer(a: Vector3, b: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new(); var bm := BoxMesh.new(); var len := a.distance_to(b)
	if len < 0.5: return
	bm.size = Vector3(0.012, 0.012, len); m.mesh = bm
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.albedo_color = col; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.material_override = mat; m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m); m.look_at_from_position((a + b) / 2.0, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	tracers.append([m, mat, 0.07, col])

# ------------------------------------------------------------------------- hooks
func shot(enclosed: float) -> void:
	play2d("shot" if enclosed > 0.5 else "shot_out", -3.0, 0.96 + randf() * 0.08)
	if view: puff(view.muzzle_pos(), -view.cam.global_transform.basis.z, Color(0.8, 0.8, 0.8, 0.25), 6, 1.2, 0.6)
func reload() -> void: play2d("reload", -6.0)
func empty() -> void: play2d("empty", -8.0)
func click() -> void: play2d("click", -10.0)
func pickup() -> void: play2d("pickup", -8.0)
func clear() -> void: play2d("clear", -8.0)
func rescued() -> void: play2d("rescued", -6.0)
func ambush() -> void: play2d("ambush", -5.0)
func death() -> void: play2d("death", -3.0)
func power(on: bool) -> void: play2d("power_up" if on else "power_down", -4.0)
func door(d: Dictionary) -> void:
	var m := Plan.door_mid(d); play3d("door", Vector3(m.x, d["L"] * Plan.LH + 1.2, m.y), 2.0)
func step(surface: String, run: bool) -> void:
	play2d("step_%s%d" % [surface, randi() % 3], -16.0 if not run else -12.0, 0.92 + randf() * 0.16)

func hit_actor(a: Actor, pos: Vector3, head: bool) -> void:
	play3d("hit", pos, 0.0, 1.2 if head else 1.0)
	puff(pos, (game.eye() - pos).normalized(), Color(0.5, 0.02, 0.02, 0.9), 12, 2.5, 0.45)
	if view: tracer(view.muzzle_pos(), pos, Color(1.0, 0.8, 0.5, 0.5))

func impact(hit, dir: Vector3) -> void:
	if hit == null:
		if view: tracer(view.muzzle_pos(), game.eye() + dir * 40.0, Color(1.0, 0.8, 0.5, 0.4))
		return
	var pos: Vector3 = hit["pos"]; var n: Vector3 = hit["n"]; var kind: String = hit["kind"]
	play3d("glass" if kind == "glass" else ("metal" if kind == "metal" else "impact"), pos, -2.0, 0.9 + randf() * 0.2)
	puff(pos + n * 0.03, n, Color(1.0, 0.85, 0.5, 1.0) if kind == "metal" else Color(0.75, 0.72, 0.68, 0.7), 10 if kind != "metal" else 16, 3.5 if kind == "metal" else 2.0, 0.4)
	if kind != "glass": decal(pos, n, hole_tex, 0.07)
	if view: tracer(view.muzzle_pos(), pos, Color(1.0, 0.8, 0.5, 0.45))

func kill(a: Actor) -> void:
	play3d("body", a.pos + Vector3(0, 0.5, 0), -2.0)
	decal(a.pos + Vector3(0, 0.02, 0), Vector3.UP, blood_tex, 0.9 + randf() * 0.5)

func enemy_fire(a: Actor, hit_me: bool) -> void:
	var from := a.pos + Vector3(0, 1.35, 0)
	play3d("shot_enemy", from, 3.0, 0.94 + randf() * 0.1)
	var e := game.eye()
	var miss := Vector3(randf() - 0.5, randf() * 0.4 - 0.1, randf() - 0.5).normalized() * (0.25 if hit_me else 0.7)
	tracer(from, e + miss + (e - from).normalized() * (0.0 if hit_me else 6.0), Color(1.0, 0.6, 0.3, 0.6))
	if hit_me: play2d("hurt", -4.0, 0.9 + randf() * 0.2)
	else: play2d("whiz", -10.0, 0.8 + randf() * 0.5)

func crate(kind: String, pos: Vector3, rot: float) -> Node3D:
	var root := Node3D.new(); root.position = pos; root.rotation.y = rot; add_child(root)
	var ps: PackedScene = crate_packs.get(kind)
	if ps:
		var c: Node3D = ps.instantiate(); var bb := Level.scene_aabb(c)
		var sc := 0.5 / maxf(0.01, maxf(bb.size.x, bb.size.z))
		c.scale = Vector3.ONE * sc; c.position.y = -bb.position.y * sc; root.add_child(c)
	var o := OmniLight3D.new(); o.light_color = Color(0.3, 1.0, 0.5) if kind == "aid" else Color(1.0, 0.75, 0.25); o.light_energy = 1.2; o.omni_range = 3.5; o.position.y = 0.7; root.add_child(o)
	return root

func update(dt: float) -> void:
	for n in range(tracers.size() - 1, -1, -1):
		var q: Array = tracers[n]; q[2] -= dt
		var c: Color = q[3]; (q[1] as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, c.a * maxf(0.0, q[2] / 0.07))
		if q[2] <= 0.0: (q[0] as Node).queue_free(); tracers.remove_at(n)
	if muted: return
	var p := game.player
	var out := Plan.outdoor_at(p.L, p.pos.x, p.pos.z)
	var near_sea := clampf((p.pos.z - 4.0) / 16.0, 0.0, 1.0)
	_fade(loops["sea"], (-6.0 if out else lerpf(-40.0, -22.0, near_sea)) if Plan.meta["name"] == "hotel" else -60.0, dt)   # the sea is the hotel's
	_fade(loops["room"], -40.0 if out or game.power < 0.5 else -20.0, dt)
	_fade(loops["drone"], -14.0 if game.power < 0.5 else -60.0, dt)
	if p.hp < 40.0:
		beat_t -= dt
		if beat_t <= 0.0: beat_t = 0.55 + p.hp / 100.0; play2d("heart", -6.0)

func _fade(pl: AudioStreamPlayer, db: float, dt: float) -> void: pl.volume_db = lerpf(pl.volume_db, db, minf(1.0, dt * 2.5))
