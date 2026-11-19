class_name Level
extends Node3D
## The hotel: the exported building mesh with PBR materials, fixtures and furniture, real lights,
## the sky, the sun, the sea and the grounds. Everything here is looks; the walkable plan lives in Plan.

const TEX := "res://assets/textures/"
const MODELS := "res://assets/models/"
const LAMP_COL := Color(1.0, 0.92, 0.8)
const OPEN_KINDS := ["lobby", "gallery", "stair"]
# sun: low over the sea to the north-west (matches the sky panorama turned by PI)
const SUN_ELEV := 19.2
const SUN_DIR := Vector3(-0.59, 0.0, 0.81)

var quality := "high"            # "high" for play, "scan" for the software-rendered harness
var env: Environment
var sun: DirectionalLight3D
var cam_attr: CameraAttributesPractical
var lamps: Array = []            # {node, L, open, e, fixture, pos}
var emerg: Array = []            # red emergency lights (on in a blackout)
var props: Array = []            # {node, L, open}
var door_recs: Array = []        # {door, leaves:[node], y0:[float], lamps:[node], k}
var bulb_mat: StandardMaterial3D
var door_mats: Array = []
var power := 1.0                 # eased lamp level
var power_target := 1.0
var windows: Array = []          # {L, x, y, z, nx, nz}
var _light_cache := {}
var _view_L := -99
var _view_ramp := false
var _mat_cache := {}
var signs: Array = []
var strip_mats := {}
var t := 0.0
var amb_base := 0.8        # ambient energy when there is no GI bounce (the light preset)

func build(q := "high") -> void:
	quality = q
	var raw := Plan.raw
	var native := not raw.has("surfaces")     # a level made by LevelGen: geometry comes from the plan
	_build_env()
	if native: _build_native()
	else: _build_surfaces(raw)
	_build_doors(raw)
	_build_lamps(raw)
	_build_props(raw)
	if native: _build_native_outside()
	else:
		_build_exterior()
		_build_signs()
	_find_windows()

## For the headless simulations: only what light_at needs (the lamp list and the windows), nothing drawn.
func lamps_only(raw: Dictionary) -> void:
	for l in raw["lamps"]:
		var fx: String = l["fixture"]
		var dy := -0.65 if fx == "ceiling" else (-0.1 if fx == "sconce" or fx == "wallsconce" else -0.5)
		lamps.append({"node": null, "L": int(l["L"]), "open": false, "e": float(l["I"]), "I": float(l["I"]), "fixture": fx, "pos": Vector3(l["x"], float(l["y"]) + dy, l["z"]), "room": int(l["room"])})
	_find_windows()

# ---------------------------------------------------------------------------------------- sky, sun, post
func _build_env() -> void:
	env = Environment.new()
	var sky := Sky.new(); var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/hdri/qwantani_late_afternoon_puresky.hdr"); pm.energy_multiplier = 0.32   # dusk: the sky keeps its colour, the lamps and the neon carry the light
	sky.sky_material = pm; sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY; env.sky = sky; env.sky_rotation = Vector3(0, PI, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = 4 if ClassDB.class_has_enum("Environment", "ToneMapper") else Environment.TONE_MAPPER_FILMIC   # AgX
	env.tonemap_exposure = 1.0; env.tonemap_white = 6.0
	var hi := quality == "high"
	env.ambient_light_energy = 0.9 if hi else 0.8
	env.sdfgi_enabled = hi
	env.sdfgi_use_occlusion = true; env.sdfgi_read_sky_light = true; env.sdfgi_bounce_feedback = 0.45
	env.sdfgi_cascades = 4; env.sdfgi_min_cell_size = 0.25; env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_energy = 1.0; env.sdfgi_normal_bias = 1.1; env.sdfgi_probe_bias = 1.1
	env.ssao_enabled = true; env.ssao_radius = 1.2; env.ssao_intensity = 2.2; env.ssao_power = 1.6; env.ssao_light_affect = 0.25 if hi else 0.6
	env.ssil_enabled = hi; env.ssil_radius = 4.0; env.ssil_intensity = 1.2
	env.ssr_enabled = hi; env.ssr_max_steps = 56; env.ssr_fade_in = 0.15; env.ssr_fade_out = 2.0; env.ssr_depth_tolerance = 0.3
	env.glow_enabled = true; env.glow_intensity = 0.55; env.glow_strength = 1.0; env.glow_bloom = 0.02; env.glow_hdr_threshold = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.2); env.set_glow_level(2, 0.6); env.set_glow_level(3, 0.9); env.set_glow_level(4, 0.7); env.set_glow_level(5, 0.5); env.set_glow_level(6, 0.3)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0045; env.volumetric_fog_albedo = Color(0.92, 0.9, 0.86); env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 70.0; env.volumetric_fog_detail_spread = 2.0; env.volumetric_fog_gi_inject = 0.6; env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_temporal_reprojection_enabled = hi; env.volumetric_fog_sky_affect = 0.25
	env.adjustment_enabled = true; env.adjustment_contrast = 1.06; env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	cam_attr = CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = true; cam_attr.auto_exposure_scale = 0.2; cam_attr.auto_exposure_speed = 1.6
	cam_attr.auto_exposure_min_sensitivity = 90.0; cam_attr.auto_exposure_max_sensitivity = 260.0
	we.camera_attributes = cam_attr
	sun = DirectionalLight3D.new()
	var el := deg_to_rad(SUN_ELEV); var sd := Vector3(SUN_DIR.x * cos(el), sin(el), SUN_DIR.z * cos(el)).normalized()
	add_child(sun)
	sun.look_at_from_position(sd * 100.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.72, 0.5); sun.light_energy = 1.3; sun.light_angular_distance = 0.6
	sun.shadow_enabled = true; sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0; sun.shadow_bias = 0.04; sun.shadow_normal_bias = 1.2; sun.directional_shadow_blend_splits = true
	sun.light_volumetric_fog_energy = 1.6
	sun.light_bake_mode = Light3D.BAKE_STATIC
	var sk: String = Plan.meta.get("sky", "dusk")
	if sk == "day":        # the gardens: a bright late afternoon
		pm.energy_multiplier = 1.0; sun.light_energy = 3.0; sun.light_color = Color(1.0, 0.86, 0.68)
		env.ambient_light_energy = 1.0; amb_base = 1.0; env.volumetric_fog_density = 0.003; cam_attr.auto_exposure_scale = 0.24
	elif sk == "none":     # the service level: no daylight at all, cold tube light, murky air
		pm.energy_multiplier = 0.02; sun.light_energy = 0.0; sun.shadow_enabled = false; sun.light_volumetric_fog_energy = 0.0
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.55, 0.62, 0.7)
		env.ambient_light_energy = 0.22; amb_base = 0.22; env.volumetric_fog_density = 0.011; env.volumetric_fog_albedo = Color(0.8, 0.86, 0.9)

