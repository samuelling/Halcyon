class_name Plan
## The hotel's plan: three floors on a 2 m grid, loaded from level/level.json (written by
## tools/export_level.mjs from web/src/plan.js). The same grid is the collision, the bot's
## pathfinding and the analysis, so all three agree.
##   x runs east (+i), z runs north (+k); floor L sits at y = L * LH.

const NONE := 0
const WALL := 1
const RAIL := 2
const DOOR := 3
const SDOOR := 4
const WINDOW := 5
const GLASS := 6
const ETYPE := {"wall": 1, "rail": 2, "door": 3, "sdoor": 4, "window": 5, "glass": 6}
const SIDES: Array[String] = ["E", "W", "N", "S"]

static var C := 2.0
static var NX := 28
static var NZ := 28
static var NL := 3
static var LH := 4.2
static var CEIL := 3.5
static var X0 := -28.0
static var Z0 := -20.0
static var NN := 0
static var kind: Array = []     # per level PackedInt32Array: 0 solid, 1 floor, 2 void, 3 ramp
static var room: Array = []
static var ramp: Array = []
static var edges := {}          # int key -> type
static var edge_door := {}      # int key -> door dictionary
static var doors: Array = []    # {id, L, i, k, s, keys(int), name, open}
static var ramps: Array = []
static var rooms: Array = []
static var obstacles: Array = [] # {L, x, z, r}
static var raw := {}            # the whole level.json

## What the director needs to know about a level beyond its plan. The hotel's values are the defaults.
static var meta := {}
const HOTEL_META := {
	"name": "hotel", "title": "THE HOTEL", "spawn": [0, 0.0, -9.0, PI], "respawn": [[0, -1.0, -11.0], [0, 1.0, -11.0]],
	"exits": {"front": {"label": "FRONT DOORS", "rect": [0, 12, 0, 15, 0], "nodes": [[0, 13, 0], [0, 14, 0]]},
		"terrace": {"label": "POOL TERRACE", "rect": [0, 4, 25, 23, 27], "nodes": [[0, 12, 25], [0, 15, 25]]}},
	"exit_cycle": ["front", "terrace", "terrace", "front", "terrace"],
	"objective_kinds": ["guestA", "guestB", "suite"], "objective_min_L": 1,
	"blackout_p": 0.85, "blackout_min_L": 1, "spawn_far": 0.0, "spawn_cells": 10, "stop_hostile": 12.0, "sky": "dusk"}

static func load_level(path := "res://level/level.json") -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	return load_dict(JSON.parse_string(txt))

## A level as a dictionary: the hotel's exported JSON, or one built by LevelGen (which adds "meta" and has no "surfaces").
static func load_dict(d: Dictionary) -> Dictionary:
	raw = d
	meta = HOTEL_META.duplicate(true)
	for k in (d.get("meta", {}) as Dictionary): meta[k] = d["meta"][k]
	var p: Dictionary = raw["plan"]
	C = p["C"]; NX = int(p["NX"]); NZ = int(p["NZ"]); NL = int(p["NL"]); LH = p["LH"]; CEIL = p["CEIL"]; X0 = p["X0"]; Z0 = p["Z0"]
	NN = NL * NX * NZ
	kind.clear(); room.clear(); ramp.clear(); edges.clear(); edge_door.clear(); doors.clear()
	for L in NL:
		kind.append(PackedInt32Array(p["kind"][L])); room.append(PackedInt32Array(p["room"][L])); ramp.append(PackedInt32Array(p["ramp"][L]))
	for e in p["edges"]:
		edges[_key_str(e[0]) if e[0] is String else int(e[0])] = ETYPE[e[1]] if e[1] is String else int(e[1])
	for dr in p["doors"]:
		var dd := {"id": int(dr["id"]), "L": int(dr["L"]), "i": int(dr["i"]), "k": int(dr["k"]), "s": dr["s"], "name": dr["name"], "open": true, "keys": [], "met_at": -1e9}
		for ks in dr["keys"]:
			var kk: int = _key_str(ks) if ks is String else int(ks)
			dd["keys"].append(kk); edge_door[kk] = dd
		doors.append(dd)
	ramps = p["ramps"]
	for r in ramps:
		r["L"] = int(r["L"]); r["id"] = int(r["id"]); r["dir"] = int(r["dir"])
		var ln: Array = r["lane"]; r["lane"] = [int(ln[0]), int(ln[1]), int(ln[2]), int(ln[3])]
		r["along_k"] = (r["axis"] as String)[1] == "k"
	rooms = p["rooms"]
	for r in rooms:
		r["L"] = int(r["L"]); r["id"] = int(r["id"]); r["outdoor"] = r.get("outdoor", false)
		var rc: Array = r["rect"]; r["rect"] = [int(rc[0]), int(rc[1]), int(rc[2]), int(rc[3])]
	obstacles.clear()
	for o in raw["obstacles"]:
		obstacles.append({"L": int(o["L"]), "x": float(o["x"]), "z": float(o["z"]), "r": float(o["r"])})
	return raw

