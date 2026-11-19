extends Node3D
## Entry point. A plain launch is the game. User arguments (after "--"):
##   bot=1 [seed=N]                       watch the simulated player
##   scan=<prefix> seed=N frames=M        BOLDBLASTER harness: 384x288 render, 192x144 frames + log + events
##   shots=<name>,<x>,<y>,<z>,<yaw>,<pitch>[,<ortho size>];...   stills for checking the look
##   level=hotel|gardens|service   q=high|scan   people=1 (stage some people for stills)   dark=1

static var level_name := ""      # survives a scene reload: the title card switches level by reloading
var level: Level
var game: Game
var view: View
var fx: Fx
var hud: Hud
var bot: Bot
var args := {}
var mode := "play"
var look := Vector2.ZERO
var playing := false
var sens := 0.0022
var torch_latch := false
var use_latch := false
var snap_n := 0
var us_tick := 0
var us_draw := 0
var us_tick_last := 0
var us_draw_last := 0
var us_read_last := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0].trim_prefix("--")] = kv[1] if kv.size() > 1 else "1"
	mode = "shots" if args.has("shots") else ("scan" if args.has("scan") else ("bot" if args.has("bot") else "play"))
	if level_name == "": level_name = args.get("level", "hotel")
	if level_name == "hotel": Plan.load_level()
	else: Plan.load_dict(LevelGen.make(level_name))
	level = Level.new(); add_child(level)
	level.build(args.get("q", "scan" if mode == "scan" else "high"))
	game = Game.new(); add_child(game); game.setup(level, true)
	view = View.new(); add_child(view); view.setup(game); game.view = view
	fx = Fx.new(); add_child(fx); fx.setup(game, view, mode == "scan" or mode == "shots"); game.fx = fx
	var vs := get_viewport().get_visible_rect().size; game.aspect = vs.x / vs.y
	if mode == "play" or mode == "bot":
		hud = Hud.new(); add_child(hud); hud.setup(game); game.hud = hud
	if mode == "play":
		game.human = true; game.reset(int(args.get("seed", str(randi() % 100000)))); hud.show_card(true)
	elif mode == "bot":
		bot = Bot.new(game, int(args.get("seed", "1")))
	elif mode == "scan":
		# the software-rendered preset: 192x144 with 4x MSAA standing in for the 2x2 supersample, lighter shadows and fog
		var vp := get_viewport(); vp.msaa_3d = Viewport.MSAA_4X; vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		RenderingServer.environment_set_volumetric_fog_volume_size(48, 48)
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50, 300)
		level.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS; level.sun.directional_shadow_max_distance = 55.0
		view.flash.shadow_enabled = false
		if args.has("sdfgi"): level.env.sdfgi_enabled = true
		if args.has("noshadow"): level.sun.shadow_enabled = false
		if args.has("nofog"): level.env.volumetric_fog_enabled = false
		if args.has("noao"): level.env.ssao_enabled = false
		if args.has("noglow"): level.env.glow_enabled = false
		if args.has("noprops"):
			for r in level.props: (r["node"] as Node3D).queue_free()
			level.props.clear()
		if args.has("nomsaa"): vp.msaa_3d = Viewport.MSAA_DISABLED
		if args.has("nolights"):
			for r in level.lamps: (r["node"] as Node3D).queue_free()
			level.lamps.clear()
			for r in level.signs: (r["light"] as Node3D).queue_free()
			level.signs.clear()
		if args.has("noexp"): level.cam_attr.auto_exposure_enabled = false
		if args.has("nobody"): view.show_body = false
		if args.has("noview"): view.show_body = false; view.pistol.visible = false   # no arms, no pistol: the scene alone
		game.enc_gate = float(args.get("gate", str(game.enc_gate))); game.enc_min = float(args.get("emin", str(game.enc_min))); game.enc_span = float(args.get("espan", str(game.enc_span))); game.enc_serial = args.get("serial", "1" if game.enc_serial else "0") == "1"
		_scan()
	elif mode == "shots": _shots()
	get_viewport().size_changed.connect(func(): var s := get_viewport().get_visible_rect().size; game.aspect = s.x / s.y)

func _unhandled_input(e: InputEvent) -> void:
	if mode != "play": return
	if e is InputEventMouseMotion and playing: look += (e as InputEventMouseMotion).relative
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and not playing:
		playing = true; hud.show_card(false); Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var k := (e as InputEventKey).physical_keycode
		if not playing and k in [KEY_1, KEY_2, KEY_3]:      # on the title card: choose where to play
			var want: String = ["hotel", "gardens", "service"][[KEY_1, KEY_2, KEY_3].find(k)]
			if want != level_name: level_name = want; get_tree().reload_current_scene()
		elif k == KEY_ESCAPE:
			playing = false; hud.show_card(true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif k == KEY_F11:
			var w := get_window(); w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _human_inp(dt: float) -> Game.Inp:
	var i := Game.Inp.new()
	var kx := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	var kz := (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
	var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X); var jz := -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	i.move_x = kx + (jx if absf(jx) > 0.2 else 0.0); i.move_z = kz + (jz if absf(jz) > 0.2 else 0.0)
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X); var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var ads := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.4
	var s := sens * (0.6 if ads else 1.0)
	i.look_x = look.x * s + (rx if absf(rx) > 0.15 else 0.0) * dt * 2.6; i.look_y = look.y * s + (ry if absf(ry) > 0.15 else 0.0) * dt * 2.0
	look = Vector2.ZERO
	i.fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	i.ads = ads
	i.run = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)
	i.reload = Input.is_physical_key_pressed(KEY_R) or Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	var u := Input.is_physical_key_pressed(KEY_E) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	i.use = u
	var tk := Input.is_physical_key_pressed(KEY_F) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	i.torch_toggle = tk and not torch_latch; torch_latch = tk
	return i