# ---------------------------------------------------------------------------------------- materials
func tex(name: String, kind: String) -> Texture2D:
	var p := TEX + name + "/" + kind + ".jpg"
	return load(p) if ResourceLoader.exists(p) else null

func surf_mat(name: String, color := Color.WHITE, uv := Vector3.ONE) -> StandardMaterial3D:
	var key := name + color.to_html() + str(uv)
	if _mat_cache.has(key): return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name, "diff"); m.albedo_color = color
	var n := tex(name, "nor")
	if n: m.normal_enabled = true; m.normal_texture = n; m.normal_scale = 1.0
	var r := tex(name, "rough")
	if r: m.roughness_texture = r; m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.0; m.metallic = 0.0; m.metallic_specular = 0.5; m.uv1_scale = uv
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# polished floors: let the lamps and the neon lie on them
	if name in ["marble_tiles", "terrazzo_tiles"]: m.roughness = 0.28; m.uv1_scale = Vector3(0.5, 0.5, 1)
	if name in ["blue_floor_tiles_01", "grey_tiles"]: m.roughness = 0.5
	if name in ["herringbone_parquet", "diagonal_parquet"]: m.roughness = 0.75
	_mat_cache[key] = m
	return m

func plain(name: String) -> Material:
	if _mat_cache.has(name): return _mat_cache[name]
	var m := StandardMaterial3D.new()
	match name:
		"trim": m.albedo_color = Color(0.86, 0.83, 0.76); m.roughness = 0.6
		"ceilTrim": m.albedo_color = Color(0.9, 0.88, 0.83); m.roughness = 0.75
		"brass": m.albedo_color = Color(0.83, 0.62, 0.3); m.metallic = 1.0; m.roughness = 0.28
		"steel": m.albedo_color = Color(0.55, 0.57, 0.6); m.metallic = 1.0; m.roughness = 0.38
		"dark": m.albedo_color = Color(0.05, 0.05, 0.055); m.metallic = 0.6; m.roughness = 0.45
		"glass":
			m.albedo_color = Color(0.75, 0.86, 0.9, 0.16); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.04; m.metallic = 0.0; m.metallic_specular = 0.9; m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.refraction_enabled = false
	_mat_cache[name] = m
	return m

# ---------------------------------------------------------------------------------------- the building
func _build_surfaces(raw: Dictionary) -> void:
	var bin := FileAccess.get_file_as_bytes("res://level/level.bin")
	var solid := ArrayMesh.new(); var glass := ArrayMesh.new()
	for s in raw["surfaces"]:
		var nv := int(s["nv"])
		var pf := bin.slice(int(s["pos"][0]), int(s["pos"][0]) + nv * 12).to_float32_array()
		var nf := bin.slice(int(s["nrm"][0]), int(s["nrm"][0]) + nv * 12).to_float32_array()
		var uf := bin.slice(int(s["uv"][0]), int(s["uv"][0]) + nv * 8).to_float32_array()
		var ix := bin.slice(int(s["idx"][0]), int(s["idx"][0]) + int(s["ni"]) * 4).to_int32_array()
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in nv:
			st.set_normal(Vector3(nf[v * 3], nf[v * 3 + 1], nf[v * 3 + 2])); st.set_uv(Vector2(uf[v * 2], uf[v * 2 + 1]))
			st.add_vertex(Vector3(pf[v * 3], pf[v * 3 + 1], pf[v * 3 + 2]))
		for q in range(0, ix.size(), 3):   # three.js winds counter-clockwise, Godot clockwise
			st.add_index(ix[q]); st.add_index(ix[q + 2]); st.add_index(ix[q + 1])
		st.generate_tangents()
		var md: Dictionary = s["mat"]
		var is_glass: bool = md.get("name", "") == "glass"
		var mat: Material = surf_mat(md["tex"], Color.hex((int(md["color"]) << 8) | 0xff)) if md.has("tex") else plain(md["name"])
		var target := glass if is_glass else solid
		st.commit(target); target.surface_set_material(target.get_surface_count() - 1, mat)
	var mi := MeshInstance3D.new(); mi.mesh = solid; mi.name = "Building"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED; mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(mi)
	var gi := MeshInstance3D.new(); gi.mesh = glass; gi.name = "Glass"; gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(gi)
	# the atrium's glass roof sits in a steel lattice: its shadow falls across the galleries
	var lat := Node3D.new(); lat.name = "Lattice"; add_child(lat)
	for n in range(-4, 5):
		_box(lat, Vector3(n * 2.0, 12.42, 0), Vector3(0.1, 0.22, 16.2), plain("steel"))
		if n % 2 == 0: _box(lat, Vector3(0, 12.44, n * 2.0), Vector3(16.2, 0.26, 0.14), plain("steel"))

func _box(parent: Node, pos: Vector3, size: Vector3, mat: Material, shadow := true) -> MeshInstance3D:
	var m := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = size; m.mesh = b; m.material_override = mat; m.position = pos
	if not shadow: m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m); return m

func _build_doors(raw: Dictionary) -> void:
	var leaf := StandardMaterial3D.new(); leaf.albedo_color = Color(0.32, 0.34, 0.37); leaf.metallic = 0.9; leaf.roughness = 0.42
	for d in raw["doors"]:
		var rec := {"door": Plan.doors[int(d["id"])], "leaves": [], "y0": [], "lamps": [], "k": 1.0, "mat": null}
		for lf in d["leaves"]:
			var m := _box(self, Vector3(lf[0], lf[1], lf[2]), Vector3(1.22, 2.3, 0.08), leaf); m.rotation.y = lf[3]
			# hazard stripe band
			var band := _box(m, Vector3(0, -0.2, 0), Vector3(1.23, 0.16, 0.085), plain("brass"), false)
			rec["leaves"].append(m); rec["y0"].append(float(lf[1]))
		var lm := StandardMaterial3D.new(); lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; lm.albedo_color = Color(0.2, 1.0, 0.4) * 3.0
		rec["mat"] = lm
		for lp in d["lamps"]:
			var m2 := _box(self, Vector3(lp[0], lp[1], lp[2]), Vector3(0.18, 0.08, 0.04), lm, false); m2.rotation.y = lp[3]
			rec["lamps"].append(m2)
		door_recs.append(rec)

