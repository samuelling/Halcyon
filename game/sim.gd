extends SceneTree
## Headless logic simulation: godot --headless --path . --script game/sim.gd -- seed=1 minutes=10 [out=path.json]
## No rendering, no people on screen: the bot plays the plan and the director; prints the design numbers.
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Plan.load_level()
	var lv := Level.new(); lv.quality = "none"; lv.lamps_only(Plan.raw)
	var g := Game.new(); g.setup(lv, false)
	var bot := Bot.new(g, int(args.get("seed", "1")))
	var minutes := float(args.get("minutes", "10"))
	var n := int(minutes * 600.0)
	var dark := 0; var terrace := 0; var nvis := 0; var t0 := Time.get_ticks_msec()
	var recs: Array = []
	for f in n:
		bot.tick(0.05); bot.tick(0.05)
		var rec := bot.record()
		if rec["dark"] == 1: dark += 1
		if Plan.outdoor_at(g.player.L, g.player.pos.x, g.player.pos.z): terrace += 1
		nvis += (rec["vis"] as Array).size()
		if args.has("out"): recs.append(rec)
	var ev := bot.ev; var h := minutes / 60.0
	var ct: Array = []
	for c in ev["calls"]: ct.append(c[0])
	var gaps: Array = []
	for i in range(1, ct.size()): gaps.append(ct[i] - ct[i - 1])
	gaps.sort()
	var homes := 0
	for q in ev["homing"]:
		if q[-2] == 1: homes += 1
	var resc := 0
	for q in ev["objectives"]:
		if q[1] == "rescued": resc += 1
	var amb := 0
	for q in ev["outcomes"]: amb += q[2]
	print("seed %s  %.0f min in %.1f s" % [args.get("seed", "1"), minutes, (Time.get_ticks_msec() - t0) / 1000.0])
	print("  rescues/h %.0f  deaths/h %.0f  wrong kills %d  hostiles %d  stuck %d" % [resc / h, ev["deaths"].size() / h, g.score["wrong"], g.score["hostiles"], bot.n_stuck])
	print("  calls/h %.0f  gap median %.1f s  p10 %.1f s  min %.1f s" % [ct.size() / h, gaps[gaps.size() / 2] if gaps.size() else 0.0, gaps[gaps.size() / 10] if gaps.size() else 0.0, gaps[0] if gaps.size() else 0.0])
	print("  stair crossings/h %.0f (ambush %.0f%%)  stair choices/h %.0f" % [ev["outcomes"].size() / h, 100.0 * amb / maxf(1, ev["outcomes"].size()), ev["stairs"].size() / h])
	print("  dark %.1f%%  terrace %.1f%%  homing walks/h %.0f (home %.0f)  blackouts/h %.0f" % [100.0 * dark / n, 100.0 * terrace / n, ev["homing"].size() / h, homes / h, ev["blackouts"].size() / 2.0 / h])
	print("  people in view per frame %.2f  shots/h %.0f  kills/h %.0f  doors stale/h %.0f" % [float(nvis) / n, ev["shots"].size() / h, ev["kills"].size() / h, ev["stale"].size() / h])
	if args.has("stuck"):
		for q in bot.stuck_log: print(q)
	if args.has("out"):
		var fa := FileAccess.open(args["out"], FileAccess.WRITE); fa.store_string(JSON.stringify({"events": ev, "log": recs})); fa.close()
	quit()