static func _key_str(s: String) -> int:
	var a := s.split(":")
	return ekey(int(a[0]), int(a[1]), int(a[2]), a[3])
static func ekey(L: int, i: int, k: int, s: String) -> int:
	if s == "W": i -= 1; s = "E"
	elif s == "S": k -= 1; s = "N"
	return ((L * 32 + (i + 1)) * 32 + (k + 1)) * 2 + (0 if s == "E" else 1)

static func cx(i: int) -> float: return X0 + (i + 0.5) * C
static func cz(k: int) -> float: return Z0 + (k + 0.5) * C
static func ci(x: float) -> int: return int(floor((x - X0) / C))
static func ck(z: float) -> int: return int(floor((z - Z0) / C))
static func in_grid(i: int, k: int) -> bool: return i >= 0 and k >= 0 and i < NX and k < NZ
static func kind_at(L: int, i: int, k: int) -> int:
	return kind[L][k * NX + i] if (i >= 0 and k >= 0 and i < NX and k < NZ and L >= 0 and L < NL) else 0
static func room_at(L: int, i: int, k: int) -> int:
	return room[L][k * NX + i] if (i >= 0 and k >= 0 and i < NX and k < NZ and L >= 0 and L < NL) else -1
static func ramp_at(L: int, i: int, k: int) -> int:
	return ramp[L][k * NX + i] if (i >= 0 and k >= 0 and i < NX and k < NZ and L >= 0 and L < NL) else -1
static func room_kind(L: int, i: int, k: int) -> String:
	var r := room_at(L, i, k)
	return rooms[r]["kind"] if r >= 0 else ""
static func outdoor_at(L: int, x: float, z: float) -> bool:
	var r := room_at(L, ci(x), ck(z))
	return r >= 0 and rooms[r]["outdoor"]
static func walkable(L: int, i: int, k: int) -> bool:
	var t := kind_at(L, i, k)
	return t == 1 or t == 3
static func edge_at(L: int, i: int, k: int, s: String) -> int:
	return edges.get(ekey(L, i, k, s), 0)
static func passable(L: int, i: int, k: int, s: String) -> bool:
	var key := ekey(L, i, k, s)
	var e: int = edges.get(key, 0)
	if e == NONE or e == DOOR: return true
	if e == SDOOR: return edge_door[key]["open"]
	return false
static func see_through(L: int, i: int, k: int, s: String) -> bool:
	var key := ekey(L, i, k, s)
	var e: int = edges.get(key, 0)
	if e == NONE or e == DOOR or e == RAIL or e == GLASS or e == WINDOW: return true
	if e == SDOOR: return edge_door[key]["open"]
	return false
static func nb(i: int, k: int, s: String) -> Vector2i:
	match s:
		"E": return Vector2i(i + 1, k)
		"W": return Vector2i(i - 1, k)
		"N": return Vector2i(i, k + 1)
	return Vector2i(i, k - 1)
static func ramp_y(r: Dictionary, x: float, z: float) -> float:
	var s := z if r["along_k"] else x
	var u := clampf((s - float(r["s0"])) * r["dir"] / float(r["len"]), 0.0, 1.0)
	return r["L"] * LH + u * LH

# ---------------------------------------------------------------- graph: node id = L * NX * NZ + k * NX + i
static func node_id(L: int, i: int, k: int) -> int: return L * NX * NZ + k * NX + i
static func node_l(n: int) -> int: return n / (NX * NZ)
static func node_i(n: int) -> int: return n % NX
static func node_k(n: int) -> int: return (n % (NX * NZ)) / NX
static func node_at(L: int, x: float, z: float) -> int: return node_id(L, ci(x), ck(z))
static func node_pos(n: int) -> Vector2: return Vector2(cx(node_i(n)), cz(node_k(n)))
static func node_ok(n: int) -> bool:
	var L := node_l(n); var i := node_i(n); var k := node_k(n); var rp := ramp_at(L, i, k)
	if rp < 0: return walkable(L, i, k)
	var r: Dictionary = ramps[rp]
	var y: float = ramp_y(r, cx(i), cz(k)) - float(r["L"]) * LH
	return (y <= LH * 0.5 + 0.6) if L == r["L"] else (y >= LH * 0.5 - 0.6)