func step_doors(dt: float) -> void:
	for rec in door_recs:
		var tgt := 1.0 if rec["door"]["open"] else 0.0
		if absf(rec["k"] - tgt) < 0.001 and rec.has("done") and rec["done"] == tgt: continue
		rec["k"] = lerpf(rec["k"], tgt, minf(1.0, dt * 5.0))
		if absf(rec["k"] - tgt) < 0.001: rec["k"] = tgt; rec["done"] = tgt
		for n in rec["leaves"].size():
			var m: MeshInstance3D = rec["leaves"][n]
			m.position.y = rec["y0"][n] + rec["k"] * 2.2; m.visible = rec["k"] < 0.98
		(rec["mat"] as StandardMaterial3D).albedo_color = (Color(0.2, 1.0, 0.4) if rec["door"]["open"] else Color(1.0, 0.16, 0.1)) * 3.0

# ---------------------------------------------------------------------------------------- lamps
func _build_lamps(raw: Dictionary) -> void:
	var hi := quality == "high"
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new(); sph.radius = 0.07; sph.height = 0.14; sph.radial_segments = 12; sph.rings = 6
	bulb_mat = StandardMaterial3D.new(); bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; bulb_mat.albedo_color = Color(1.0, 0.85, 0.6) * 5.0
	sph.material = bulb_mat; mm.mesh = sph; mm.instance_count = raw["lamps"].size()
	var n := 0
	for l in raw["lamps"]:
		var fx: String = l["fixture"]; var L := int(l["L"]); var I: float = l["I"]
		var rk := "" if int(l["room"]) < 0 else String(Plan.rooms[int(l["room"])]["kind"])
		var open := fx == "chandelier" or fx == "sconce" or fx == "wallsconce" or rk in OPEN_KINDS
		var dy := -0.65 if fx == "ceiling" else (-0.1 if fx == "sconce" or fx == "wallsconce" or fx == "tube" else (0.0 if fx == "post" else -0.5))
		var pos := Vector3(l["x"], float(l["y"]) + dy, l["z"])
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.001 if fx == "tube" else (2.2 if fx == "post" else 1.0))), pos)); n += 1
		if fx == "tube":
			var tb := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.25, 0.05, 0.11); tb.mesh = bm; tb.material_override = bulb_mat
			tb.position = pos + Vector3(0, 0.07, 0); tb.rotation.y = PI / 2 if Plan.passable(L, Plan.ci(pos.x), Plan.ck(pos.z), "N") and not Plan.passable(L, Plan.ci(pos.x), Plan.ck(pos.z), "E") else 0.0
			tb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(tb)
		var node: Light3D
		if fx == "ceiling" and open:
			var sp := SpotLight3D.new(); sp.spot_range = 9.0; sp.spot_angle = 82.0; sp.spot_angle_attenuation = 0.5; sp.spot_attenuation = 1.2
			sp.rotation.x = -PI / 2; node = sp; node.light_energy = I * 5.5
		else:
			var om := OmniLight3D.new(); om.omni_attenuation = 1.3
			om.omni_range = 22.0 if fx == "chandelier" else (11.0 if fx == "chandelier3" else (6.5 if fx != "ceiling" else 8.5))
			if fx == "tube": om.omni_range = 7.5
			elif fx == "post": om.omni_range = 13.0
			node = om; node.light_energy = I * (1.4 if fx == "chandelier" else (1.5 if fx == "chandelier3" else (2.2 if fx == "ceiling" else (2.6 if fx == "tube" else (3.0 if fx == "post" else 4.5)))))
		node.position = pos + Vector3(0, -0.06, 0)
		node.light_color = Color(0.8, 0.92, 1.0) if fx == "tube" else (LAMP_COL if fx != "chandelier" else Color(1.0, 0.86, 0.68))
		node.light_specular = 0.6; node.shadow_enabled = false; node.shadow_bias = 0.06; node.shadow_normal_bias = 1.5
		node.light_volumetric_fog_energy = 2.0
		node.distance_fade_enabled = true; node.distance_fade_begin = 38.0; node.distance_fade_length = 8.0; node.distance_fade_shadow = 22.0
		node.light_bake_mode = Light3D.BAKE_STATIC
		add_child(node)
		lamps.append({"node": node, "L": L, "open": open, "e": node.light_energy, "I": I, "fixture": fx, "pos": pos, "room": int(l["room"])})
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; mmi.name = "Bulbs"
	add_child(mmi)
	# emergency lighting: red battery lamps at both ends of every flight and over the ways out
	var spots: Array = []
	for r in Plan.ramps:
		var ln: Array = r["lane"]
		var mx := (Plan.cx(ln[0]) + Plan.cx(ln[2])) / 2.0; var mz := (Plan.cz(ln[1]) + Plan.cz(ln[3])) / 2.0
		var half := float(r["len"]) / 2.0 + 1.0
		for e: float in [-1.0, 1.0]:
			var up := e * float(r["dir"]) > 0.0
			var p := Vector3(mx, (r["L"] + (1 if up else 0)) * Plan.LH + 2.7, mz)
			if r["along_k"]: p.z += e * half
			else: p.x += e * half
			spots.append(p)
	if Plan.meta["name"] == "hotel":
		spots.append(Vector3(0, 2.9, Plan.Z0 + 1.2)); spots.append(Vector3(0, 2.9, 19.0)); spots.append(Vector3(-12, 2.9, 0)); spots.append(Vector3(12, 2.9, 0))
	else:
		for ex: Dictionary in (Plan.meta["exits"] as Dictionary).values():
			var nd: Array = ex["nodes"][0]; spots.append(Vector3(Plan.cx(nd[1]), nd[0] * Plan.LH + 2.9, Plan.cz(nd[2])))
	var em := StandardMaterial3D.new(); em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; em.albedo_color = Color(0.25, 0.02, 0.02)
	for p in spots:
		var o := OmniLight3D.new(); o.position = p; o.light_color = Color(1.0, 0.12, 0.08); o.light_energy = 0.0; o.omni_range = 9.0; o.omni_attenuation = 1.1
		o.light_volumetric_fog_energy = 2.0; o.visible = false; add_child(o)
		var b := _box(self, p + Vector3(0, 0.12, 0), Vector3(0.22, 0.1, 0.22), em, false)
		emerg.append({"node": o, "box": b, "L": int(floor((p.y - 1.0) / Plan.LH))})
	emerg_mat = em

