class_name Game
extends Node3D
## Halcyon's play: the player, the pistol, the people in the corridors and the director that runs the
## hotel (rescues, encounters, the stairwells' hidden risk, the security doors, the power). All of it
## advances in step(dt, inp), so a bot can drive it tick by tick; every event the models need is
## written to self.log as it happens.

const EYE := 1.62
const RAD := 0.3

class Inp:
	var move_x := 0.0
	var move_z := 0.0
	var look_x := 0.0     # radians this tick (positive turns right)
	var look_y := 0.0
	var fire := false
	var ads := false
	var run := false
	var use := false
	var reload := false
	var torch_toggle := false

class Player:
	var pos := Vector3.ZERO
	var L := 0
	var yaw := PI
	var pitch := 0.0
	var vel := Vector3.ZERO
	var hp := 100.0
	var ammo := 12
	var reserve := 60
	var reload_t := -1.0
	var cool := 0.0
	var kick := 0.0
	var kick_yaw := 0.0
	var bloom := 0.0
	var ads := 0.0
	var run := false
	var bob := 0.0
	var sway := Vector2.ZERO
	var lives := 0
	var torch := false
	var ramp_from = null
	var last_cell := -1
	var trail: Array = []
	var dry := false
	var fov := 72.0

var level: Level
var visual := true
var human := false
var seed_ := 1
var rng := RandomNumberGenerator.new()
var serial := 0
var groups := 0
var group_rec := {}          # id -> {id, hostile, pose, n, call_t, resolved, first}
var t := 0.0
var player := Player.new()
var actors: Array[Actor] = []
var items: Array = []
var power := 1.0
var dark_until := 0.0
var dark_t0 := 0.0
var dark_L := 0
var pending_dark = null
var score := {"rescued": 0, "wrong": 0, "hostiles": 0}
var risk: Array = []
var next_enc := 3.0
var next_door := 8.0
var next_risk := 20.0
var next_obj_t := 0.0
var last_call_t := -99.0
var quiet_until := 0.0
var hurt_t := -9.0
var hit_mark_t := -9.0
var log := {}
var door_use := {}
var objective = null         # {room, name, guest, phase, t0, exit}
var n_obj := 0
var last_msg := [0.0, ""]
var aspect := 4.0 / 3.0
var people: Node3D
var fx = null
var hud = null
var view = null

func setup(lv: Level, vis: bool) -> void:
	level = lv; visual = vis
	people = Node3D.new(); people.name = "People"; add_child(people)

func reset(seed_value := 1) -> void:
	seed_ = seed_value
	for a in actors: a.dispose()
	for it in items:
		if it.get("node"): it["node"].queue_free()
	actors.clear(); items.clear(); group_rec.clear()
	rng.seed = seed_ * 7919 + 13
	t = 0.0; serial = 0; groups = 0
	player = Player.new(); player.pos = Vector3(Plan.cx(13) + 1.0, 0, Plan.cz(5)); player.yaw = PI
	power = 1.0; dark_until = 0.0; pending_dark = null
	score = {"rescued": 0, "wrong": 0, "hostiles": 0}
	risk.clear()
	for r in Plan.ramps: risk.append(0.1 + rng.randf() * 0.55)
	next_enc = 3.0; next_door = 8.0; next_risk = 20.0; next_obj_t = 0.0; last_call_t = -99.0; quiet_until = 0.0; n_obj = 0
	log = {"calls": [], "choices": [], "outcomes": [], "doors": [], "doorMet": [], "blackouts": [], "objectives": [], "resp": [], "shots": [], "kills": [], "deaths": [], "spawns": [], "pickups": [], "supplies": []}
	for d in Plan.doors: d["open"] = true; d["met_at"] = -1e9
	door_use.clear()
	objective = null; new_objective()
	if level: level.set_power(true)
	msg("FIND THE GUEST. WALK THEM OUT.")

func msg(s: String) -> void:
	last_msg = [t, s]
	if hud: hud.msg(s)

static func r2(v: float) -> float: return snappedf(v, 0.01)
static func r1(v: float) -> float: return snappedf(v, 0.1)

# ---------------------------------------------------------------------------------- objectives
func blocked_cell(L: int, i: int, k: int) -> bool:
	var x := Plan.cx(i); var z := Plan.cz(k)
	for o in Plan.obstacles:
		if o["L"] == L and Vector2(o["x"] - x, o["z"] - z).length() < o["r"] + 0.6: return true
	return false

func new_group(hostile: bool, pose: String) -> Dictionary:
	groups += 1
	var g := {"id": groups, "hostile": hostile, "pose": pose, "n": 0, "call_t": -1.0, "resolved": "", "first": -1}
	group_rec[groups] = g
	return g

