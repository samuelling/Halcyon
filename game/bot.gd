class_name Bot
extends RefCounted
## The simulated player for the BOLDBLASTER harness, built from the same models the analysis fits:
##   routes   shortest believed paths; security doors seen shut are believed shut (map updating)
##   stairs   a softmax choice between flights by distance and a Rescorla-Wagner estimate of each
##            flight's ambush risk (the restless bandit)
##   calls    drift diffusion on what a group is holding and how well it can be seen, to shoot or hold
##   aim      a pursuit controller with motor noise; fires when on target
##   dark     torch on in a blackout, slower and noisier heading, walking back to the stairs it came by

const RW := 0.35
const LAMBDA := 9.0
const TEMP := 2.2

var g: Game
var seed_ := 1
var s := 0
var NN := 0
var zone := PackedInt32Array()
var nz := 0
var z_adj: Array = []
var door_zones := {}
var plan := {}
var bel := {}
var Q: Array = []
var avoid := {}
var blocked := PackedByteArray()
var wpt := {}
var ev := {}
var taken := {}
var inp := Game.Inp.new()
# state
var t := 0.0
var path: PackedInt32Array = PackedInt32Array()
var has_path := false
var pts: Array = []
var pts_for := -1
var path_serial := 0
var qi := 0
var goal_key := ""
var tgt := -1
var ddm := {}
var cool := 0.0
var glance := 0.0
var glance_t := 2.0
var stuck_t := 0.0
var last_pos = null
var lives := 0
var last_zone := -1
var home = null
var outb: Array = []
var trial = null
var last_l := 0
var hop_ramp := -1
var hop = null
var aim_noise := Vector2.ZERO
var pursue := 0.0
var replan_t := 0.0
var last_hurt := -9.0
var hp0 := 100.0
var dark := false
var lost_t = null
var last_fire := 0.0
var back_t := -1.0
var back_x := 0.0
var n_stuck := 0
var stuck_log: Array = []
var n_out := 0
var tgt_scr := [0.0, 0.0]
var tgt_dist := 10.0