var emerg_mat: StandardMaterial3D

func set_power(on: bool) -> void: power_target = 1.0 if on else 0.0

## Per frame: ease the power, hide lamps on floors you cannot see, give shadows to the nearest lamps.
func step(dt: float, L: int, on_ramp: bool, eye: Vector3) -> void:
	t += dt
	step_doors(dt)
	var changed := false
	if absf(power - power_target) > 0.001:
		# lamps die in a flicker and come back with a slow strike
		power = move_toward(power, power_target, dt * (2.5 if power_target < power else 1.2)); changed = true
	if L != _view_L or on_ramp != _view_ramp: changed = true; _view_L = L; _view_ramp = on_ramp
	var flick := 1.0
	if power < 0.999 and power > 0.02: flick = 0.55 + 0.45 * signf(sin(t * 47.0) + sin(t * 31.0) + 0.6); changed = true
	if changed:
		var lv := power * flick
		for r in lamps:
			var vis: bool = lv > 0.01 and (r["open"] or r["L"] == L or (on_ramp and absi(r["L"] - L) <= 1))
			var nd: Light3D = r["node"]
			nd.visible = vis; nd.light_energy = r["e"] * lv
		bulb_mat.albedo_color = Color(1.0, 0.85, 0.6) * (0.03 + 4.97 * lv)
		var ev := 1.0 - power
		for r in emerg:
			var nd2: OmniLight3D = r["node"]
			nd2.visible = ev > 0.02 and absi(r["L"] - L) <= 1; nd2.light_energy = 1.4 * ev
		emerg_mat.albedo_color = Color(0.25, 0.02, 0.02).lerp(Color(4.0, 0.25, 0.15), ev)
		for r in props:
			(r["node"] as Node3D).visible = r["open"] or r["L"] == L or (on_ramp and absi(r["L"] - L) <= 1)
		for s in signs: s["light"].light_energy = s["e"] * (0.25 + 0.75 * power)
		# without the GI bounce (the light preset) the sky's ambient stands in for it indoors, and dies with the lamps
		if not env.sdfgi_enabled: env.ambient_light_energy = amb_base * (0.12 + 0.88 * power)
	if quality == "high" and Engine.get_frames_drawn() % 6 == 0: _shadow_budget(eye)

func _shadow_budget(eye: Vector3) -> void:
	var near: Array = []
	for r in lamps:
		var nd: Light3D = r["node"]
		if not nd.visible: nd.shadow_enabled = false; continue
		near.append([eye.distance_squared_to(r["pos"]), nd])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for n in near.size(): (near[n][1] as Light3D).shadow_enabled = n < 8

# ---------------------------------------------------------------------------------------- furniture
static func scene_aabb(node: Node, xf := Transform3D.IDENTITY, acc: Array = []) -> AABB:
	var top := acc.is_empty()
	if top: acc.append(null)
	var x := xf
	if node is Node3D and not top: x = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var a: AABB = x * (node as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in node.get_children(): scene_aabb(c, x, acc)
	return acc[0] if acc[0] != null else AABB()

func _build_props(raw: Dictionary) -> void:
	var packs := {}; var boxes := {}
	var bed_fab := surf_mat("quatrefoil_jacquard_fabric", Color(0.91, 0.88, 0.82)); var bed_wood := StandardMaterial3D.new(); bed_wood.albedo_color = Color(0.23, 0.15, 0.09); bed_wood.roughness = 0.6
	for q in raw["place"]:
		var name: String = q[0]; var L := int(q[1]); var rot: float = q[4]; var sc: float = q[6] if q[6] != null else 1.0
		var y: float = L * Plan.LH if q[5] == null else float(q[5])
		var ri := Plan.room_at(L, Plan.ci(q[2]), Plan.ck(q[3]))
		var open: bool = ri < 0 or String(Plan.rooms[ri]["kind"]) in OPEN_KINDS or name.contains("Chandelier_01") or name.contains("sconce") or Plan.NL == 1
		var base := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * sc), Vector3(q[2], y, q[3]))
		var node: Node3D
		if name.begins_with("__") and name != "__bed":
			node = _special(name, q); node.transform = base * node.transform if name != "__pipe" else node.transform
			open = Plan.NL == 1
		elif name == "__bed":
			node = Node3D.new()
			_box(node, Vector3(0, 0.38, 0), Vector3(1.7, 0.55, 2.1), bed_fab); _box(node, Vector3(0, 0.6, -1.05), Vector3(1.8, 1.1, 0.12), bed_wood)
			_box(node, Vector3(-0.4, 0.72, -0.7), Vector3(0.62, 0.14, 0.4), bed_fab); _box(node, Vector3(0.4, 0.72, -0.7), Vector3(0.62, 0.14, 0.4), bed_fab)
			node.transform = base
		else:
			if not packs.has(name):
				var ps: PackedScene = load(MODELS + name + "/" + name + ".gltf")
				packs[name] = ps
				if ps: var tmp := ps.instantiate(); boxes[name] = scene_aabb(tmp); tmp.free()
			if packs[name] == null: continue
			node = (packs[name] as PackedScene).instantiate()
			var bb: AABB = boxes[name]
			var hang := (name.contains("lamp") or name.contains("Chandelier")) and not name.contains("sconce")
			var wall := name.contains("frame") or name.contains("mirror") or name.contains("clock") or name.contains("lifebuoy") or name.contains("sconce")
			var off := -bb.end.y if hang else (-(bb.position.y + bb.end.y) / 2.0 if wall else -bb.position.y)
			node.transform = base * Transform3D(Basis.IDENTITY, Vector3(0, off, 0)) * node.transform
			var small := maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) * sc < 0.8
			_prop_setup(node, hang or name.contains("sconce"), 30.0 if small else 70.0)
		add_child(node)
		props.append({"node": node, "L": L, "open": open})