## The guest to bring out waits upstairs, so every rescue climbs at least one flight and comes back
## down one; the way out alternates between the front doors and the far end of the pool terrace.
func new_objective() -> void:
	var cands: Array = []
	for r in Plan.rooms:
		var kd: String = r["kind"]
		if r["L"] >= 1 and (kd.begins_with("guest") or kd == "suite") and (objective == null or r["id"] != objective["room"]): cands.append(r)
	var r: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
	var rc: Array = r["rect"]
	var i := 0; var k := 0; var n := 0
	while true:
		i = rng.randi_range(rc[0], rc[2]); k = rng.randi_range(rc[1], rc[3]); n += 1
		if (Plan.walkable(r["L"], i, k) and not blocked_cell(r["L"], i, k)) or n > 50: break
	var grp := new_group(false, "hands")
	var g := Actor.new(self, "guest", r["L"], Plan.cx(i), Plan.cz(k), rng.randf() * TAU, "hands")
	g.objective = true; g.group = grp["id"]; grp["n"] = 1
	actors.append(g)
	n_obj += 1
	objective = {"room": r["id"], "name": r["name"], "guest": g, "phase": "find", "t0": t, "exit": "terrace" if (n_obj % 5) in [1, 2, 4] else "front"}
	log["objectives"].append([t, "new", r["id"], r["L"], i, k, g.id, objective["exit"]])

func extraction_at(L: int, x: float, z: float) -> bool:
	if L != 0 or objective == null: return false
	var i := Plan.ci(x); var k := Plan.ck(z)
	if objective["exit"] == "front": return k <= 0 and i >= 12 and i <= 15
	var r := Plan.room_at(0, i, k)
	return r >= 0 and Plan.rooms[r]["outdoor"] and k >= 25

func exit_nodes() -> Array:
	if objective and objective["exit"] == "front": return [Plan.node_id(0, 13, 0), Plan.node_id(0, 14, 0)]
	return [Plan.node_id(0, 12, 25), Plan.node_id(0, 15, 25)]

# ---------------------------------------------------------------------------------- the step
func step(dt: float, inp: Inp) -> void:
	t += dt
	var p := player
	step_player(dt, inp)
	step_weapon(dt, inp)
	step_actors(dt)
	step_director(dt, inp)
	track_calls()
	# the power comes back at the head of the stairs (or after 14 s)
	if power < 0.5:
		var on_ramp := Plan.ramp_at(p.L, Plan.ci(p.pos.x), Plan.ck(p.pos.z)) >= 0
		if t > dark_until or p.L != dark_L or (on_ramp and t - dark_t0 > 3.0 and absf(p.pos.y - dark_L * Plan.LH) > 1.6):
			power = 1.0; msg("POWER BACK"); log["blackouts"].append([t, "on"])
			if level: level.set_power(true)
			if fx: fx.power(true)
	if p.hp < 100.0 and t - hurt_t > 6.0: p.hp = minf(100.0, p.hp + 8.0 * dt)   # catch your breath
	var sp := Vector2(p.vel.x, p.vel.z).length()
	p.ads = lerpf(p.ads, 1.0 if inp.ads and p.reload_t < 0.0 else 0.0, minf(1.0, dt * 12.0))
	p.run = inp.run and sp > 3.5
	p.kick *= exp(-dt * 11.0); p.kick_yaw *= exp(-dt * 9.0); p.bloom *= exp(-dt * 3.5)
	p.fov = lerpf(p.fov, 72.0 - 18.0 * p.ads + (5.0 if p.run else 0.0), minf(1.0, dt * 10.0))
	if view: view.update(dt, inp)
	if fx: fx.update(dt)

func surface() -> String:
	var k := Plan.room_kind(player.L, Plan.ci(player.pos.x), Plan.ck(player.pos.z))
	if k in ["hall", "gallery", "guestA", "suite"]: return "carpet"
	return "wood" if k in ["terrace", "bar", "library", "ballroom", "guestB"] else "hard"

func step_player(dt: float, inp: Inp) -> void:
	var p := player
	p.yaw -= inp.look_x; p.pitch = clampf(p.pitch - inp.look_y, -1.3, 1.3)
	var sp := 5.2 if inp.run else 3.0
	var fx_ := -sin(p.yaw); var fz := -cos(p.yaw); var rx := cos(p.yaw); var rz := -sin(p.yaw)
	var mx := inp.move_z * fx_ + inp.move_x * rx; var mz := inp.move_z * fz + inp.move_x * rz
	var ml := maxf(1.0, sqrt(mx * mx + mz * mz))
	var tv := Vector3(mx / ml * sp, 0, mz / ml * sp)
	p.vel = p.vel.lerp(tv, minf(1.0, dt * 10.0))
	var old := p.pos
	var np := Plan.collide(p.L, Vector3(p.pos.x + p.vel.x * dt, p.pos.y, p.pos.z + p.vel.z * dt), RAD)
	var g := Plan.ground(p.L, np.x, np.z)
	if Plan.walkable(g[1], Plan.ci(np.x), Plan.ck(np.z)): p.pos = Vector3(np.x, g[0], np.z); p.L = g[1]
	p.vel = Vector3((p.pos.x - old.x) / dt, 0, (p.pos.z - old.z) / dt)
	if inp.torch_toggle:
		p.torch = not p.torch
		if fx: fx.click()

