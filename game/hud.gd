class_name Hud
extends CanvasLayer
## Heads-up display, the lens shader, and the title / pause card.

var game: Game
var post: ColorRect
var pm: ShaderMaterial
var cross: Control
var ammo: Label
var reserve: Label
var hp_bar: ColorRect
var hp_back: ColorRect
var hp_num: Label
var obj: Label
var obj_sub: Label
var toast: Label
var score: Label
var prompt: Label
var card: Control
var card_sub: Label
var toast_t := -9.0
var f_semi: FontFile
var f_med: FontFile
var f_neon: FontFile
var cyan := Color(0.35, 0.95, 1.0)
var pink := Color(1.0, 0.25, 0.6)

func _label(parent: Control, font: FontFile, size: int, col: Color, anchor: int, off: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new(); l.add_theme_font_override("font", font); l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6)); l.add_theme_constant_override("shadow_offset_x", 2); l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l); l.set_anchors_and_offsets_preset(anchor)
	l.position += off
	return l

func setup(g: Game, lens := true) -> void:
	game = g; layer = 5
	f_semi = load("res://assets/fonts/Rajdhani-SemiBold.ttf"); f_med = load("res://assets/fonts/Rajdhani-Medium.ttf"); f_neon = load("res://assets/fonts/Monoton-Regular.ttf")
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(root)
	post = ColorRect.new(); post.set_anchors_preset(Control.PRESET_FULL_RECT); post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pm = ShaderMaterial.new(); pm.shader = load("res://game/post.gdshader"); post.material = pm; post.visible = lens; root.add_child(post)
	cross = Control.new(); cross.set_anchors_preset(Control.PRESET_FULL_RECT); cross.mouse_filter = Control.MOUSE_FILTER_IGNORE; cross.draw.connect(_draw_cross); root.add_child(cross)
	ammo = _label(root, f_semi, 76, Color.WHITE, Control.PRESET_BOTTOM_RIGHT, Vector2(-250, -128), HORIZONTAL_ALIGNMENT_RIGHT); ammo.custom_minimum_size = Vector2(120, 0)
	reserve = _label(root, f_med, 34, Color(1, 1, 1, 0.65), Control.PRESET_BOTTOM_RIGHT, Vector2(-118, -92))
	hp_back = ColorRect.new(); hp_back.color = Color(0, 0, 0, 0.45); hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(hp_back)
	hp_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT); hp_back.position += Vector2(48, -66); hp_back.size = Vector2(300, 10)
	hp_bar = ColorRect.new(); hp_bar.color = cyan; hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE; hp_back.add_child(hp_bar); hp_bar.size = Vector2(300, 10)
	hp_num = _label(root, f_semi, 40, Color.WHITE, Control.PRESET_BOTTOM_LEFT, Vector2(48, -128))
	obj = _label(root, f_semi, 30, Color.WHITE, Control.PRESET_TOP_LEFT, Vector2(48, 36))
	obj_sub = _label(root, f_med, 24, cyan, Control.PRESET_TOP_LEFT, Vector2(48, 72))
	score = _label(root, f_med, 24, Color(1, 1, 1, 0.7), Control.PRESET_TOP_RIGHT, Vector2(-330, 36), HORIZONTAL_ALIGNMENT_RIGHT); score.custom_minimum_size = Vector2(280, 0)
	toast = _label(root, f_semi, 40, Color.WHITE, Control.PRESET_CENTER, Vector2(-400, 150), HORIZONTAL_ALIGNMENT_CENTER); toast.custom_minimum_size = Vector2(800, 0)
	prompt = _label(root, f_med, 28, cyan, Control.PRESET_CENTER, Vector2(-300, 70), HORIZONTAL_ALIGNMENT_CENTER); prompt.custom_minimum_size = Vector2(600, 0)
	# title / pause card
	card = ColorRect.new(); (card as ColorRect).color = Color(0.01, 0.015, 0.03, 0.72); card.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(card)
	var title := _label(card, f_neon, 150, pink, Control.PRESET_CENTER, Vector2(-600, -300), HORIZONTAL_ALIGNMENT_CENTER); title.custom_minimum_size = Vector2(1200, 0); title.text = "HALCYON"
	card_sub = _label(card, f_med, 30, Color(1, 1, 1, 0.9), Control.PRESET_CENTER, Vector2(-600, -90), HORIZONTAL_ALIGNMENT_CENTER); card_sub.custom_minimum_size = Vector2(1200, 0)
	card_sub.text = "Gunmen hold the hotel. Find each guest upstairs and walk them out.\nOnly shoot who is armed: look at the hands, not the clothes.\n\nWASD move    SHIFT run    MOUSE look    LEFT fire    RIGHT aim\nR reload    E come with me    F torch    ESC pause    F11 full screen\n\nCLICK TO PLAY"
	card.visible = false