func _prop_setup(n: Node, is_lamp: bool, far: float) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.visibility_range_end = far; g.visibility_range_end_margin = 4.0; g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if is_lamp: g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC if not is_lamp else GeometryInstance3D.GI_MODE_DISABLED
		g.lod_bias = 1.0
	for c in n.get_children(): _prop_setup(c, is_lamp, far)

# ---------------------------------------------------------------------------------------- outside
func _build_exterior() -> void:
	var xa := Plan.X0; var xb := Plan.X0 + Plan.NX * Plan.C; var za := Plan.Z0; var zt := Plan.Z0 + Plan.NZ * Plan.C
	_ground("cobblestone_floor_08", xb - xa + 24.0, 14.0, (xa + xb) / 2.0, za - 7.0, 3.0, -0.02)
	_ground("asphalt_02", 400.0, 12.0, 0.0, za - 20.0, 6.0, -0.04)
	_ground("cobblestone_floor_08", 12.0, zt - za + 14.0, xa - 6.0, (za + zt) / 2.0 - 7.0, 3.0, -0.02)
	_ground("cobblestone_floor_08", 12.0, zt - za + 14.0, xb + 6.0, (za + zt) / 2.0 - 7.0, 3.0, -0.02)
	var grass := StandardMaterial3D.new(); grass.albedo_color = Color(0.2, 0.25, 0.11); grass.roughness = 0.95
	for g in [[160.0, zt - za + 40.0, xa - 92.0, (za + zt) / 2.0 - 20.0], [160.0, zt - za + 40.0, xb + 92.0, (za + zt) / 2.0 - 20.0], [400.0, 160.0, 0.0, za - 106.0]]:
		var m := MeshInstance3D.new(); var pl := PlaneMesh.new(); pl.size = Vector2(g[0], g[1]); m.mesh = pl; m.material_override = grass; m.position = Vector3(g[2], -0.05, g[3]); add_child(m)
	# the cliff under the terrace: a rough rock face down to the sea
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var W := 120; var H := 12
	for j in H + 1:
		for i in W + 1:
			var x := -200.0 + 400.0 * i / W; var y := 0.0 - 34.0 * j / H
			var out := sin(x * 0.7) * 0.8 + sin(x * 0.23 + y) * 1.6 + rng.randf_range(-0.4, 0.4) + (-y) * 0.25
			st.set_uv(Vector2(x * 0.1, y * 0.1)); st.add_vertex(Vector3(x, y, zt + 0.2 + out))
	for j in H:
		for i in W:
			var a := j * (W + 1) + i; var b := a + 1; var c := a + W + 1; var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c); st.add_index(b); st.add_index(d); st.add_index(c)
	st.generate_normals(); var rock := StandardMaterial3D.new(); rock.albedo_color = Color(0.3, 0.26, 0.22); rock.roughness = 1.0
	var cm := MeshInstance3D.new(); cm.mesh = st.commit(); cm.material_override = rock; add_child(cm)
	# the sea
	var sea := MeshInstance3D.new(); var sp := PlaneMesh.new(); sp.size = Vector2(6000, 6000); sp.subdivide_width = 1; sp.subdivide_depth = 1; sea.mesh = sp
	var sm := ShaderMaterial.new(); sm.shader = load("res://game/sea.gdshader"); sea.material_override = sm; sea.position = Vector3(0, -30, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; sea.gi_mode = GeometryInstance3D.GI_MODE_DISABLED; add_child(sea)

func _ground(name: String, w: float, d: float, x: float, z: float, rep: float, y: float) -> void:
	var m := MeshInstance3D.new(); var pl := PlaneMesh.new(); pl.size = Vector2(w, d); m.mesh = pl
	m.material_override = surf_mat(name, Color.WHITE, Vector3(w / rep, d / rep, 1)); m.position = Vector3(x, y, z); add_child(m)

# ---------------------------------------------------------------------------------------- neon and signs
func neon(text: String, pos: Vector3, rot_y: float, col: Color, size := 0.6, font_name := "TiltNeon", light := 2.0) -> void:
	var l := Label3D.new(); l.text = text; l.font = load("res://assets/fonts/" + font_name + ".ttf"); l.font_size = 160; l.pixel_size = size / 160.0
	l.modulate = col * 3.2; l.outline_size = 0; l.shaded = false; l.double_sided = true; l.no_depth_test = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED; l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.position = pos; l.rotation.y = rot_y; add_child(l)
	var o := OmniLight3D.new(); o.light_color = col; o.light_energy = light; o.omni_range = 7.0 + size * 4.0; o.omni_attenuation = 1.4
	o.position = pos + Vector3(sin(rot_y), 0, cos(rot_y)) * 1.3; o.light_volumetric_fog_energy = 0.4; o.light_specular = 1.0; add_child(o)
	signs.append({"label": l, "light": o, "e": light, "col": col})

func _build_signs() -> void:
	var pink := Color(1.0, 0.16, 0.55); var cyan := Color(0.1, 0.9, 1.0); var amber := Color(1.0, 0.6, 0.12); var green := Color(0.15, 1.0, 0.45)
	var zf := Plan.Z0
	neon("HALCYON", Vector3(0, 5.6, zf - 0.35), PI, pink, 1.9, "Monoton-Regular", 6.0)          # over the front doors, facing the street
	neon("HALCYON", Vector3(0, 2.75, zf + 8.0 - 0.14), PI, cyan, 0.7, "TiltNeon", 2.5)  # behind the reception desk, facing the lobby... seen from the doors
	neon("BAR", Vector3(-12.2, 2.75, -9.0), PI / 2, pink, 0.55, "TiltNeon", 2.2)
	neon("LIBRARY", Vector3(-12.2, 2.75, 9.0), PI / 2, amber, 0.4, "TiltNeon", 1.4)
	neon("TERRACE", Vector3(0, 2.8, 19.8), PI, cyan, 0.5, "TiltNeon", 2.0)
	neon("EXIT", Vector3(0, 2.85, zf + 0.4), 0, green, 0.34, "Rajdhani-SemiBold", 1.2)
	neon("EXIT", Vector3(0, 2.85, 20.4), 0, green, 0.34, "Rajdhani-SemiBold", 1.2)
	# light lines along the gallery edges: cyan on the first floor, magenta on the second
	var n := 0
	for key: int in Plan.edges:
		if Plan.edges[key] != Plan.RAIL: continue
		var k := (key >> 1) % 32 - 1; var i := ((key >> 1) / 32) % 32 - 1; var L := (key >> 1) / 1024
		if L == 0: continue
		var east := (key & 1) == 0
		var j := i + (1 if east else 0); var m := k + (0 if east else 1)
		var va := Plan.kind_at(L, i, k) == 2; var vb := Plan.kind_at(L, j, m) == 2
		if va == vb: continue
		var x := Plan.X0 + (i + 1) * Plan.C if east else Plan.cx(i); var z := Plan.cz(k) if east else Plan.Z0 + (k + 1) * Plan.C
		var col := cyan if L == 1 else pink
		if not strip_mats.has(L):
			var sm := StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; sm.albedo_color = col * 3.0; strip_mats[L] = sm
		var out := Vector3((1.0 if va else -1.0) * (-1.0 if east else 0.0), 0, (1.0 if va else -1.0) * (0.0 if east else -1.0))   # towards the void
		_box(self, Vector3(x, L * Plan.LH - 0.12, z) + out * 0.1, Vector3(0.05, 0.05, 2.0) if east else Vector3(2.0, 0.05, 0.05), strip_mats[L], false)
		n += 1
		if n % 3 == 0:
			var o := OmniLight3D.new(); o.light_color = col; o.light_energy = 1.1; o.omni_range = 6.0; o.omni_attenuation = 1.3; o.light_specular = 1.0
			o.position = Vector3(x, L * Plan.LH - 0.3, z) + out * 0.5; o.light_volumetric_fog_energy = 0.6; add_child(o)
			signs.append({"label": null, "light": o, "e": 1.1, "col": col})

# ---------------------------------------------------------------------------------------- light level
func _find_windows() -> void:
	for key: int in Plan.edges:
		var ty: int = Plan.edges[key]
		if ty != Plan.WINDOW and ty != Plan.GLASS: continue
		var k := (key >> 1) % 32 - 1; var i := ((key >> 1) / 32) % 32 - 1; var L := (key >> 1) / 1024
		var east := (key & 1) == 0
		var x := Plan.X0 + (i + 1) * Plan.C if east else Plan.cx(i); var z := Plan.cz(k) if east else Plan.Z0 + (k + 1) * Plan.C
		var j := i + (1 if east else 0); var m := k + (0 if east else 1)
		var in_a := Plan.kind_at(L, i, k) == 1 and not Plan.outdoor_at(L, Plan.cx(i), Plan.cz(k))
		var in_b := Plan.kind_at(L, j, m) == 1 and not Plan.outdoor_at(L, Plan.cx(j), Plan.cz(m))
		if in_a == in_b: continue
		var s := -1.0 if in_a else 1.0   # normal points indoors
		windows.append({"L": L, "x": x, "y": L * Plan.LH + 1.8, "z": z, "nx": s if east else 0.0, "nz": 0.0 if east else s})

## Lamp light and daylight on a horizontal patch at a point (the regressor the models use for "how
## lit is this person"): [lamp, day]. Cached on a half-metre lattice.
func light_at(L: int, x: float, y: float, z: float) -> Vector2:
	var key := Vector3i(L * 1000 + int(round(x * 2.0)), int(round((y - L * Plan.LH) * 2.0)), int(round(z * 2.0)))
	if _light_cache.has(key): return _light_cache[key]
	var lamp := 0.012; var day := 0.0
	if Plan.outdoor_at(L, x, z): day = 1.6
	var i := Plan.ci(x); var k := Plan.ck(z)
	for r in lamps:
		var fx: String = r["fixture"]
		if r["L"] != L and not (fx == "chandelier" and i >= 8 and i <= 19 and k >= 4 and k <= 15): continue
		var p: Vector3 = r["pos"]
		var d2 := (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) + (p.z - z) * (p.z - z)
		if d2 > 220.0 or p.y <= y: continue
		var d := sqrt(d2); var c := (p.y - y) / d
		if fx != "chandelier" and not Plan.los(L, x, z, p.x, p.z): continue
		var I: float = r["I"]
		var down := 0.25 + 0.75 * pow(c, 1.5) if fx == "ceiling" else (0.6 + 0.4 * c if fx != "chandelier" and fx != "chandelier3" else 1.0)
		lamp += I * 2.1 * c * down / (1.0 + d2 * 1.05) + I * 0.07 / (1.0 + d2 * 0.12)
	for w in windows:
		if w["L"] != L: continue
		var dx: float = w["x"] - x; var dy: float = w["y"] - y; var dz: float = w["z"] - z
		var d2: float = dx * dx + dy * dy + dz * dz
		if d2 > 300.0: continue
		var d := sqrt(d2); var cs := maxf(0.15, dy / d); var cw: float = -(dx * float(w["nx"]) + dz * float(w["nz"])) / d
		if cw <= 0.0: continue
		if not Plan.los(L, x, z, w["x"] + w["nx"] * 0.2, w["z"] + w["nz"] * 0.2): continue
		day += 1.4 * cs * cw / (1.0 + d2 * 0.25)
	var v := Vector2(lamp, day)
	_light_cache[key] = v
	return v

# ---------------------------------------------------------------------------------------- generated levels
const N_FLOOR := {"field": "leafy_grass", "pavilion": "wood_floor_deck", "corridor": "concrete_floor_02", "stair": "concrete_floor_02", "boiler": "metal_plate", "plant": "metal_plate",
	"pump": "metal_plate", "workshop": "concrete_floor_02", "laundry": "floor_tiles_06", "kitchen": "floor_tiles_06", "cold": "floor_tiles_06", "locker": "floor_tiles_06"}
const N_WALL := {"pavilion": "white_plaster_rough_01", "corridor": "concrete_wall_008", "stair": "concrete_wall_008", "boiler": "brick_wall_001", "plant": "brick_wall_001", "pump": "brick_wall_001",
	"workshop": "brick_wall_001", "laundry": "grey_tiles", "kitchen": "grey_tiles", "cold": "grey_tiles", "locker": "grey_tiles"}
var _n_st := {}
var _n_cnt := {}

func _nst(name: String) -> SurfaceTool:
	if not _n_st.has(name):
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); _n_st[name] = st; _n_cnt[name] = 0
	return _n_st[name]