func step_weapon(dt: float, inp: Inp) -> void:
	var p := player
	p.cool -= dt
	if p.reload_t > 0.0:
		p.reload_t -= dt
		if p.reload_t <= 0.0:
			var n := mini(12 - p.ammo, p.reserve); p.ammo += n; p.reserve -= n; p.reload_t = -1.0
		return
	if (inp.reload and p.ammo < 12 and p.reserve > 0) or (p.ammo == 0 and p.reserve > 0 and inp.fire):
		p.reload_t = 1.5
		if fx: fx.reload()
		return
	if inp.fire and p.cool <= 0.0 and p.ammo == 0 and not p.dry:
		p.dry = true
		if fx: fx.empty()
	if not inp.fire: p.dry = false
	if inp.fire and p.cool <= 0.0 and p.ammo > 0:
		p.ammo -= 1; p.cool = 0.2
		var dir := cam_forward()   # the round leaves before the muzzle climbs
		p.kick += 0.035 * (1.0 - 0.4 * p.ads)
		if human:
			p.kick_yaw += (randf() - 0.5) * 0.012
			var spr := deg_to_rad(spread()); var rr := sqrt(randf()) * spr; var th := randf() * TAU
			dir = (cam_basis() * Vector3(cos(th) * rr, sin(th) * rr, -1.0)).normalized()
			p.bloom = minf(2.5, p.bloom + 0.6)
		var hit = hitscan(dir); var aim = aim_target()
		if fx:
			fx.shot(enclosed())
			if hit: fx.hit_actor(hit["a"], eye() + dir * hit["d"], hit["head"])
			else: fx.impact(cast_world(dir), dir)
		if view: view.fired()
		log["shots"].append([r2(t), hit["a"].id if hit else -1, r2(hit["d"]) if hit else -1, (2 if hit["head"] else 1) if hit else 0, aim[0].id if aim else -1, r2(aim[1]) if aim else -1])
		if aim: resolve_call(aim[0], "shoot")
		if hit: damage(hit["a"], 100.0 if hit["head"] else 40.0)

func spread() -> float:
	var p := player; var sp := Vector2(p.vel.x, p.vel.z).length()
	return (0.15 + 1.6 * (1.0 - p.ads) * (0.35 + minf(1.0, sp / 3.0)) + p.bloom * (1.0 - 0.6 * p.ads)) * (2.0 if p.run else 1.0)

func enclosed() -> float: return 0.25 if Plan.outdoor_at(player.L, player.pos.x, player.pos.z) else 1.0
func eye() -> Vector3: return Vector3(player.pos.x, player.pos.y + EYE, player.pos.z)
func cam_basis() -> Basis: return Basis.from_euler(Vector3(player.pitch + player.kick, player.yaw + player.kick_yaw, 0), EULER_ORDER_YXZ)
func cam_forward() -> Vector3: return -cam_basis().z

## Where a ray from the eye meets the building: a march through the plan (walls, floor, ceiling).
func cast_world(d: Vector3, maxd := 40.0):
	var p := player; var o := eye()
	var L := p.L; var i := Plan.ci(o.x); var k := Plan.ck(o.z)
	var y0 := L * Plan.LH; var yc := y0 + Plan.CEIL
	var s := 0.05
	while s < maxd:
		var x := o.x + d.x * s; var y := o.y + d.y * s; var z := o.z + d.z * s
		var ni := Plan.ci(x); var nk := Plan.ck(z)
		var rp := Plan.ramp_at(L, ni, nk)
		var fy: float = Plan.ramp_y(Plan.ramps[rp], x, z) if rp >= 0 else y0
		if y < fy: return {"pos": Vector3(x, fy + 0.005, z), "n": Vector3.UP, "kind": "floor", "d": s}
		var ku := Plan.kind_at(L + 1, ni, nk)
		var ceil_y := 1e9 if (ku == 2 or ku == 3 or Plan.outdoor_at(L, x, z)) else yc
		if y > ceil_y: return {"pos": Vector3(x, ceil_y - 0.005, z), "n": Vector3.DOWN, "kind": "wall", "d": s}
		if ni != i or nk != k:
			var sd := "E" if ni > i else ("W" if ni < i else ("N" if nk > k else "S"))
			var e := Plan.edge_at(L, i, k, sd)
			var blocks := false
			if e == Plan.WALL or e == Plan.GLASS: blocks = true
			elif e == Plan.SDOOR: blocks = not Plan.edge_door[Plan.ekey(L, i, k, sd)]["open"]
			elif e == Plan.DOOR: blocks = y > y0 + 2.3
			elif e == Plan.WINDOW: blocks = true
			elif e == Plan.RAIL: blocks = y < y0 + 1.0
			if blocks:
				var n := Vector3(-1, 0, 0) if sd == "E" else (Vector3(1, 0, 0) if sd == "W" else (Vector3(0, 0, -1) if sd == "N" else Vector3(0, 0, 1)))
				var hp := Vector3(x, y, z)
				if sd == "E": hp.x = Plan.X0 + (i + 1) * Plan.C - 0.08
				elif sd == "W": hp.x = Plan.X0 + i * Plan.C + 0.08
				elif sd == "N": hp.z = Plan.Z0 + (k + 1) * Plan.C - 0.08
				else: hp.z = Plan.Z0 + k * Plan.C + 0.08
				var glassy := e == Plan.GLASS or (e == Plan.WINDOW and y > y0 + 0.95 and y < y0 + 2.65)
				return {"pos": hp, "n": n, "kind": "glass" if glassy else ("metal" if e == Plan.SDOOR or e == Plan.RAIL else "wall"), "d": s}
			i = ni; k = nk
		s += 0.05
	return null