func msg(s: String) -> void:
	toast.text = s; toast_t = game.t

func show_card(v: bool) -> void: card.visible = v

func _draw_cross() -> void:
	if card.visible: return
	var c := cross.size / 2.0; var p := game.player
	var gap := 6.0 + game.spread() * 9.0 * (1.0 - 0.5 * p.ads)
	var col := Color(1, 1, 1, 0.85 * (1.0 - 0.6 * p.ads))
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		cross.draw_line(c + d * gap, c + d * (gap + 9.0), col, 2.0, true)
	cross.draw_circle(c, 1.6, Color(1, 1, 1, 0.9))
	var hm := 1.0 - (game.t - game.hit_mark_t) * 5.0
	if hm > 0.0:
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			cross.draw_line(c + d * 7.0, c + d * (13.0 + 4.0 * hm), Color(1.0, 0.35, 0.3, hm), 2.5, true)

func update(_dt: float) -> void:
	var p := game.player
	ammo.text = "%d" % p.ammo if p.reload_t < 0.0 else "··"
	ammo.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if p.ammo <= 3 else Color.WHITE)
	reserve.text = "/ %d" % p.reserve
	hp_bar.size.x = 300.0 * clampf(p.hp / 100.0, 0.0, 1.0); hp_bar.color = cyan if p.hp > 40.0 else Color(1.0, 0.3, 0.25)
	hp_num.text = "%d" % int(ceil(maxf(0.0, p.hp)))
	score.text = "OUT %d    WRONG %d" % [game.score["rescued"], game.score["wrong"]]
	var o = game.objective
	prompt.text = ""
	if o:
		var find: bool = o["phase"] == "find"
		var g: Actor = o["guest"]
		var tgt := g.pos if find else (Vector3(0, 0, Plan.Z0 + 1.0) if o["exit"] == "front" else Vector3(0, 0, 31.0))
		var tl := g.L if find else 0
		var d := Vector2(tgt.x - p.pos.x, tgt.z - p.pos.z).length()
		var rel := wrapf(atan2(-(tgt.x - p.pos.x), -(tgt.z - p.pos.z)) - p.yaw, -PI, PI)
		var arrow := "▲" if absf(rel) < 0.4 else ("◀" if rel > 0.0 and absf(rel) < 2.4 else ("▶" if rel < 0.0 and absf(rel) < 2.4 else "▼"))
		var fl := "" if tl == p.L else ("   UP %d" % (tl - p.L) if tl > p.L else "   DOWN %d" % (p.L - tl))
		obj.text = ("FIND THE GUEST  ·  %s" % String(o["name"]).to_upper()) if find else ("WALK THEM OUT  ·  %s" % ("FRONT DOORS" if o["exit"] == "front" else "POOL TERRACE"))
		obj_sub.text = "%s  %d m%s" % [arrow, int(d), fl]
		if find and g.L == p.L and d < 2.6: prompt.text = "E   COME WITH ME"
	else:
		obj.text = ""; obj_sub.text = ""
	var ta := clampf(1.0 - (game.t - toast_t - 2.2) * 2.0, 0.0, 1.0)
	toast.modulate = Color(1, 1, 1, ta)
	pm.set_shader_parameter("hurt", clampf(1.0 - (game.t - game.hurt_t) * 2.0, 0.0, 1.0))
	pm.set_shader_parameter("low", clampf((45.0 - p.hp) / 45.0, 0.0, 1.0))
	pm.set_shader_parameter("dark", 1.0 if game.power < 0.5 else 0.0)
	cross.queue_redraw()