func _nquad(name: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, rep := 2.0) -> void:
	var st := _nst(name); var base: int = _n_cnt[name]
	for p: Vector3 in [p0, p1, p2, p3]:
		var uv := Vector2(p.x, p.z) if absf(n.y) > 0.5 else (Vector2(p.z, -p.y) if absf(n.x) > 0.5 else Vector2(p.x, -p.y))
		st.set_normal(n); st.set_uv(uv / rep); st.add_vertex(p)
	var flip := (p1 - p0).cross(p2 - p0).dot(n) > 0.0     # Godot's front faces wind clockwise
	for q: int in ([0, 2, 1, 0, 3, 2] if flip else [0, 1, 2, 0, 2, 3]): st.add_index(base + q)
	_n_cnt[name] = base + 4

func _nbox(name: String, c: Vector3, size: Vector3, rep := 2.0) -> void:
	var h := size / 2.0
	for ax in 3:
		for sg: float in [-1.0, 1.0]:
			var n := Vector3.ZERO; n[ax] = sg
			var u := Vector3.ZERO; u[(ax + 1) % 3] = h[(ax + 1) % 3]
			var v := Vector3.ZERO; v[(ax + 2) % 3] = h[(ax + 2) % 3]
			var o := c + n * h[ax]
			_nquad(name, o - u - v, o + u - v, o + u + v, o - u + v, n, rep)