static func ray_vs_segment(o: Vector3, d: Vector3, a: Vector3, b: Vector3):
	var v := b - a; var r := o - a
	var e := v.dot(v); var f := v.dot(r); var c := d.dot(r); var bb := d.dot(v)
	var tt := 0.0; var s := 0.0
	if e < 1e-9: tt = -c
	else:
		var den := e - bb * bb
		tt = (bb * f - c * e) / den if den > 1e-9 else 0.0
		s = clampf((bb * tt + f) / e, 0.0, 1.0); tt = bb * s - c
	if tt <= 0.0: return null
	return [tt, (o + d * tt).distance_to(a + v * s)]

func hitscan(d: Vector3):
	var o := eye(); var best = null
	var aim = aim_target()
	for a in actors:
		if not a.alive or absf(a.pos.y - player.pos.y) > 2.5: continue
		if a.objective and (aim == null or aim[0] != a): continue   # the guest you came for keeps out of the line of fire
		for part: Array in [[Vector3(a.pos.x, a.pos.y + 0.2, a.pos.z), Vector3(a.pos.x, a.pos.y + 1.45, a.pos.z), 0.24, false], [a.head(), a.head(), 0.14, true]]:
			var q = ray_vs_segment(o, d, part[0], part[1])
			if q and q[1] < part[2] and (best == null or q[0] < best["d"]): best = {"a": a, "d": q[0], "head": part[3]}
	if best == null: return null
	var hp: Vector3 = o + d * best["d"]
	if not Plan.los(player.L, o.x, o.z, hp.x, hp.z): return null
	return best

func damage(a: Actor, n: float) -> void:
	a.hp -= n; a.hit_t = t
	if a.hostile and a.state != "fight": a.state = "fight"
	hit_mark_t = t
	if a.hp <= 0.0 and a.alive:
		a.alive = false; a.dead_t = 0.0
		if fx: fx.kill(a)
		log["kills"].append([t, a.id, 1 if a.hostile else 0, a.role])
		if a.hostile: score["hostiles"] += 1
		else:
			score["wrong"] += 1; msg("YOU SHOT THE GUEST" if a.objective else "NOT A GUNMAN")
		if a.objective and objective and objective["guest"] == a:
			log["objectives"].append([t, "failed", objective["room"]]); objective = null; next_obj_t = t + 3.0

func _walk(a: Actor, tx: float, tz: float, sp: float, dt: float) -> float:
	var ddx := tx - a.pos.x; var ddz := tz - a.pos.z; var dd := sqrt(ddx * ddx + ddz * ddz)
	if dd < 0.12: a.speed = 0.0; return dd
	var s := minf(sp, dd / dt)
	var np := Plan.collide(a.L, Vector3(a.pos.x + ddx / dd * s * dt, a.pos.y, a.pos.z + ddz / dd * s * dt), 0.28)
	var ty := atan2(-ddx, -ddz); a.yaw += wrapf(ty - a.yaw, -PI, PI) * minf(1.0, dt * 6.0)
	var g := Plan.ground(a.L, np.x, np.z)
	a.pos = Vector3(np.x, g[0], np.z); a.L = g[1]; a.speed = s
	return dd

