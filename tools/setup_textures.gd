extends SceneTree
# marks normal maps as such in their .import files (RGTC compression; avatar normals are DirectX-style, so flip green)
func walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	for f in d.get_files():
		if f.ends_with(".import"): out.append(dir + "/" + f)
	for s in d.get_directories():
		if not s.begins_with("."): walk(dir + "/" + s, out)
func _init():
	var files: Array = []; walk("assets", files)
	var n := 0
	for p: String in files:
		var b := p.get_file().trim_suffix(".import").to_lower()
		var is_n := b.begins_with("nor.") or b.contains("_normal.") or b.contains("_nor_") or b.contains("_nor.")
		if not is_n: continue
		var cf := ConfigFile.new()
		if cf.load(p) != OK: continue
		cf.set_value("params", "compress/normal_map", 1)
		if p.contains("/avatars/"): cf.set_value("params", "process/normal_map_invert_y", true)
		cf.save(p); n += 1
	print("normal maps flagged: ", n)
	quit()