## A piece of wall on an edge: from y0 to y1, between a and b along the edge (0..C), of a thickness.
func _nwall(name: String, east: bool, ex: float, ez: float, y0: float, y1: float, a: float, b: float, thick: float, rep := 2.0) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01: return
	var mid := (a + b) / 2.0 - Plan.C / 2.0
	var c := Vector3(ex, (y0 + y1) / 2.0, ez + mid) if east else Vector3(ex + mid, (y0 + y1) / 2.0, ez)
	_nbox(name, c, Vector3(thick, y1 - y0, b - a) if east else Vector3(b - a, y1 - y0, thick), rep)

func _build_native() -> void:
	var C := Plan.C
	for L in Plan.NL:
		var y0 := L * Plan.LH
		for k in Plan.NZ:
			for i in Plan.NX:
				var kd := Plan.kind_at(L, i, k)
				if kd != 1 and kd != 3: continue
				var ri := Plan.room_at(L, i, k); var rk: String = Plan.rooms[ri]["kind"] if ri >= 0 else ""
				var x0 := Plan.X0 + i * C; var z0 := Plan.Z0 + k * C
				if kd == 1:
					var fm: String = N_FLOOR.get(rk, "concrete_floor_painted")
					_nquad(fm, Vector3(x0, y0, z0), Vector3(x0 + C, y0, z0), Vector3(x0 + C, y0, z0 + C), Vector3(x0, y0, z0 + C), Vector3.UP, 3.0 if rk == "field" else 2.0)
				var lower_ramp: bool = kd == 3 and Plan.ramps[Plan.ramp_at(L, i, k)]["L"] == L
				if ri >= 0 and not Plan.rooms[ri]["outdoor"] and not lower_ramp:
					var yc := y0 + Plan.CEIL
					_nquad("dark_paneled_wood" if rk == "pavilion" else "painted_concrete", Vector3(x0, yc, z0), Vector3(x0 + C, yc, z0), Vector3(x0 + C, yc, z0 + C), Vector3(x0, yc, z0 + C), Vector3.DOWN)
	for key: int in Plan.edges:
		var ty: int = Plan.edges[key]
		var k := (key >> 1) % 32 - 1; var i := ((key >> 1) / 32) % 32 - 1; var L := (key >> 1) / 1024; var east := (key & 1) == 0
		var j := i + (1 if east else 0); var m := k + (0 if east else 1)
		var ra := Plan.room_at(L, i, k) if Plan.walkable(L, i, k) else -1; var rb := Plan.room_at(L, j, m) if Plan.walkable(L, j, m) else -1
		var in_a: bool = ra >= 0 and not Plan.rooms[ra]["outdoor"]; var in_b: bool = rb >= 0 and not Plan.rooms[rb]["outdoor"]
		var indoor := in_a or in_b
		var rk: String = Plan.rooms[ra]["kind"] if in_a and (not in_b or Plan.rooms[ra]["kind"] != "corridor") else (Plan.rooms[rb]["kind"] if in_b else "")
		var wm: String = N_WALL.get(rk, "painted_concrete") if indoor else ("forest_leaves_02" if (ra >= 0 and rb >= 0) else "rustic_stone_wall")
		var ex := (Plan.X0 + (i + 1) * C) if east else Plan.cx(i); var ez := Plan.cz(k) if east else (Plan.Z0 + (k + 1) * C)
		var y0 := L * Plan.LH
		var top := y0 + (Plan.LH if L < Plan.NL - 1 else Plan.CEIL + 0.1) if indoor else y0 + (2.3 if wm == "forest_leaves_02" else 3.0)
		var th := 0.16 if indoor else (0.8 if wm == "forest_leaves_02" else 0.5)
		match ty:
			Plan.WALL: _nwall(wm, east, ex, ez, y0, top, 0.0, C, th)
			Plan.DOOR, Plan.SDOOR:
				_nwall(wm, east, ex, ez, y0, top, 0.0, 0.39, th); _nwall(wm, east, ex, ez, y0, top, C - 0.39, C, th); _nwall(wm, east, ex, ez, y0 + 2.3, top, 0.39, C - 0.39, th)
				if ty == Plan.SDOOR:    # a steel frame so the shutter reads as a different kind of door
					_nwall("steel", east, ex, ez, y0, y0 + 2.34, 0.33, 0.39, th + 0.08); _nwall("steel", east, ex, ez, y0, y0 + 2.34, C - 0.39, C - 0.33, th + 0.08); _nwall("steel", east, ex, ez, y0 + 2.3, y0 + 2.38, 0.33, C - 0.33, th + 0.08)
			Plan.WINDOW:
				_nwall(wm, east, ex, ez, y0, y0 + 0.95, 0.0, C, th); _nwall(wm, east, ex, ez, y0 + 2.65, top, 0.0, C, th); _nwall("glass", east, ex, ez, y0 + 0.95, y0 + 2.65, 0.0, C, 0.02)
			Plan.RAIL: _nwall("rustic_stone_wall" if not indoor else "steel", east, ex, ez, y0, y0 + 0.95, 0.0, C, 0.34 if not indoor else 0.06)
			Plan.GLASS: _nwall("glass", east, ex, ez, y0, top, 0.0, C, 0.02)
	# flights: forty shallow steps each, solid underneath
	for r: Dictionary in Plan.ramps:
		var ln: Array = r["lane"]; var y0: float = r["L"] * Plan.LH; var n := int(round(float(r["len"]) / 0.3))
		var xa: float = Plan.X0 + int(ln[0]) * C; var xb: float = Plan.X0 + (int(ln[2]) + 1) * C; var za: float = Plan.Z0 + int(ln[1]) * C; var zb: float = Plan.Z0 + (int(ln[3]) + 1) * C
		for st in n:
			var u0: float = float(r["s0"]) + r["dir"] * st * 0.3; var u1: float = u0 + r["dir"] * 0.3; var hgt := (st + 1) * Plan.LH / n
			if r["along_k"]: _nbox("concrete_floor_02", Vector3((xa + xb) / 2.0, y0 + hgt / 2.0, (u0 + u1) / 2.0), Vector3(xb - xa, hgt, 0.3))
			else: _nbox("concrete_floor_02", Vector3((u0 + u1) / 2.0, y0 + hgt / 2.0, (za + zb) / 2.0), Vector3(0.3, hgt, zb - za))
	var solid := ArrayMesh.new(); var glass := ArrayMesh.new()
	for name: String in _n_st:
		var st: SurfaceTool = _n_st[name]; st.generate_tangents()
		var target := glass if name == "glass" else solid
		st.commit(target)
		var mat: Material = plain(name) if name in ["glass", "steel", "brass", "trim"] else surf_mat(name, Color(0.5, 0.68, 0.38) if name == "forest_leaves_02" else (Color(0.62, 0.82, 0.48) if name == "leafy_grass" else Color.WHITE))
		target.surface_set_material(target.get_surface_count() - 1, mat)
	var mi := MeshInstance3D.new(); mi.mesh = solid; mi.name = "Building"; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED; add_child(mi)
	if glass.get_surface_count() > 0:
		var gi := MeshInstance3D.new(); gi.mesh = glass; gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED; add_child(gi)
	_n_st.clear(); _n_cnt.clear()