func step_actors(dt: float) -> void:
	var p := player
	for a in actors:
		a.t += dt
		if not a.alive:
			a.dead_t += dt; a.speed = 0.0; a.sync(dt); continue
		var dx := p.pos.x - a.pos.x; var dz := p.pos.z - a.pos.z; var d := sqrt(dx * dx + dz * dz)
		var same := a.L == p.L and absf(a.pos.y - p.pos.y) < 2.5
		var sees := same and d < 26.0 and Plan.los(a.L, a.pos.x, a.pos.z, p.pos.x, p.pos.z)
		a.speed = 0.0
		if a.state == "approach" or a.state == "pass":
			var lead: Actor = a.leader if (a.leader and a.leader.alive and a.leader.state == a.state) else null
			var stop_d := 12.0 if a.hostile else 6.5
			if a.state == "approach" and ((sees and d < stop_d) or (a.leader and lead == null) or d < 4.0 or a.t > 16.0):
				a.state = ("alert" if sees else "idle") if a.hostile else "idle"; a.alert_t = t
			elif a.state == "pass" and (a.ri >= a.route.size() - 1 and lead == null and Vector2(a.route[-1][1] - a.pos.x, a.route[-1][2] - a.pos.z).length() < 0.6):
				a.state = "idle"
			else:
				var tx := 0.0; var tz := 0.0
				if lead:
					tx = lead.pos.x - sin(lead.yaw) * a.off.y + cos(lead.yaw) * a.off.x; tz = lead.pos.z - cos(lead.yaw) * a.off.y - sin(lead.yaw) * a.off.x
				else:
					var w: Array = a.route[mini(a.ri, a.route.size() - 1)]
					tx = w[1]; tz = w[2]
					if Vector2(tx - a.pos.x, tz - a.pos.z).length() < 0.5 and a.ri < a.route.size() - 1: a.ri += 1
				_walk(a, tx, tz, a.walk_sp * (1.25 if lead else 1.0), dt)
				a.sync(dt); continue
		if a.hostile:
			if sees and a.state == "idle": a.state = "alert"; a.alert_t = t
			if a.state == "alert" and t - a.alert_t > a.react: a.state = "fight"
			if a.state == "fight" or a.state == "alert": a.yaw = atan2(-dx, -dz)
			if a.state == "fight" and sees:
				a.fire_t -= dt
				if a.fire_t <= 0.0:
					a.fire_t = 0.7 + rng.randf() * 0.6
					var dark := 0.25 if power < 0.5 else 0.0
					var ph := maxf(0.08, 0.5 - d * 0.016 - dark - minf(0.2, p.vel.length() * 0.03))
					var hit_me := rng.randf() < ph
					if hit_me: p.hp -= 9.0; hurt_t = t
					a.muzzle_t = t; a.shoot_t = t
					if fx: fx.enemy_fire(a, hit_me)
		elif a.escort and objective and objective["guest"] == a:
			var tgt: Vector3 = p.trail[maxi(0, p.trail.size() - 3)] if p.trail.size() > 3 else p.pos
			var td := Vector2(tgt.x - a.pos.x, tgt.z - a.pos.z).length()
			if d > 2.2 and td > 0.4: _walk(a, tgt.x, tgt.z, 5.0 if d > 6.0 else 3.2, dt)
			if d > 14.0 and not Plan.los(a.L, a.pos.x, a.pos.z, p.pos.x, p.pos.z):
				var q: Vector3 = p.trail[maxi(0, p.trail.size() - 4)] if p.trail.size() > 0 else p.pos
				a.pos = q; a.L = p.L
		else:
			if sees and d < 12.0: a.yaw += wrapf(atan2(-dx, -dz) - a.yaw, -PI, PI) * minf(1.0, dt * 2.0)
			# once you have had your look (the call is over), bystanders walk on past you
			var g = group_rec.get(a.group)
			if not a.objective and g and g["resolved"] != "" and a.route.size() > 0 and a.state == "idle" and t - g["call_t"] > 3.5 and a.ri < a.route.size() - 1:
				a.state = "pass"; a.t = 0.0
		a.sync(dt)
	var cell := Plan.node_id(p.L, Plan.ci(p.pos.x), Plan.ck(p.pos.z))
	if cell != p.last_cell:
		p.trail.append(p.pos)
		if p.trail.size() > 60: p.trail.pop_front()
		p.last_cell = cell
	# tidy away people far behind
	var keep: Array[Actor] = []
	for a in actors:
		if a.objective and objective and objective["guest"] == a: keep.append(a); continue
		var far := Vector2(a.pos.x - p.pos.x, a.pos.z - p.pos.z).length() > 32.0 or a.L != p.L
		var old: bool = (not a.alive and a.dead_t > 25.0) or (far and a.t > 15.0) or (a.objective and (objective == null or objective["guest"] != a) and a.alive)
		if old: a.dispose()
		else: keep.append(a)
	actors = keep