static func neighbours(n: int) -> PackedInt32Array:
	var L := node_l(n); var i := node_i(n); var k := node_k(n)
	var out := PackedInt32Array()
	for s in SIDES:
		var q := nb(i, k, s)
		if walkable(L, q.x, q.y) and passable(L, i, k, s): out.append(node_id(L, q.x, q.y))
	var rp := ramp_at(L, i, k)
	if rp >= 0:
		var rl: int = ramps[rp]["L"]
		out.append(node_id(rl + 1 if L == rl else rl, i, k))
	return out
static func edge_cost(a: int, b: int) -> float:
	return 0.01 if (node_l(a) != node_l(b)) else 1.0
static func bfs(src: int) -> Dictionary:   # cell-step distances honouring doors as they are
	var d := {src: 0.0}
	var q: Array[int] = [src]
	var h := 0
	while h < q.size():
		var a := q[h]; h += 1
		for b in neighbours(a):
			if d.has(b) or not node_ok(b): continue
			d[b] = d[a] + edge_cost(a, b); q.append(b)
	return d
static func path(src: int, dst: int) -> PackedInt32Array:
	var d := {src: 0.0}; var prev := {}
	var q: Array[int] = [src]
	var h := 0
	while h < q.size():   # BFS is exact enough here (unit steps, zero-cost twins handled by order)
		var a := q[h]; h += 1
		if a == dst: break
		for b in neighbours(a):
			if d.has(b) or not node_ok(b): continue
			d[b] = d[a] + 1.0; prev[b] = a; q.append(b)
	var out := PackedInt32Array()
	if not d.has(dst): return out
	var c := dst
	out.append(c)
	while c != src:
		c = prev[c]; out.append(c)
	out.reverse()
	return out

# ---------------------------------------------------------------- sight, collision, ground
## Line of sight on one floor through the grid's edges (walls block; doors, rails, glass do not).
static func los(L: int, x0: float, z0: float, x1: float, z1: float, sight := true) -> bool:
	var i := ci(x0); var k := ck(z0); var i1 := ci(x1); var k1 := ck(z1)
	var dx := x1 - x0; var dz := z1 - z0
	var step_i := 1 if dx > 0 else -1; var step_k := 1 if dz > 0 else -1
	var tdi := absf(C / (dx if dx != 0.0 else 1e-9)); var tdk := absf(C / (dz if dz != 0.0 else 1e-9))
	var ti := 1e9; var tk := 1e9
	if dx > 0: ti = (X0 + (i + 1) * C - x0) / dx
	elif dx < 0: ti = (X0 + i * C - x0) / dx
	if dz > 0: tk = (Z0 + (k + 1) * C - z0) / dz
	elif dz < 0: tk = (Z0 + k * C - z0) / dz
	var n := 0
	while n < 64 and (i != i1 or k != k1):
		n += 1
		if ti < tk:
			var s := "E" if step_i > 0 else "W"
			if not (see_through(L, i, k, s) if sight else passable(L, i, k, s)): return false
			i += step_i; ti += tdi
		else:
			var s2 := "N" if step_k > 0 else "S"
			if not (see_through(L, i, k, s2) if sight else passable(L, i, k, s2)): return false
			k += step_k; tk += tdk
		if ti > 1.0 and tk > 1.0: break
		if in_grid(i, k) and kind_at(L, i, k) == 0: return false
	return true

static func _edge_blocks(L: int, a: int, b: int, s: String) -> int:   # 0 open, 1 solid, 2 doorway (posts either side of a gap)
	var key := ekey(L, a, b, s)
	var e: int = edges.get(key, 0)
	if e == NONE: return 0
	if e == DOOR or (e == SDOOR and edge_door[key]["open"]): return 2
	return 1