func _build_native_outside() -> void:
	if Plan.meta.get("sky", "") == "day":      # the country beyond the garden wall
		var m := MeshInstance3D.new(); var pl := PlaneMesh.new(); pl.size = Vector2(700, 700); m.mesh = pl
		m.material_override = surf_mat("leafy_grass", Color(0.6, 0.78, 0.46), Vector3(180, 180, 1)); m.position = Vector3(0, -0.04, 0); add_child(m)
	var cols := {"green": Color(0.15, 1.0, 0.45), "pink": Color(1.0, 0.16, 0.55), "cyan": Color(0.1, 0.9, 1.0), "amber": Color(1.0, 0.6, 0.12)}
	for q: Array in Plan.meta.get("signs", []): neon(q[0], Vector3(q[1], q[2], q[3]), q[4], cols[q[5]], q[6], "Rajdhani-SemiBold", 1.2)

func _cyl(parent: Node3D, r0: float, r1: float, h: float, pos: Vector3, mat: Material, shadow := true) -> MeshInstance3D:
	var m := MeshInstance3D.new(); var c := CylinderMesh.new(); c.bottom_radius = r0; c.top_radius = r1; c.height = h; c.radial_segments = 12; c.rings = 1
	m.mesh = c; m.material_override = mat; m.position = pos; parent.add_child(m)
	if not shadow: m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

func _special(name: String, q: Array) -> Node3D:
	var n := Node3D.new()
	if name == "__tree":
		var bark := StandardMaterial3D.new(); bark.albedo_color = Color(0.25, 0.18, 0.12); bark.roughness = 0.95
		var leaf := surf_mat("forest_leaves_02", Color(0.42, 0.62, 0.3), Vector3(3, 3, 1))
		_cyl(n, 0.26, 0.16, 3.4, Vector3(0, 1.7, 0), bark)
		for c: Array in [[0.0, 4.3, 0.0, 1.9], [1.1, 3.8, 0.4, 1.3], [-0.9, 3.9, -0.6, 1.4], [0.2, 5.2, -0.3, 1.3], [-0.3, 3.7, 1.0, 1.2]]:
			var m := MeshInstance3D.new(); var sp := SphereMesh.new(); sp.radius = c[3]; sp.height = c[3] * 1.7; sp.radial_segments = 12; sp.rings = 6
			m.mesh = sp; m.material_override = leaf; m.position = Vector3(c[0], c[1], c[2]); n.add_child(m)
	elif name == "__fountain":
		var stone := surf_mat("rustic_stone_wall")
		_cyl(n, 1.9, 1.9, 0.6, Vector3(0, 0.3, 0), stone); _cyl(n, 0.3, 0.22, 1.5, Vector3(0, 0.95, 0), stone); _cyl(n, 0.7, 0.3, 0.2, Vector3(0, 1.75, 0), stone)
		var w := StandardMaterial3D.new(); w.albedo_color = Color(0.08, 0.22, 0.28); w.roughness = 0.05; w.metallic_specular = 0.8
		_cyl(n, 1.7, 1.7, 0.02, Vector3(0, 0.62, 0), w, false)
	elif name == "__lamppost":
		_cyl(n, 0.07, 0.05, 3.3, Vector3(0, 1.65, 0), plain("dark"))
	elif name == "__pipe":     # [name, L, x, z, rot, y, length]: two pipes side by side under the ceiling
		for o: Array in [[0.0, 0.0, 0.09, Color(0.5, 0.52, 0.55)], [0.24, -0.04, 0.06, Color(0.55, 0.16, 0.12)]]:
			var pm := StandardMaterial3D.new(); pm.albedo_color = o[3]; pm.metallic = 0.7; pm.roughness = 0.45
			var m := _cyl(n, o[2], o[2], float(q[6]), Vector3(o[0], o[1], 0), pm, false); m.rotation.x = PI / 2
		n.position = Vector3(q[2], q[5], q[3]); n.rotation.y = q[4]
	return n