func rnd() -> float:
	s = (s + 0x6D2B79F5) & 0xFFFFFFFF
	var x := s
	x = ((x ^ (x >> 15)) * (x | 1)) & 0xFFFFFFFF
	x ^= (x + (((x ^ (x >> 7)) * (x | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return float((x ^ (x >> 14)) & 0xFFFFFFFF) / 4294967296.0
func gauss() -> float: return sqrt(-2.0 * log(rnd() + 1e-12)) * cos(TAU * rnd())
static func wrap_a(a: float) -> float: return wrapf(a, -PI, PI)
static func r2(v: float) -> float: return snappedf(v, 0.01)
static func r1(v: float) -> float: return snappedf(v, 0.1)
func node_at(L: int, x: float, z: float) -> int: return Plan.node_id(L, Plan.ci(x), Plan.ck(z))

func _init(game: Game, seed_value: int) -> void:
	g = game; seed_ = seed_value; s = seed_value & 0xFFFFFFFF
	g.reset(seed_value)
	NN = Plan.NL * Plan.NX * Plan.NZ
	_zones()
	for r in Plan.ramps: Q.append(0.5)
	blocked.resize(NN); blocked.fill(0)
	for ob in Plan.obstacles:
		for i in range(Plan.ci(ob["x"] - ob["r"]), Plan.ci(ob["x"] + ob["r"]) + 1):
			for k in range(Plan.ck(ob["z"] - ob["r"]), Plan.ck(ob["z"] + ob["r"]) + 1):
				if Plan.in_grid(i, k): blocked[Plan.node_id(ob["L"], i, k)] = 1
	ev = {"kills": [], "bursts": [], "cuts": [], "deaths": [], "calls": [], "resp": [], "stairs": [], "outcomes": [], "doors": [], "stale": [], "junctions": [], "homing": [], "objectives": [], "pickups": [], "blackouts": [], "spawns": [], "shots": [], "plan": plan}

# zones: cells joined by open floor; zones are joined by doorways, security doors and flights
func _zones() -> void:
	zone.resize(NN); zone.fill(-1)
	for n in NN:
		var L := Plan.node_l(n); var i := Plan.node_i(n); var k := Plan.node_k(n)
		if not Plan.walkable(L, i, k) or zone[n] >= 0: continue
		var q: Array = [n]; zone[n] = nz; var h := 0
		while h < q.size():
			var a: int = q[h]; h += 1
			var al := Plan.node_l(a); var ai := Plan.node_i(a); var ak := Plan.node_k(a)
			for sd in Plan.SIDES:
				var jm := Plan.nb(ai, ak, sd)
				if not Plan.walkable(al, jm.x, jm.y) or Plan.edge_at(al, ai, ak, sd) != 0: continue
				var b := Plan.node_id(al, jm.x, jm.y)
				if zone[b] < 0: zone[b] = nz; q.append(b)
		nz += 1
	var z_edges := {}; var zx := PackedFloat64Array(); var zz := PackedFloat64Array(); var zc := PackedFloat64Array(); var zl := PackedInt32Array()
	zx.resize(nz); zz.resize(nz); zc.resize(nz); zl.resize(nz)
	for z in nz: z_adj.append({})
	for n in NN:
		if zone[n] < 0: continue
		var L := Plan.node_l(n); var i := Plan.node_i(n); var k := Plan.node_k(n); var za := zone[n]
		zx[za] += Plan.cx(i); zz[za] += Plan.cz(k); zc[za] += 1; zl[za] = L
		for sd in ["E", "N"]:
			var jm := Plan.nb(i, k, sd); var e := Plan.edge_at(L, i, k, sd)
			if not Plan.walkable(L, jm.x, jm.y) or (e != Plan.DOOR and e != Plan.SDOOR): continue
			var zb := zone[Plan.node_id(L, jm.x, jm.y)]
			if zb == za: continue
			z_adj[za][zb] = true; z_adj[zb][za] = true; z_edges["%d:%d" % [mini(za, zb), maxi(za, zb)]] = true
			if e == Plan.SDOOR: door_zones[Plan.edge_door[Plan.ekey(L, i, k, sd)]["id"]] = [za, zb]
		var rp := Plan.ramp_at(L, i, k)
		if rp >= 0 and L == Plan.ramps[rp]["L"]:
			var zb2 := zone[Plan.node_id(L + 1, i, k)]
			if zb2 >= 0 and zb2 != za:
				z_adj[za][zb2] = true; z_adj[zb2][za] = true; z_edges["%d:%d" % [mini(za, zb2), maxi(za, zb2)]] = true
	var zs: Array = []; var cells: Array = []
	for z in nz:
		zs.append([zl[z], r1(zx[z] / zc[z]), r1(zz[z] / zc[z]), int(zc[z])]); cells.append(z)
	var dl: Array = []
	for d in Plan.doors: dl.append([d["id"], d["L"], d["i"], d["k"], d["s"], door_zones.get(d["id"])])
	var rl: Array = []
	for n in Plan.ramps.size(): rl.append([n, Plan.ramps[n]["L"], Plan.ramps[n]["group"], Plan.ramps[n]["lane"]])
	plan = {"cells": cells, "edges": z_edges.keys(), "zones": zs, "doors": dl, "ramps": rl, "grid": {"x0": Plan.X0, "z0": Plan.Z0, "cell": Plan.C, "nx": Plan.NX, "nz": Plan.NZ, "nl": Plan.NL}}

# believed neighbours [node, cost]; mode -2 no flights, -1 any flight, n: flight n or flights not starting on floor lo
func nbrs(n: int, mode: int, lo: int, out: Array) -> void:
	out.clear()
	var L := Plan.node_l(n); var i := Plan.node_i(n); var k := Plan.node_k(n)
	for sd in Plan.SIDES:
		var jm := Plan.nb(i, k, sd)
		if not Plan.walkable(L, jm.x, jm.y): continue
		var e := Plan.edge_at(L, i, k, sd)
		var c := 1.0
		if e == Plan.SDOOR:
			var d: Dictionary = Plan.edge_door[Plan.ekey(L, i, k, sd)]
			if bel.has(d["id"]) and not bel[d["id"]]: continue
		elif e != 0 and e != Plan.DOOR: continue
		var b := Plan.node_id(L, jm.x, jm.y)
		if not Plan.node_ok(b): continue
		if blocked[b] == 1: c += 3.0
		if avoid.has(b) and t < avoid[b]: c += 6.0
		out.append(b); out.append(c)
	var rp := Plan.ramp_at(L, i, k)
	if rp >= 0 and (mode == -1 or (mode >= 0 and (rp == mode or Plan.ramps[rp]["L"] != lo))):
		var r: Dictionary = Plan.ramps[rp]
		var b2 := Plan.node_id(r["L"] + 1 if L == r["L"] else r["L"], i, k)
		if Plan.node_ok(b2): out.append(b2); out.append(0.01)

func wp(n: int) -> Vector2:
	if blocked[n] == 0: return Vector2(Plan.cx(Plan.node_i(n)), Plan.cz(Plan.node_k(n)))
	if wpt.has(n): return wpt[n]
	var L := Plan.node_l(n); var x0 := Plan.cx(Plan.node_i(n)); var z0 := Plan.cz(Plan.node_k(n))
	var best := Vector2(x0, z0); var bd := 1e9
	for a in range(-2, 3):
		for b in range(-2, 3):
			var x := x0 + a * 0.35; var z := z0 + b * 0.35; var hit := false
			for o in Plan.obstacles:
				if o["L"] == L and Vector2(o["x"] - x, o["z"] - z).length() < o["r"] * 0.8 + 0.4: hit = true; break
			if hit: continue
			var d := float(a * a + b * b)
			if d < bd: bd = d; best = Vector2(x, z)
	wpt[n] = best
	return best

var _dist := PackedFloat64Array()
var _prev := PackedInt32Array()
func dijkstra(src: int, mode: int, lo: int) -> void:
	_dist.resize(NN); _dist.fill(INF); _prev.resize(NN); _prev.fill(-1)
	_dist[src] = 0.0
	var hd: Array = [0.0]; var hn: Array = [src]; var nb: Array = []
	while hd.size() > 0:
		# pop the smallest (binary heap in two arrays)
		var d0: float = hd[0]; var a: int = hn[0]
		var ld: float = hd.pop_back(); var ln: int = hn.pop_back()
		if hd.size() > 0:
			hd[0] = ld; hn[0] = ln
			var i := 0; var sz := hd.size()
			while true:
				var l := 2 * i + 1; var r := l + 1; var m := i
				if l < sz and hd[l] < hd[m]: m = l
				if r < sz and hd[r] < hd[m]: m = r
				if m == i: break
				var td = hd[i]; hd[i] = hd[m]; hd[m] = td
				var tn = hn[i]; hn[i] = hn[m]; hn[m] = tn
				i = m
		if d0 > _dist[a]: continue
		nbrs(a, mode, lo, nb)
		for q in range(0, nb.size(), 2):
			var b: int = nb[q]; var nd: float = d0 + nb[q + 1]
			if nd < _dist[b]:
				_dist[b] = nd; _prev[b] = a
				hd.append(nd); hn.append(b)
				var j := hd.size() - 1
				while j > 0:
					var pj := (j - 1) >> 1
					if hd[pj] <= hd[j]: break
					var td2 = hd[j]; hd[j] = hd[pj]; hd[pj] = td2
					var tn2 = hn[j]; hn[j] = hn[pj]; hn[pj] = tn2
					j = pj

func trace(src: int, dst: int) -> PackedInt32Array:
	var out := PackedInt32Array([dst])
	while out[out.size() - 1] != src:
		var q := _prev[out[out.size() - 1]]
		if q < 0: return PackedInt32Array()
		out.append(q)
	out.reverse()
	return out

func set_path(p: PackedInt32Array) -> void:
	path = p; has_path = p.size() > 0; path_serial += 1

# ---------------------------------------------------------------- goals
func goal_nodes():
	var o = g.objective; var pl := g.player
	if o == null: return null
	if o["phase"] == "find":
		var gu: Actor = o["guest"]
		return {"key": "g%d" % gu.id, "nodes": [node_at(gu.L, gu.pos.x, gu.pos.z)]}
	if trial != null and home != null and home["L"] == pl.L: return {"key": "home", "nodes": [home["n"]]}
	return {"key": "out", "nodes": g.exit_nodes()}

func _best_of(nodes: Array) -> int:
	var best := -1
	for n: int in nodes:
		if best < 0 or _dist[n] < _dist[best]: best = n
	return best

## Route to the goal; a change of floor goes by a flight chosen by softmax over believed cost and risk.
func replan(reason: String) -> void:
	var pl := g.player; var gl = goal_nodes(); replan_t = t
	if gl == null: set_path(PackedInt32Array()); return
	var src := node_at(pl.L, pl.pos.x, pl.pos.z)
	var gL := Plan.node_l(gl["nodes"][0])
	goal_key = gl["key"]
	if gL == pl.L:
		dijkstra(src, -2, 0)
		var best := _best_of(gl["nodes"])
		if best < 0 or is_inf(_dist[best]):
			dijkstra(src, -1, 0); best = _best_of(gl["nodes"])
		set_path(trace(src, best) if best >= 0 and not is_inf(_dist[best]) else PackedInt32Array())
		return
	var lnext := pl.L + 1 if gL > pl.L else pl.L - 1; var lo := mini(pl.L, lnext)
	var opts: Array = []
	for n in Plan.ramps.size():
		if Plan.ramps[n]["L"] != lo: continue
		dijkstra(src, n, lo)
		var best := _best_of(gl["nodes"])
		if best >= 0 and not is_inf(_dist[best]): opts.append({"n": n, "cost": _dist[best], "path": trace(src, best)})
	if opts.is_empty(): set_path(PackedInt32Array()); return
	if hop != null and hop["L"] == pl.L and hop["gL"] == gL:
		for o in opts:
			if o["n"] == hop["n"]: set_path(o["path"]); return
	var c0 := INF
	for o in opts: c0 = minf(c0, o["cost"])
	var w: Array = []; var W := 0.0
	for o in opts:
		var x := exp(-((o["cost"] - c0) + LAMBDA * Q[o["n"]]) / TEMP); w.append(x); W += x
	var u := rnd() * W; var pick: Dictionary = opts[0]
	for m in opts.size():
		u -= w[m]
		if u <= 0.0: pick = opts[m]; break
	set_path(pick["path"]); hop_ramp = pick["n"]; hop = {"L": pl.L, "gL": gL, "n": pick["n"]}
	var on: Array = []; var oc: Array = []; var qq: Array = []
	for o in opts: on.append(o["n"]); oc.append(r1(o["cost"]))
	for v in Q: qq.append(snappedf(v, 0.001))
	ev["stairs"].append([r2(t), pick["n"], on, oc, pl.L, gL, qq, reason])

# ---------------------------------------------------------------- perception: doors
func crosses(a: int, b: int, d: Dictionary) -> bool:
	if Plan.node_l(a) != d["L"] or Plan.node_l(b) != d["L"]: return false
	var ai := Plan.node_i(a); var ak := Plan.node_k(a); var bi := Plan.node_i(b); var bk := Plan.node_k(b)
	var sd := "E" if bi > ai else ("W" if bi < ai else ("N" if bk > ak else "S"))
	return Plan.ekey(d["L"], ai, ak, sd) in d["keys"]

func see_doors() -> void:
	var pl := g.player
	for d in Plan.doors:
		if d["L"] != pl.L: continue
		var m := Plan.door_mid(d)
		var dd := Vector2(m.x - pl.pos.x, m.y - pl.pos.z).length()
		if dd > 14.0: continue
		var f := atan2(-(m.x - pl.pos.x), -(m.y - pl.pos.z))
		if absf(wrap_a(f - pl.yaw)) > 1.2 and dd > 2.5: continue
		var ex := m.x - (m.x - pl.pos.x) / dd * 0.3; var ez := m.y - (m.y - pl.pos.z) / dd * 0.3
		if not Plan.los(pl.L, pl.pos.x, pl.pos.z, ex, ez): continue
		var was: bool = bel.get(d["id"], true)
		if was != d["open"]:
			bel[d["id"]] = d["open"]
			if not d["open"]:
				var on_path := false
				if has_path:
					for q in range(maxi(1, 1), path.size()):
						if crosses(path[q - 1], path[q], d): on_path = true; break
				var dz: Array = door_zones.get(d["id"], [-1, -1])
				ev["stale"].append([r2(t), dz[0], dz[1], d["id"], 1 if on_path else 0, r1(dd)])
				if on_path: replan("door")

# ---------------------------------------------------------------- the step
func step(dt: float) -> Game.Inp:
	var pl := g.player; var o = g.objective
	inp = Game.Inp.new()
	if pl.lives != lives:
		lives = pl.lives; ev["deaths"].append([r2(t)]); ev["cuts"].append([r2(t), 0]); set_path(PackedInt32Array()); tgt = -1; ddm.clear(); end_trial(0); home = null; outb = []
	if pl.L != last_l:
		last_l = pl.L; home = {"L": pl.L, "x": pl.pos.x, "z": pl.pos.z, "n": node_at(pl.L, pl.pos.x, pl.pos.z), "id": hop_ramp}; outb = [[t, pl.pos.x, pl.pos.z]]
		if has_path: replan("floor")
	if home != null and outb.size() > 0 and t - outb[-1][0] > 0.4:
		outb.append([r2(t), r2(pl.pos.x), r2(pl.pos.z)])
		if outb.size() > 600: outb.pop_front()
	var dk := g.power < 0.5
	if dk != pl.torch: inp.torch_toggle = true
	if dk and not dark: start_trial()
	if not dk and dark: end_trial(2)
	dark = dk
	if trial != null and home != null and pl.L == home["L"] and Vector2(pl.pos.x - home["x"], pl.pos.z - home["z"]).length() < 2.0: end_trial(1)
	see_doors()
	# calls: drift diffusion per group in view
	var vis := g.visible()
	if pl.hp < hp0: last_hurt = t
	hp0 = pl.hp
	for v: Array in vis:
		if v[3] == 0 or v[2] > 24.0 or absf(v[0]) > 34.0: continue
		var gid: int = v[12]
		var D = ddm.get(gid)
		if D == null:
			D = {"x": 0.0, "t0": t, "ndt": 0.2 + rnd() * 0.15, "done": 0, "tick": -1.0}; ddm[gid] = D
		if D["done"] != 0 or t - D["t0"] < D["ndt"] or D["tick"] == t: continue
		D["tick"] = t   # one step of evidence per group per tick (its best-seen member)
		var pose: String = v[7]
		var sig := -1.0 if v[8] == 1 else (1.0 if pose == "aim" else (0.75 if pose == "low" else (-0.4 if pose == "phone" else -1.0)))
		var q := minf(1.0, v[6] / 0.55) * maxf(0.15, 1.0 - v[2] / 26.0) * (1.0 if absf(v[0]) < 12.0 else 0.6)
		D["x"] += 4.0 * sig * q * dt + 0.75 * sqrt(dt) * gauss() + (4.0 * dt if v[11] == 1 else 0.0) + (2.0 * dt if (t - last_hurt < 0.5 and v[8] == 0 and sig > 0.0) else 0.0)
		if D["x"] >= 1.0: D["done"] = 1
		elif D["x"] <= -1.0: D["done"] = -1
	if tgt < 0:
		var bd := 1e9
		for v: Array in vis:
			if v[3] == 1 and ddm.has(v[12]) and ddm[v[12]]["done"] == 1 and v[2] < bd: bd = v[2]; tgt = v[4]
		if tgt >= 0: aim_noise = Vector2(gauss() * 1.2, gauss() * 1.0); pursue = 0.0
	# aim and fire at the engaged target
	var tv = null
	if tgt >= 0:
		for v: Array in vis:
			if v[4] == tgt: tv = v
		if tv == null or tv[3] == 0:
			var a := g.actor_by_id(tgt)
			if lost_t == null: lost_t = t
			if a == null or not a.alive or t - lost_t > 1.5: tgt = -1; lost_t = null
			tv = null
		else: lost_t = null
	var fighting := false
	if tv != null:
		fighting = true; pursue += dt
		var kk := exp(-pursue * 2.2)
		var ex: float = tv[0] + aim_noise.x * kk + gauss() * 0.25; var ey: float = tv[1] - 0.2 + aim_noise.y * kk + gauss() * 0.2
		var gain := minf(1.0, dt * 9.0)
		inp.look_x = deg_to_rad(ex) * gain; inp.look_y = -deg_to_rad(ey) * gain
		cool -= dt
		var err := sqrt(ex * ex + ey * ey)
		var fouled := false
		for v: Array in vis:
			if v[4] != tv[4] and v[3] == 1 and v[2] < tv[2] - 0.3 and Vector2(v[0] - tv[0], v[1] - tv[1]).length() < 2.2 and (v[8] == 1 or (ddm.has(v[12]) and ddm[v[12]]["done"] == -1)): fouled = true
		if err < 1.6 and cool <= 0.0 and pl.ammo > 0 and pl.reload_t < 0.0 and not fouled:
			inp.fire = true; cool = 0.22 + rnd() * 0.12
			tgt_scr = [r2(tv[9]), r2(tv[10])]; tgt_dist = r1(tv[2])
		if pl.ammo == 0: inp.reload = true
		if inp.fire: last_fire = t
		elif pursue > 4.0 and t - last_fire > 4.0:
			ddm[tv[12]]["done"] = -2; tgt = -1
		inp.move_x = sin(t * 1.7 + seed_) * 0.5
	if not fighting and pl.ammo < 7 and pl.reserve > 0 and pl.reload_t < 0.0: inp.reload = true
	# the guest
	if o != null and o["phase"] == "find":
		var gu: Actor = o["guest"]
		if gu.alive and gu.L == pl.L and Vector2(gu.pos.x - pl.pos.x, gu.pos.z - pl.pos.z).length() < 2.4 and Plan.los(pl.L, pl.pos.x, pl.pos.z, gu.pos.x, gu.pos.z): inp.use = true
	# routes
	var gl = goal_nodes()
	if gl == null: set_path(PackedInt32Array())
	elif gl["key"] != goal_key or (not has_path and t - replan_t > 0.5) or t - replan_t > 6.0:
		replan("goal" if gl["key"] != goal_key else "refresh")
		if not has_path and not bel.is_empty():   # no way through the doors as remembered: go and look again
			bel.clear(); replan("forget")
	if not fighting and has_path:
		if pts_for != path_serial: build_pts()
		while qi < pts.size() - 1:
			var q: Dictionary = pts[qi]
			var hit: bool = q.get("ramp", false) if q["L"] != pl.L else Vector2(q["x"] - pl.pos.x, q["z"] - pl.pos.z).length() < q["r"]
			if q.get("pre", false) and q["L"] == pl.L:
				var rx: float = pl.pos.x - q["mx"]; var rz: float = pl.pos.z - q["mz"]
				var nrm: float = rx * q["ux"] + rz * q["uz"]; var lat: float = absf(rx * q["uz"] - rz * q["ux"])
				if lat < 0.3 and nrm > -0.9 and nrm < 0.1: hit = true
			if hit: qi += 1
			else: break
		var ti := qi
		if not pts[qi].get("door", false):
			for m in range(qi + 1, mini(pts.size(), qi + 6)):
				var q2: Dictionary = pts[m]
				if q2["L"] != pl.L: break
				if Plan.los(pl.L, pl.pos.x, pl.pos.z, q2["x"], q2["z"], false) and clear_line(pl, q2["x"], q2["z"]): ti = m
				else: break
				if q2.get("door", false): break
		var tq: Dictionary = pts[ti]
		var dx: float = tq["x"] - pl.pos.x; var dz: float = tq["z"] - pl.pos.z; var dist := sqrt(dx * dx + dz * dz)
		glance_t -= dt
		if glance_t <= 0.0: glance = gauss() * (0.25 if dk else 0.55); glance_t = 1.2 + rnd() * 2.5
		glance *= exp(-dt * 0.8)
		var head := atan2(-dx, -dz)
		var want := head + (0.0 if tq.get("door", false) else glance) + (gauss() * 0.04 if dk else 0.0)
		var err2 := wrap_a(want - pl.yaw)
		inp.look_x = -clampf(err2 * 4.0 * dt, -1.0, 1.0)
		inp.look_y = -(-0.03 - pl.pitch) * minf(1.0, dt * 3.0)
		var rel := wrap_a(head - pl.yaw); var sp := (0.65 if dk else 1.0) * minf(1.0, dist / 0.6 + 0.3)
		inp.move_z = cos(rel) * sp; inp.move_x = -sin(rel) * sp
		if qi >= pts.size() - 1 and dist < 0.4: set_path(PackedInt32Array())
	elif not fighting:
		inp.look_x = sin(t * 0.6 + seed_) * 0.02
	# stuck: no progress for 2 s while trying to move -> back off and replan
	if t < back_t: inp.move_z = -0.7; inp.move_x = back_x; stuck_t = t
	elif fighting or inp.move_z <= 0.3: stuck_t = t   # standing to fight or to look is not being stuck
	else:
		if last_pos == null or Vector2(pl.pos.x - last_pos.x, pl.pos.z - last_pos.y).length() > 0.6: last_pos = Vector2(pl.pos.x, pl.pos.z); stuck_t = t
		elif t - stuck_t > 2.0:
			stuck_t = t; back_t = t + 0.7; back_x = -0.8 if rnd() < 0.5 else 0.8
			avoid[node_at(pl.L, pl.pos.x, pl.pos.z)] = t + 20.0
			if has_path and qi < pts.size() and pts[qi].has("n"): avoid[pts[qi]["n"]] = t + 20.0
			stuck_log.append([r1(t), pl.L, r1(pl.pos.x), r1(pl.pos.z), Plan.room_kind(pl.L, Plan.ci(pl.pos.x), Plan.ck(pl.pos.z)), pts[qi] if qi < pts.size() else null])
			n_stuck += 1; replan("stuck")
	var zc := zone[node_at(pl.L, pl.pos.x, pl.pos.z)]
	if zc >= 0 and zc != last_zone:
		if z_adj[zc].size() >= 3 and gl != null and has_path: ev["junctions"].append([r2(t), zc, last_zone, z_adj[zc].keys(), pl.L, gl["key"], 0, zone[gl["nodes"][0]]])
		last_zone = zc
	return inp

func door_between(a: int, b: int) -> bool:
	var L := Plan.node_l(a)
	if L != Plan.node_l(b): return false
	var ai := Plan.node_i(a); var ak := Plan.node_k(a); var bi := Plan.node_i(b); var bk := Plan.node_k(b)
	return Plan.edge_at(L, ai, ak, "E" if bi > ai else ("W" if bi < ai else ("N" if bk > ak else "S"))) != 0

func build_pts() -> void:
	pts = []
	for m in path.size():
		var n := path[m]; var L := Plan.node_l(n); var w := wp(n)
		if m > 0 and Plan.node_l(path[m - 1]) != L:
			pts.append({"x": w.x, "z": w.y, "L": L, "r": 0.7, "ramp": true, "n": n}); continue
		if m > 0 and door_between(path[m - 1], n):
			var a := path[m - 1]
			var ax := Plan.cx(Plan.node_i(a)); var az := Plan.cz(Plan.node_k(a)); var bx := Plan.cx(Plan.node_i(n)); var bz := Plan.cz(Plan.node_k(n))
			var mx := (ax + bx) / 2.0; var mz := (az + bz) / 2.0; var ux := signf(bx - ax); var uz := signf(bz - az)
			pts.append({"x": mx - ux * 0.55, "z": mz - uz * 0.55, "L": L, "r": 0.22, "door": true, "pre": true, "mx": mx, "mz": mz, "ux": ux, "uz": uz, "n": n})
			pts.append({"x": mx + ux * 0.6, "z": mz + uz * 0.6, "L": L, "r": 0.35, "door": true, "n": n})
		pts.append({"x": w.x, "z": w.y, "L": L, "r": 0.7, "n": n})
	qi = 0; pts_for = path_serial

func clear_line(pl: Game.Player, x1: float, z1: float) -> bool:
	var dx := x1 - pl.pos.x; var dz := z1 - pl.pos.z; var l2 := maxf(1e-9, dx * dx + dz * dz)
	for ob in Plan.obstacles:
		if ob["L"] != pl.L: continue
		var tt := clampf(((ob["x"] - pl.pos.x) * dx + (ob["z"] - pl.pos.z) * dz) / l2, 0.0, 1.0)
		if Vector2(pl.pos.x + dx * tt - ob["x"], pl.pos.z + dz * tt - ob["z"]).length() < ob["r"] * 0.8 + 0.35: return false
	return true

# ---------------------------------------------------------------- homing trials (the walk back in the dark)
func start_trial() -> void:
	var pl := g.player
	if home == null or home["L"] != pl.L or g.objective == null or g.objective["phase"] != "escort": trial = null; return
	trial = [r2(t), r2(pl.pos.x), r2(pl.pos.z), home["id"], r2(home["x"]), r2(home["z"]), outb.duplicate(true)]
	replan("dark")

func end_trial(code: int) -> void:
	if trial == null: return
	var pl := g.player
	ev["homing"].append(trial + [r2(t), r2(pl.pos.x), r2(pl.pos.z), code, pl.L])
	trial = null; replan("lights")

# ---------------------------------------------------------------- the harness side
## One 50 ms tick: the bot decides, the game steps, shots and kills are booked.
func tick(dt: float) -> void:
	var i := step(dt)
	var kb: int = g.log["kills"].size(); var sb: int = g.log["shots"].size()
	g.step(dt, i)
	t += dt
	for m in range(sb, g.log["shots"].size()):
		var sh: Array = g.log["shots"][m]
		ev["bursts"].append([r2(t), sh[2] if sh[2] > 0 else tgt_dist, sh[5] if sh[5] >= 0 else 3, tgt_scr[0], tgt_scr[1], sh[4], 1 if (sh[1] >= 0 and sh[1] == sh[4]) else 0])
	for m in range(kb, g.log["kills"].size()):
		var kv: Array = g.log["kills"][m]
		ev["kills"].append([r2(t), tgt_scr[0], tgt_scr[1], kv[1], kv[2]])

func _take(key: String) -> void:
	var src: Array = g.log[key]; var n: int = taken.get(key, 0)
	while n < src.size():
		var q: Array = (src[n] as Array).duplicate(); q[0] = r2(q[0]); ev[key].append(q); n += 1
	taken[key] = n

## After the ticks of a frame: gather the game's logs, learn from the stairs, write the frame record.
func record() -> Dictionary:
	for k in ["calls", "resp", "outcomes", "doors", "objectives", "pickups", "blackouts", "spawns", "shots"]: _take(k)
	while n_out < g.log["outcomes"].size():
		var oc: Array = g.log["outcomes"][n_out]; Q[oc[1]] += RW * (oc[2] - Q[oc[1]]); n_out += 1
	var pl := g.player; var vis := g.visible()
	var vl: Array = []
	for v: Array in vis:
		if v[4] == tgt: tgt_scr = [r2(v[9]), r2(v[10])]; tgt_dist = r1(v[2])
		vl.append([r2(v[9]), r2(v[10]), r1(v[2]), v[3], v[4], v[5], v[6], v[7], v[8]])
	var n := node_at(pl.L, pl.pos.x, pl.pos.z)
	var ld := g.level.light_at(pl.L, pl.pos.x, pl.pos.y + 1.6, pl.pos.z) if g.level else Vector2.ZERO
	return {"t": r2(t), "tau": r2(t), "body": pl.lives, "x": r2(pl.pos.x), "z": r2(pl.pos.z), "y": r2(pl.pos.y), "L": pl.L,
		"yaw": snappedf(pl.yaw, 0.0001), "pitch": snappedf(pl.pitch, 0.0001), "speed": snappedf(Vector2(pl.vel.x, pl.vel.z).length(), 0.001),
		"vis": vl, "cell": n, "zone": zone[n], "room": Plan.room_at(pl.L, Plan.ci(pl.pos.x), Plan.ck(pl.pos.z)), "wall": r2(Plan.wall_dist(pl.L, pl.pos.x, pl.pos.z)),
		"dark": 1 if g.power < 0.5 else 0, "light": snappedf(ld.x * (1.0 if g.power > 0.5 else 0.03) + ld.y, 0.001), "torch": 1 if pl.torch else 0,
		"phase": g.objective["phase"] if g.objective else "none", "carry": 1 if (g.objective and g.objective["phase"] == "escort") else 0, "under": 0,
		"hp": int(round(pl.hp)), "ammo": pl.ammo, "tgt": tgt, "ramp": Plan.ramp_at(pl.L, Plan.ci(pl.pos.x), Plan.ck(pl.pos.z))}
