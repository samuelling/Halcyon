class_name LevelGen
## Levels made in code (the hotel is exported from the browser build's generator instead):
##   gardens   open ground: lawns, hedges and low walls, four pavilions, long sight lines, daylight
##   service   tight quarters: two floors of 2 m corridors and small rooms under the hotel, tube lighting
## Each returns a dictionary in the same shape as level/level.json, plus "meta" (what the director
## needs: where you start, the ways out, where guests wait) and without "surfaces" (Level builds the
## geometry from the plan).

class B:
	var NX := 28; var NZ := 28; var NL := 1; var X0 := -28.0; var Z0 := -28.0; var C := 2.0; var LH := 4.2; var CEIL := 3.5
	var kind: Array = []; var room: Array = []; var ramp: Array = []
	var edges := {}; var rooms: Array = []; var ramps: Array = []; var doors: Array = []; var door_vis: Array = []
	var lamps: Array = []; var place: Array = []; var obstacles: Array = []
	var rng := RandomNumberGenerator.new()
	func _init(nl: int, seed_: int) -> void:
		NL = nl; rng.seed = seed_
		for L in NL:
			var a := PackedInt32Array(); a.resize(NX * NZ); a.fill(0); kind.append(a)
			var b := PackedInt32Array(); b.resize(NX * NZ); b.fill(-1); room.append(b)
			var c := PackedInt32Array(); c.resize(NX * NZ); c.fill(-1); ramp.append(c)
	func cx(i: int) -> float: return X0 + (i + 0.5) * C
	func cz(k: int) -> float: return Z0 + (k + 0.5) * C
	func walk(L: int, i: int, k: int) -> bool: return i >= 0 and k >= 0 and i < NX and k < NZ and kind[L][k * NX + i] != 0 and kind[L][k * NX + i] != 2
	func add_room(name: String, L: int, i0: int, k0: int, i1: int, k1: int, kd: String, outdoor := false) -> int:
		var id := rooms.size()
		rooms.append({"id": id, "name": name, "L": L, "rect": [i0, k0, i1, k1], "kind": kd, "outdoor": outdoor})
		for k in range(k0, k1 + 1):
			for i in range(i0, i1 + 1): kind[L][k * NX + i] = 1; room[L][k * NX + i] = id
		return id
	func cells(L: int, id: int, list: Array) -> void:    # extra cells for a room that is not a rectangle
		for q: Array in list: kind[L][q[1] * NX + q[0]] = 1; room[L][q[1] * NX + q[0]] = id
	func edge(L: int, i: int, k: int, s: String, t: int) -> void: edges[Plan.ekey(L, i, k, s)] = t
	func run(L: int, i0: int, k0: int, i1: int, k1: int, s: String, t: int) -> void:
		for k in range(k0, k1 + 1):
			for i in range(i0, i1 + 1): edge(L, i, k, s, t)
	func sdoor(L: int, i: int, k: int, s: String, name: String) -> void:
		var key := Plan.ekey(L, i, k, s); edges[key] = Plan.SDOOR
		var id := doors.size()
		doors.append({"id": id, "L": L, "i": i, "k": k, "s": s, "name": name, "keys": [key]})
		var east := s == "E" or s == "W"
		var x := (X0 + (i + (1 if s == "E" else 0)) * C) if east else cx(i); var z := cz(k) if east else (Z0 + (k + (1 if s == "N" else 0)) * C)
		var ry := PI / 2 if east else 0.0
		var nx := 0.13 if east else 0.0; var nz := 0.0 if east else 0.13
		door_vis.append({"id": id, "leaves": [[x, L * LH + 1.15, z, ry]], "lamps": [[x - nx, L * LH + 2.55, z - nz, ry], [x + nx, L * LH + 2.55, z + nz, ry]]})
	## A straight flight from floor L up to L + 1 along the lane, rising in direction axis ("+i", "-i", "+k", "-k").
	func stairs(name: String, group: String, L: int, i0: int, k0: int, i1: int, k1: int, axis: String) -> void:
		var id := ramps.size(); var ak := axis[1] == "k"; var dir := 1 if axis[0] == "+" else -1
		var n := (k1 - k0 + 1) if ak else (i1 - i0 + 1)
		var s0 := (Z0 + (k0 if dir > 0 else k1 + 1) * C) if ak else (X0 + (i0 if dir > 0 else i1 + 1) * C)
		ramps.append({"id": id, "name": name, "group": group, "L": L, "lane": [i0, k0, i1, k1], "axis": axis, "len": n * C, "dir": dir, "s0": s0})
		for k in range(k0, k1 + 1):
			for i in range(i0, i1 + 1):
				for q in [L, L + 1]:
					kind[q][k * NX + i] = 3; ramp[q][k * NX + i] = id
					for s in Plan.SIDES:
						var jm := Plan.nb(i, k, s)
						if jm.x >= i0 and jm.x <= i1 and jm.y >= k0 and jm.y <= k1: continue
						var along := (s == "N" or s == "S") if ak else (s == "E" or s == "W")
						var t := Plan.WALL
						if along:
							var plus := s == "N" or s == "E"
							var is_head := plus == (dir > 0)
							if (is_head and q == L + 1) or (not is_head and q == L): t = Plan.NONE
						edge(q, i, k, s, t)
	func prop(model: String, L: int, x: float, z: float, rot := 0.0, y = null, scale := 1.0, collide := 0.0) -> void:
		place.append([model, L, x, z, rot, y, scale, collide])
		if collide > 0.0: obstacles.append({"L": L, "x": x, "z": z, "r": collide})
	func lamp(L: int, x: float, z: float, I: float, fixture := "tube") -> void:
		var i := int(floor((x - X0) / C)); var k := int(floor((z - Z0) / C))
		lamps.append({"L": L, "x": x, "y": L * LH + CEIL - 0.05, "z": z, "I": I, "room": room[L][k * NX + i], "fixture": fixture})
	func finish(meta: Dictionary) -> Dictionary:
		# walls wherever floor meets nothing or another room, unless something was put there on purpose
		for L in NL:
			for k in NZ:
				for i in NX:
					if not walk(L, i, k): continue
					for s in Plan.SIDES:
						var key := Plan.ekey(L, i, k, s)
						if edges.has(key): continue
						var jm := Plan.nb(i, k, s)
						if not walk(L, jm.x, jm.y) or room[L][jm.y * NX + jm.x] != room[L][k * NX + i]: edges[key] = Plan.WALL
		var el: Array = []
		for key: int in edges:
			if edges[key] != Plan.NONE: el.append([key, edges[key]])
		var kl: Array = []; var rl: Array = []; var pl: Array = []
		for L in NL: kl.append(Array(kind[L])); rl.append(Array(room[L])); pl.append(Array(ramp[L]))
		return {"meta": meta, "plan": {"C": C, "NX": NX, "NZ": NZ, "NL": NL, "LH": LH, "CEIL": CEIL, "X0": X0, "Z0": Z0, "kind": kl, "room": rl, "ramp": pl,
			"edges": el, "doors": doors, "ramps": ramps, "rooms": rooms}, "doors": door_vis, "lamps": lamps, "place": place, "obstacles": obstacles}