# ---------------------------------------------------------------------------------- the director
func step_director(dt: float, inp: Inp) -> void:
	var p := player
	if p.hp <= 0.0:
		log["deaths"].append([t]); p.lives += 1
		p.hp = 100.0; p.ammo = 12; p.reserve = maxi(p.reserve, 36); p.pos = Vector3(Plan.cx(13 + rng.randi_range(0, 1)), 0, Plan.cz(4)); p.L = 0; p.yaw = PI; p.pitch = 0.0; p.trail.clear(); p.ramp_from = null
		for a in actors:
			if a.hostile: a.state = "idle"
		if objective and objective["phase"] == "escort": objective["guest"].escort = false; objective["guest"].pose = "hands"; objective["phase"] = "find"
		msg("YOU ARE DOWN. BACK IN THE LOBBY.")
		if fx: fx.death()
	var o = objective
	if o == null and t > next_obj_t: new_objective(); o = objective
	if o and o["phase"] == "find" and o["guest"].alive:
		var g: Actor = o["guest"]
		if g.L == p.L and Vector2(g.pos.x - p.pos.x, g.pos.z - p.pos.z).length() < 2.6 and inp.use:
			o["phase"] = "escort"; g.escort = true; g.pose = "none"; log["pickups"].append([t, o["room"], g.id])
			if fx: fx.pickup()
			msg("WITH YOU. OUT BY THE %s." % ("FRONT DOORS" if o["exit"] == "front" else "POOL TERRACE"))
			if rng.randf() < 0.85: pending_dark = t + 1.5 + rng.randf() * 2.0
	if o and o["phase"] == "escort" and extraction_at(p.L, p.pos.x, p.pos.z):
		score["rescued"] += 1; log["objectives"].append([t, "rescued", o["room"]]); msg("GUEST OUT SAFE")
		if fx: fx.rescued()
		var g2: Actor = o["guest"]; g2.dispose(); actors.erase(g2); objective = null; next_obj_t = t + 1.5
	# the power goes a moment after you find the guest; it comes back at the stairs
	if pending_dark != null and t > pending_dark and power > 0.5:
		pending_dark = null
		if Plan.ramp_at(p.L, Plan.ci(p.pos.x), Plan.ck(p.pos.z)) < 0 and p.L > 0:
			power = 0.0; dark_t0 = t; dark_L = p.L; dark_until = t + 22.0
			log["blackouts"].append([t, "off", dark_until]); msg("THE POWER IS OUT")
			if level: level.set_power(false)
			if fx: fx.power(false)
	# stairs: the choice, and what waits at the far end
	var rp := Plan.ramp_at(p.L, Plan.ci(p.pos.x), Plan.ck(p.pos.z))
	var near_stairs := rp >= 0
	if not near_stairs:
		for q in [[2, 0], [-2, 0], [0, 2], [0, -2]]:
			if Plan.ramp_at(p.L, Plan.ci(p.pos.x) + q[0], Plan.ck(p.pos.z) + q[1]) >= 0: near_stairs = true
	if rp >= 0 and p.ramp_from == null:
		p.ramp_from = {"ramp": rp, "t": t, "L": p.L}; log["choices"].append([t, rp, p.L, snappedf(risk[rp], 0.001)])
	if rp < 0 and p.ramp_from != null:
		var f: Dictionary = p.ramp_from; p.ramp_from = null
		if p.L != f["L"]:
			var amb: bool = rng.randf() < risk[f["ramp"]]
			log["outcomes"].append([t, f["ramp"], 1 if amb else 0, p.L])
			if amb: ambush()
			else: supply()
			next_enc = maxf(next_enc, 5.0 + rng.randf() * 3.0)
	# encounters: one group at a time, each a single call, calls at least 6 s apart
	next_enc -= dt
	if next_enc <= 0.0:
		var waiting := false
		for a in actors:
			if a.alive and not a.objective and a.state == "approach" and a.t < 9.0 and group_rec[a.group]["call_t"] < 0.0: waiting = true
		if waiting or rp >= 0 or t - last_call_t < 4.5: next_enc = 0.4
		elif spawn_group(): next_enc = 2.5 + rng.randf() * 3.5
		else: next_enc = 0.7
	next_door -= dt
	if next_door <= 0.0: toggle_door(); next_door = 8.0 + rng.randf() * 10.0
	next_risk -= dt
	if next_risk <= 0.0:
		next_risk = 20.0
		for n in risk.size(): risk[n] = clampf(risk[n] + (rng.randf() - 0.5) * 0.24, 0.05, 0.8)
	for it in items:
		if not it["taken"] and it["L"] == p.L and Vector2(it["x"] - p.pos.x, it["z"] - p.pos.z).length() < 1.2:
			it["taken"] = true
			if it.get("node"): it["node"].queue_free(); it["node"] = null
			if it["kind"] == "ammo": p.reserve += 24
			else: p.hp = minf(100.0, p.hp + 40.0)
			log["supplies"].append([t, it["kind"]]); msg("AMMUNITION" if it["kind"] == "ammo" else "FIRST AID")
			if fx: fx.pickup()
	for d in Plan.doors:
		if d["L"] != p.L: continue
		var m := Plan.door_mid(d)
		var dd := Vector2(m.x - p.pos.x, m.y - p.pos.z).length()
		if dd < 1.0: door_use[d["id"]] = t
		if not d["open"] and dd < 2.6 and t - d["met_at"] > 20.0: d["met_at"] = t; log["doorMet"].append([t, d["id"]])

func _spawn_member(g: Dictionary, role: String, L: int, x: float, z: float, yaw: float) -> Actor:
	var a := Actor.new(self, role, L, x, z, yaw, g["pose"])
	a.group = g["id"]; g["n"] += 1
	a.pos.y = Plan.ground(L, x, z)[0]
	actors.append(a)
	return a