func _level_step(dt: float) -> void:
	var p := game.player
	level.step(dt, p.L, Plan.ramp_at(p.L, Plan.ci(p.pos.x), Plan.ck(p.pos.z)) >= 0, game.eye())

func _process(delta: float) -> void:
	if mode == "play":
		var dt := minf(delta, 0.05)
		if playing: game.step(dt, _human_inp(dt))
		else: view.update(0.0, Game.Inp.new())
		_level_step(dt); hud.update(dt)
	elif mode == "bot":
		var dt := minf(delta, 0.05)
		bot.tick(dt); bot.record(); _level_step(dt); hud.update(dt)
	if args.has("snap") and (mode == "bot" or mode == "play"):
		snap_n += 1
		if snap_n % int(args["snap"]) == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://shots/snap_%s%d.png" % [mode, snap_n / int(args["snap"])])
			if snap_n >= int(args["snap"]) * int(args.get("snaps", "1")): get_tree().quit()

# ------------------------------------------------------------------------------ the scanner harness
func _scan() -> void:
	var prefix: String = args["scan"]; var seed_v := int(args.get("seed", "1")); var frames := int(args.get("frames", "600"))
	bot = Bot.new(game, seed_v)
	var f_img := FileAccess.open(prefix + "_rgb.u8", FileAccess.WRITE); var f_log := FileAccess.open(prefix + "_log.jsonl", FileAccess.WRITE)
	var t0 := Time.get_ticks_msec()
	for w in 12:   # let the light settle before the clock starts
		view.update(0.0, Game.Inp.new()); _level_step(0.05)
		await get_tree().process_frame
	for f in frames:
		var ta := Time.get_ticks_usec()
		bot.tick(0.05); _level_step(0.05); bot.tick(0.05); _level_step(0.05)
		var rec := bot.record()
		var tb := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		var tc := Time.get_ticks_usec()
		var img := get_viewport().get_texture().get_image()
		us_tick += tb - ta; us_draw += tc - tb
		if f >= frames - 20: us_tick_last += tb - ta; us_draw_last += tc - tb; us_read_last += Time.get_ticks_usec() - tc
		img.convert(Image.FORMAT_RGB8)
		if img.get_width() != 192: img.shrink_x2()
		f_img.store_buffer(img.get_data()); f_log.store_line(JSON.stringify(rec))
		if f % 300 == 299:
			f_img.flush(); f_log.flush()
			print("frame %d  %.2f fps  rescued %d" % [f + 1, (f + 1) * 1000.0 / (Time.get_ticks_msec() - t0), game.score["rescued"]])
	f_img.close(); f_log.close()
	var fe := FileAccess.open(prefix + "_events.json", FileAccess.WRITE); fe.store_string(JSON.stringify(bot.ev)); fe.close()
	print("done ", frames, " frames in ", (Time.get_ticks_msec() - t0) / 1000.0, " s; per frame ms: ticks ", us_tick / 1000.0 / frames, " draw ", us_draw / 1000.0 / frames, "; last 20: ticks ", us_tick_last / 20000.0, " draw ", us_draw_last / 20000.0, " read ", us_read_last / 20000.0)
	get_tree().quit()

# ------------------------------------------------------------------------------ stills
func _shots() -> void:
	var warm := int(args.get("warm", "30"))
	var t0 := Time.get_ticks_msec()
	game.reset(3); game.human = false
	if args.has("dark"): level.set_power(false); game.power = 0.0; game.dark_until = 1e9; game.dark_L = -5; game.player.torch = true
	view.show_body = not args.has("nobody")
	for s in String(args["shots"]).split(";"):
		var f := s.split(",")
		var p := game.player
		p.pos = Vector3(float(f[1]), float(f[2]) - Game.EYE, float(f[3])); p.yaw = deg_to_rad(float(f[4])); p.pitch = deg_to_rad(float(f[5]))
		p.L = clampi(int(floor((p.pos.y + 0.5) / Plan.LH)), 0, Plan.NL - 1)
		if f.size() > 6: view.cam.projection = Camera3D.PROJECTION_ORTHOGONAL; view.cam.size = float(f[6])
		else: view.cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		if args.has("people"): _stage(p)
		for n in warm:
			for a in game.actors: a.t += 0.1; a.sync(0.1)
			var inp := Game.Inp.new(); inp.ads = args.has("ads")
			p.ads = 1.0 if args.has("ads") else 0.0
			view.update(0.1, inp); _level_step(0.1); fx.update(0.1)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % f[0])
		print("shot ", f[0], " ", Time.get_ticks_msec() - t0, " ms")
	get_tree().quit()

func _stage(p: Game.Player) -> void:
	for a in game.actors: a.dispose()
	game.actors.clear()
	var f := Vector3(-sin(p.yaw), 0, -cos(p.yaw)); var r := Vector3(-f.z, 0, f.x)
	var spec := [["gunman", "aim", 5.0, -1.6, "fight"], ["gunman", "low", 6.5, -0.4, "idle"], ["guest", "phone", 5.5, 0.9, "idle"], ["guest", "hands", 7.0, 1.9, "idle"], ["staff", "phone", 9.0, -1.0, "walk"], ["gunman", "aim", 10.0, 0.4, "walk"]]
	for q: Array in spec:
		var pos := p.pos + f * float(q[2]) + r * float(q[3])
		var g := game.new_group(q[0] == "gunman", q[1])
		var a := Actor.new(game, q[0], p.L, pos.x, pos.z, p.yaw + PI, q[1]); a.group = g["id"]; a.pos.y = p.pos.y
		if q[4] == "fight": a.state = "fight"
		if q[4] == "walk": a.speed = 1.5
		game.actors.append(a)