static func make(name: String, seed_ := 1) -> Dictionary:
	return gardens(seed_) if name == "gardens" else service(seed_)

# ------------------------------------------------------------------------------------------ the gardens
static func gardens(seed_ := 1) -> Dictionary:
	var b := B.new(1, seed_)
	b.add_room("Lawn", 0, 0, 0, 27, 27, "field", true)
	# four pavilions, a door towards the middle and windows on the other sides
	var pav := [["West pavilion", 3, 19, 5, 20, "S", 4, 19], ["East pavilion", 22, 19, 24, 20, "S", 23, 19], ["Boat house", 3, 7, 5, 8, "N", 4, 8], ["Glass house", 22, 7, 24, 8, "N", 23, 8]]
	for q: Array in pav:
		b.add_room(q[0], 0, q[1], q[2], q[3], q[4], "pavilion")
		for i in range(q[1], q[3] + 1):
			b.edge(0, i, q[2], "S", Plan.WINDOW); b.edge(0, i, q[4], "N", Plan.WINDOW)
		b.edge(0, q[6], q[7], q[5], Plan.DOOR)
		b.lamp(0, b.cx(q[1] + 1), b.cz(q[2]) + 1.0, 1.2, "ceiling")
		b.prop("wooden_crate_01", 0, b.cx(q[1]) - 0.3, b.cz(q[2]) + 0.2, 0.3, null, 1.0, 0.45)
	# hedges (block the way and the view) and low walls (block the way only)
	for h: Array in [[2, 10, 9, 10, "N"], [18, 10, 25, 10, "N"], [6, 16, 11, 16, "N"], [16, 16, 21, 16, "N"], [9, 12, 9, 15, "E"], [18, 11, 18, 14, "E"], [13, 3, 13, 5, "E"], [13, 22, 13, 24, "E"],
			[7, 2, 7, 4, "E"], [20, 23, 20, 25, "E"], [1, 14, 3, 14, "N"], [24, 13, 26, 13, "N"]]:
		b.run(0, h[0], h[1], h[2], h[3], h[4], Plan.WALL)
	for h: Array in [[11, 11, 12, 11, "S"], [15, 11, 16, 11, "S"], [11, 16, 12, 16, "N"], [15, 16, 16, 16, "N"], [10, 12, 10, 13, "E"], [16, 14, 16, 15, "E"], [5, 12, 7, 12, "N"], [20, 18, 22, 18, "N"]]:
		b.run(0, h[0], h[1], h[2], h[3], h[4], Plan.RAIL)
	b.prop("__fountain", 0, 0.0, 0.0, 0.0, null, 1.0, 1.9)
	var spots: Array = []
	for n in 16:
		for tries in 30:
			var x := b.rng.randf_range(-25.0, 25.0); var z := b.rng.randf_range(-25.0, 25.0)
			var ok := absf(x) > 4.0 or absf(z) > 6.0     # keep the central walk and the gates clear
			if absf(x) < 3.0: ok = false
			for q: Array in pav:
				if x > b.cx(q[1]) - 2.5 and x < b.cx(q[3]) + 2.5 and z > b.cz(q[2]) - 2.5 and z < b.cz(q[4]) + 2.5: ok = false
			for sp: Vector2 in spots:
				if sp.distance_to(Vector2(x, z)) < 5.0: ok = false
			if ok: spots.append(Vector2(x, z)); break
	for n in spots.size():
		var sp: Vector2 = spots[n]
		if n < 10: b.prop("__tree", 0, sp.x, sp.y, b.rng.randf() * TAU, null, 0.85 + b.rng.randf() * 0.5, 0.45)
		else: b.prop("shrub_01", 0, sp.x, sp.y, b.rng.randf() * TAU, null, 1.6, 0.6)
	for q: Array in [[-6.0, 3.0, PI / 2], [6.0, -3.0, -PI / 2], [-3.0, 14.0, 0.0], [3.0, -14.0, PI]]:
		b.prop("painted_wooden_bench", 0, q[0], q[1], q[2], null, 1.0, 0.6)
	b.prop("outdoor_table_chair_set_01", 0, -15.0, 3.0, 0.4, null, 1.0, 1.0); b.prop("outdoor_table_chair_set_01", 0, 14.0, -1.0, 1.2, null, 1.0, 1.0)
	for q: Array in [[-2.6, -26.0], [2.6, -26.0], [-2.6, 26.0], [2.6, 26.0], [-12.0, 0.0], [12.0, 0.0]]:
		b.prop("__lamppost", 0, q[0], q[1], 0.0, null, 1.0, 0.2); b.lamps.append({"L": 0, "x": q[0], "y": 3.4, "z": q[1], "I": 1.3, "room": 0, "fixture": "post"})
	var meta := {"name": "gardens", "title": "THE GARDENS", "spawn": [0, 0.0, -24.0, PI], "respawn": [[0, -1.0, -24.0], [0, 1.0, -24.0]],
		"exits": {"south": {"label": "SOUTH GATE", "rect": [0, 13, 0, 14, 0], "nodes": [[0, 13, 0], [0, 14, 0]]}, "north": {"label": "NORTH GATE", "rect": [0, 13, 27, 14, 27], "nodes": [[0, 13, 27], [0, 14, 27]]}},
		"exit_cycle": ["north", "south"], "objective_kinds": ["pavilion"], "objective_min_L": 0, "blackout_p": 0.0, "blackout_min_L": 0,
		"spawn_far": 24.0, "spawn_cells": 16, "stop_hostile": 17.0, "sky": "day",
		"signs": [["EXIT", 0.0, 3.3, -27.6, 0.0, "green", 0.5], ["EXIT", 0.0, 3.3, 27.6, PI, "green", 0.5]]}
	return b.finish(meta)