## Someone steps into the corridor ahead: a group of 1-5 of one kind (all armed or none), starting
## out of sight 5-11 cells away and walking towards you. One group is one call.
func spawn_group() -> bool:
	var p := player
	var alive_n := 0
	for a in actors:
		if a.alive and not a.objective: alive_n += 1
	if alive_n > 8: return false
	var src := Plan.node_id(p.L, Plan.ci(p.pos.x), Plan.ck(p.pos.z))
	var dist := Plan.bfs(src); var fx_ := -sin(p.yaw); var fz := -cos(p.yaw)
	var cands: Array = []; var tot := 0.0
	for n: int in dist:
		var d: int = dist[n]
		if d < 4 or d > 11 or Plan.node_l(n) != p.L: continue
		var i := Plan.node_i(n); var k := Plan.node_k(n)
		if Plan.kind_at(p.L, i, k) != 1 or blocked_cell(p.L, i, k): continue
		var x := Plan.cx(i); var z := Plan.cz(k); var dx := x - p.pos.x; var dz := z - p.pos.z; var e := sqrt(dx * dx + dz * dz)
		if Plan.los(p.L, p.pos.x, p.pos.z, x, z): continue
		var crowded := false
		for a in actors:
			if a.alive and a.L == p.L and Vector2(a.pos.x - x, a.pos.z - z).length() < 4.0: crowded = true
		if crowded: continue
		var w := 1.0 + maxf(0.0, (dx * fx_ + dz * fz) / e) * 3.0
		cands.append([n, i, k, w]); tot += w
	if cands.is_empty(): return false
	var u := rng.randf() * tot; var pick: Array = cands[0]
	for c: Array in cands:
		u -= c[3]
		if u <= 0.0: pick = c; break
	var route := Plan.path(pick[0], src)
	if route.size() < 2: return false
	var pu := rng.randf()
	var hostile := rng.randf() < 0.45
	var num := (1 if pu < 0.4 else (2 if pu < 0.82 else 3)) if hostile else (1 if pu < 0.2 else (2 if pu < 0.5 else (3 if pu < 0.8 else (4 if pu < 0.93 else 5))))
	var pose: String = (("aim" if rng.randf() < 0.55 else "low") if hostile else ("phone" if rng.randf() < 0.5 else "hands"))
	var g := new_group(hostile, pose)
	var pts: Array = []
	for q in range(1, route.size()): pts.append([Plan.node_l(route[q]), Plan.cx(Plan.node_i(route[q])), Plan.cz(Plan.node_k(route[q]))])
	# bystanders walk on past where you stood
	var ids: Array = []; var leader: Actor = null
	for m in num:
		var off := Vector2((rng.randf() - 0.5) * 1.6, -0.8 - rng.randf() * 1.4) if m > 0 else Vector2.ZERO
		var role := "gunman" if hostile else ("guest" if rng.randf() < 0.6 else "staff")
		var a := _spawn_member(g, role, p.L, Plan.cx(pick[1]) + off.x * 0.5, Plan.cz(pick[2]) + off.y * 0.5, 0.0)
		a.state = "approach"; a.route = pts; a.ri = 0; a.off = off; a.leader = leader
		if m == 0: leader = a
		ids.append([a.id, 1 if hostile else 0, pose])
	log["spawns"].append([r2(t), p.L, pick[1], pick[2], g["id"], ids])
	return true

func _spot_ahead(dists: Array) -> Vector3:
	var p := player; var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw)); var r := Vector3(-f.z, 0, f.x)
	for d: float in dists:
		for side: float in [0.0, 0.8, -0.8, 1.6, -1.6]:
			var q := p.pos + f * d + r * side
			var c := Plan.collide(p.L, q, 0.3)
			if Plan.walkable(p.L, Plan.ci(c.x), Plan.ck(c.z)) and Plan.ramp_at(p.L, Plan.ci(c.x), Plan.ck(c.z)) < 0 and Plan.los(p.L, p.pos.x, p.pos.z, c.x, c.z, false): return c
	return p.pos + f * 0.8

func ambush() -> void:
	# whoever was on their way and has not been seen yet turns back: the landing is one call, not two
	for a in actors.duplicate():
		if a.alive and not a.objective and a.state == "approach" and group_rec[a.group]["call_t"] < 0.0: a.dispose(); actors.erase(a)
	var g := new_group(true, "aim")
	for m in 2:
		var q := _spot_ahead([5.5 + m * 1.8, 4.0, 3.0])
		var a := _spawn_member(g, "gunman", player.L, q.x + (rng.randf() - 0.5) * 0.6, q.z + (rng.randf() - 0.5) * 0.6, player.yaw + PI)
		a.state = "alert"; a.alert_t = t; a.react = 0.8 + rng.randf() * 0.5
	msg("AMBUSH")
	if fx: fx.ambush()

func supply() -> void:
	var q := _spot_ahead([2.4, 1.6, 3.2])
	var kind := "ammo" if rng.randf() < 0.5 else "aid"
	var it := {"kind": kind, "x": q.x, "z": q.z, "L": player.L, "taken": false, "node": null}
	if visual and fx: it["node"] = fx.crate(kind, Vector3(q.x, player.pos.y, q.z), rng.randf() * TAU)
	items.append(it)
	msg("CLEAR. SUPPLIES.")
	if fx: fx.clear()