## Push a circle (pos.x, pos.z, radius r) out of walls, door posts and furniture on floor L.
static func collide(L: int, pos: Vector3, r := 0.3) -> Vector3:
	var i := ci(pos.x); var k := ck(pos.z)
	for a in range(i - 1, i + 2):
		for b in range(k - 1, k + 2):
			for s in ["E", "N"]:
				var t := _edge_blocks(L, a, b, s)
				if t == 0: continue
				var x0: float; var z0: float; var x1: float; var z1: float
				if s == "E": x0 = X0 + (a + 1) * C; x1 = x0; z0 = Z0 + b * C; z1 = z0 + C
				else: z0 = Z0 + (b + 1) * C; z1 = z0; x0 = X0 + a * C; x1 = x0 + C
				if t == 1: pos = _push_seg(pos, r, x0, z0, x1, z1, s)
				else:
					var f := 0.4 / C
					pos = _push_seg(pos, r, x0, z0, x0 + (x1 - x0) * f, z0 + (z1 - z0) * f, s)
					pos = _push_seg(pos, r, x1 - (x1 - x0) * f, z1 - (z1 - z0) * f, x1, z1, s)
	for o in obstacles:
		if o["L"] != L: continue
		var dx: float = pos.x - o["x"]; var dz: float = pos.z - o["z"]; var m: float = o["r"] + r * 0.8
		var d2 := dx * dx + dz * dz
		if d2 < m * m and d2 > 1e-10:
			var d := sqrt(d2); pos.x = o["x"] + dx / d * m; pos.z = o["z"] + dz / d * m
	return pos
static func _push_seg(pos: Vector3, r: float, x0: float, z0: float, x1: float, z1: float, s: String) -> Vector3:
	var dx := x1 - x0; var dz := z1 - z0; var l2 := dx * dx + dz * dz
	if l2 < 1e-9: l2 = 1e-9
	var t := clampf(((pos.x - x0) * dx + (pos.z - z0) * dz) / l2, 0.0, 1.0)
	var px := x0 + dx * t; var pz := z0 + dz * t; var ex := pos.x - px; var ez := pos.z - pz
	var d := sqrt(ex * ex + ez * ez)
	if d < r and d > 1e-6: pos.x = px + ex / d * r; pos.z = pz + ez / d * r
	elif d <= 1e-6:
		if s == "E": pos.x += r
		else: pos.z += r
	return pos
## Floor height and floor index at a point, given the floor we were on: [y, L]
static func ground(L: int, x: float, z: float) -> Array:
	var rp := ramp_at(L, ci(x), ck(z))
	if rp < 0: return [L * LH, L]
	var r: Dictionary = ramps[rp]
	var y := ramp_y(r, x, z)
	return [y, (r["L"] + 1) if (y - r["L"] * LH > LH / 2.0) else r["L"]]
## Distance to the nearest blocking edge (m), up to 6 m.
static func wall_dist(L: int, x: float, z: float) -> float:
	var best := 6.0
	var i := ci(x); var k := ck(z)
	for a in range(i - 3, i + 4):
		for b in range(k - 3, k + 4):
			for s in ["E", "N"]:
				var key := ekey(L, a, b, s)
				var e: int = edges.get(key, 0)
				if e == NONE or e == DOOR or e == RAIL: continue
				if e == SDOOR and edge_door[key]["open"]: continue
				var x0: float; var z0: float; var x1: float; var z1: float
				if s == "E": x0 = X0 + (a + 1) * C; x1 = x0; z0 = Z0 + b * C; z1 = z0 + C
				else: z0 = Z0 + (b + 1) * C; z1 = z0; x0 = X0 + a * C; x1 = x0 + C
				var dx := x1 - x0; var dz := z1 - z0
				var t := clampf(((x - x0) * dx + (z - z0) * dz) / (dx * dx + dz * dz), 0.0, 1.0)
				best = minf(best, Vector2(x - x0 - dx * t, z - z0 - dz * t).length())
	return best
## Every room still reachable from the lobby?
static func connected() -> bool:
	var d := bfs(node_id(0, 13, 9))
	for r in rooms:
		var rc: Array = r["rect"]; var ok := false
		for i in range(rc[0], rc[2] + 1):
			for k in range(rc[1], rc[3] + 1):
				if walkable(r["L"], i, k) and d.has(node_id(r["L"], i, k)): ok = true; break
			if ok: break
		if not ok: return false
	return true
static func door_mid(d: Dictionary) -> Vector2:   # world position of the middle of a door's first edge
	var s: String = d["s"]
	return Vector2(cx(d["i"]) + (C / 2.0 if s == "E" else (-C / 2.0 if s == "W" else 0.0)), cz(d["k"]) + (C / 2.0 if s == "N" else (-C / 2.0 if s == "S" else 0.0)))