# ------------------------------------------------------------------------------------------ the service level
static func service(seed_ := 1) -> Dictionary:
	var b := B.new(2, seed_)
	var VC := [2, 9, 16, 23]; var HC := [3, 9, 15, 21]     # corridors: one cell (2 m) wide
	var kinds := [["boiler", "laundry", "plant", "kitchen", "locker", "workshop", "pump", "cold", "linen"], ["store", "store", "office", "store", "store", "linen", "store", "store", "archive"]]
	for L in 2:
		var cid := b.add_room("Service corridor %d" % L, L, 2, 3, 2, 3, "corridor")
		var cl: Array = []
		for i in VC:
			for k in range(3, 22): cl.append([i, k])
		for k in HC:
			for i in range(2, 24): cl.append([i, k])
		if L == 0:
			for k in range(0, 3): cl.append([9, k])       # the loading dock
			for k in range(22, 25): cl.append([16, k])    # the lift lobby
		b.cells(L, cid, cl)
		b.rooms[cid]["rect"] = [2, 3, 23, 21]
		var nb := 0
		for bk in 3:
			for bi in 3:
				var i0: int = VC[bi] + 1; var k0: int = HC[bk] + 1; var kd: String = kinds[L][nb]; nb += 1
				var stair := (bi == 0 and bk == 1) or (bi == 2 and bk == 1) or (bi == 1 and bk == 2) or (bi == 1 and bk == 0)
				if stair:
					# a flight crosses the block from one corridor to the next; small rooms above and below it
					b.add_room("%s %d%d a" % [kd, L, nb], L, i0, k0, i0 + 5, k0 + 1, kd); b.add_room("%s %d%d b" % [kd, L, nb], L, i0, k0 + 3, i0 + 5, k0 + 4, kd)
					b.edge(L, i0 + 2, k0, "S", Plan.DOOR); b.edge(L, i0 + 3, k0 + 4, "N", Plan.DOOR)
					b.add_room("Stairs %d%d" % [L, nb], L, i0, k0 + 2, i0 + 5, k0 + 2, "stair")
				else:
					b.add_room("%s %d%d a" % [kd, L, nb], L, i0, k0, i0 + 2, k0 + 4, kd); b.add_room("%s %d%d b" % [kd, L, nb], L, i0 + 3, k0, i0 + 5, k0 + 4, kd)
					b.edge(L, i0, k0 + 2, "W", Plan.DOOR); b.edge(L, i0 + 1, k0, "S", Plan.DOOR)
					b.edge(L, i0 + 5, k0 + 2, "E", Plan.DOOR); b.edge(L, i0 + 4, k0 + 4, "N", Plan.DOOR)
	b.stairs("West flight", "W", 0, 3, 12, 8, 12, "+i"); b.stairs("East flight", "E", 0, 17, 12, 22, 12, "-i")
	b.stairs("North flight", "N", 0, 10, 18, 15, 18, "+i"); b.stairs("South flight", "S", 0, 10, 6, 15, 6, "-i")
	# security doors across the corridors
	for q: Array in [[0, 5, 3, "E", "Dock passage"], [0, 12, 9, "E", "Kitchen passage"], [0, 19, 15, "E", "Pump passage"], [0, 2, 6, "N", "West run"], [0, 16, 13, "N", "Middle run"], [0, 23, 18, "N", "East run"],
			[0, 12, 21, "E", "Lift passage"], [1, 6, 9, "E", "Store passage"], [1, 19, 3, "E", "Archive passage"], [1, 9, 13, "N", "Linen run"], [1, 23, 7, "N", "Office run"], [1, 12, 15, "E", "North stores"], [1, 2, 17, "N", "West stores"]]:
		b.sdoor(q[0], q[1], q[2], q[3], q[4])
	# tube lights: every third cell of corridor (some dead), one in each room
	for L in 2:
		var n := 0
		for i: int in VC:
			for k in range(4, 21, 3):
				n += 1
				if n % 5 != 3: b.lamp(L, b.cx(i), b.cz(k), 0.8)
		for k: int in HC:
			for i in range(4, 23, 3):
				n += 1
				if n % 5 != 1: b.lamp(L, b.cx(i), b.cz(k), 0.8)
		for r: Dictionary in b.rooms:
			if r["L"] != L or r["kind"] == "corridor": continue
			var rc: Array = r["rect"]
			if r["kind"] != "stair": b.lamp(L, (b.cx(rc[0]) + b.cx(rc[2])) / 2.0, (b.cz(rc[1]) + b.cz(rc[3])) / 2.0, 1.0 if b.rng.randf() < 0.8 else 0.35)
			else: b.lamp(L, b.cx(rc[0] + 2), b.cz(rc[1]), 0.6)
			if r["kind"] == "stair" or (rc[2] - rc[0]) < 2: continue
			# a little clutter against the far wall
			var models := ["barrel_03", "wooden_crate_01", "cardboard_box_01", "drawer_cabinet", "wooden_barrels_01"]
			for m in 2:
				var mdl: String = models[b.rng.randi_range(0, models.size() - 1)]
				b.prop(mdl, L, b.cx(rc[0]) + 0.1 + m * (b.cx(rc[2]) - b.cx(rc[0])), b.cz(rc[3]) + 0.35, b.rng.randf() * TAU, null, 1.0, 0.5)
		# pipes along the ceilings of the long corridors
		for i: int in VC: b.prop("__pipe", L, b.cx(i) - 0.55, b.cz(12), 0.0, L * b.LH + 3.05, 38.0)
		for k: int in HC: b.prop("__pipe", L, b.cx(12) + 1.0, b.cz(k) + 0.55, PI / 2, L * b.LH + 3.15, 44.0)
	b.lamp(0, b.cx(9), b.cz(1), 1.0); b.lamp(0, b.cx(16), b.cz(23), 1.0)
	var meta := {"name": "service", "title": "THE SERVICE LEVEL", "spawn": [0, b.cx(9), b.cz(2), PI], "respawn": [[0, b.cx(9), b.cz(2)], [0, b.cx(9), b.cz(1)]],
		"exits": {"dock": {"label": "LOADING DOCK", "rect": [0, 9, 0, 9, 1], "nodes": [[0, 9, 0]]}, "lift": {"label": "LIFT LOBBY", "rect": [0, 16, 23, 16, 24], "nodes": [[0, 16, 24]]}},
		"exit_cycle": ["lift", "dock"], "objective_kinds": ["store", "archive", "office", "linen"], "objective_min_L": 1, "blackout_p": 0.85, "blackout_min_L": 1,
		"spawn_far": 0.0, "spawn_cells": 10, "stop_hostile": 9.0, "react_scale": 0.5, "sky": "none",
		"signs": [["EXIT", b.cx(9), 2.9, b.cz(0) - 0.8, 0.0, "green", 0.34], ["LIFT", b.cx(16), 2.9, b.cz(24) + 0.8, PI, "green", 0.34]]}
	return b.finish(meta)