func toggle_door() -> void:
	var p := player
	var closed := 0
	for d in Plan.doors:
		if not d["open"]: closed += 1
	var cands: Array = []; var tot := 0.0
	for d in Plan.doors:
		var dist: float = Vector2(Plan.cx(d["i"]) - p.pos.x, Plan.cz(d["k"]) - p.pos.z).length() + absf(d["L"] - p.L) * 8.0
		if dist < 5.0 or dist > 40.0: continue
		var used := 4.0 if t - float(door_use.get(d["id"], -1e9)) < 120.0 else 1.0
		var w: float = used * ((1.0 if closed < 9 else 0.0) if d["open"] else 1.2)
		if w > 0.0: cands.append([d, w]); tot += w
	if cands.is_empty(): return
	var u := rng.randf() * tot; var pick: Dictionary = cands[0][0]
	for c: Array in cands:
		u -= c[1]
		if u <= 0.0: pick = c[0]; break
	pick["open"] = not pick["open"]
	if not pick["open"] and not Plan.connected(): pick["open"] = true; return
	if fx: fx.door(pick)
	log["doors"].append([t, pick["id"], 1 if pick["open"] else 0])

# ---------------------------------------------------------------------------------- what is in view
## People in view: [x deg, y deg, distance, clear line, id, hostile, light, pose, objective, sx (x12), sy (x9), firing, group]
func visible() -> Array:
	var p := player; var out: Array = []
	var b := cam_basis(); var e := eye()
	var tan_y := tan(deg_to_rad(p.fov) / 2.0); var tan_x := tan_y * aspect
	for a in actors:
		if not a.alive: continue
		var rel := Vector3(a.pos.x, a.pos.y + 1.3, a.pos.z) - e
		var depth := -rel.dot(b.z)
		if depth < 0.3: continue
		var sx := rel.dot(b.x) / depth; var sy := rel.dot(b.y) / depth
		if absf(sx) > tan_x or absf(sy) > tan_y: continue
		var d := Vector2(a.pos.x - p.pos.x, a.pos.z - p.pos.z).length()
		var clear := 1 if absf(a.pos.y - p.pos.y) < 2.5 and Plan.los(p.L, p.pos.x, p.pos.z, a.pos.x, a.pos.z) else 0
		var light := light_on(a.L, a.pos, d)
		out.append([rad_to_deg(atan(sx)), rad_to_deg(atan(sy)), d, clear, a.id, 1 if a.hostile else 0, r2(light), a.pose, 1 if a.objective else 0, sx / tan_x * 12.0, sy / tan_y * 9.0, 1 if t - a.muzzle_t < 1.5 else 0, a.group])
	return out

func light_on(L: int, pos: Vector3, d: float) -> float:
	var ld := level.light_at(L, pos.x, pos.y + 1.3, pos.z) if level else Vector2(0.4, 0.0)
	return ld.x * (1.0 if power > 0.5 else 0.03) + ld.y + (0.6 * maxf(0.0, 1.0 - d / 20.0) if player.torch and d < 20.0 else 0.0)

func actor_by_id(id: int) -> Actor:
	for a in actors:
		if a.id == id: return a
	return null

## The person nearest the crosshair (within 6 deg) with a clear line, and the angle off.
func aim_target():
	var best = null
	for v: Array in visible():
		if v[3] == 0: continue
		var e := sqrt(v[0] * v[0] + v[1] * v[1])
		if e < 6.0 and (best == null or e < best[1]): best = [actor_by_id(v[4]), e]
	return best

## A call: the first moment anyone of a group is plainly in front of you (in view, clear line, under
## 22 m). It resolves as "shoot" (you fired at one of them) or "hold" after 2.5 s without firing.
func track_calls() -> void:
	for v: Array in visible():
		if v[3] == 0 or v[2] > 22.0 or absf(v[0]) > 30.0: continue
		var g = group_rec.get(v[12])
		if g == null: continue
		if g["call_t"] < 0.0:
			g["call_t"] = t; g["first"] = v[4]; last_call_t = t
			log["calls"].append([r2(t), v[4], v[5], v[7], r1(v[2]), v[6], g["id"], v[8], g["n"]])
	for gid: int in group_rec:
		var g: Dictionary = group_rec[gid]
		if g["call_t"] >= 0.0 and g["resolved"] == "" and t - g["call_t"] > 2.5: _resolve(g, "hold")

func _resolve(g: Dictionary, how: String) -> void:
	if g["call_t"] < 0.0 or g["resolved"] != "": return
	g["resolved"] = how
	log["resp"].append([r2(t), g["first"], how, r2(t - g["call_t"]), 1 if g["hostile"] else 0, g["id"]])

func resolve_call(a: Actor, how: String) -> void:
	var g = group_rec.get(a.group)
	if g: _resolve(g, how)
