extends SceneTree
## Draws each piece alone into an offscreen viewport and compares the result to its PNG.
## Run windowed: godot --path . --rendering-driver opengl3 -s test/render_probe.gd

const DIR := "res://puzzles/cats-01"

func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 2048)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0, 1, 0)
	bg.size = Vector2(2048, 2048)
	vp.add_child(bg)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/manifest.json"))
	var bad := 0
	for entry: Dictionary in manifest["pieces"]:
		var id := int(entry["id"])
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture = load(DIR + "/pieces/piece_%03d.png" % id)
		spr.position = Vector2(100, 100)
		vp.add_child(spr)
		await process_frame
		await process_frame
		var shot: Image = vp.get_texture().get_image()
		var png := Image.load_from_file(ProjectSettings.globalize_path(DIR + "/pieces/piece_%03d.png" % id))
		var w := png.get_width()
		var h := png.get_height()
		var missing := 0   # opaque in png, green in render
		var extra := 0     # transparent in png, not green in render
		var wrong := 0     # opaque, but colour differs
		for y in range(h):
			for x in range(w):
				var p := png.get_pixel(x, y)
				var r := shot.get_pixel(100 + x, 100 + y)
				if p.a > 0.5:
					if r.g > 0.9 and r.r < 0.1 and r.b < 0.1:
						missing += 1
					elif abs(r.r - p.r) > 0.02 or abs(r.g - p.g) > 0.02 or abs(r.b - p.b) > 0.02:
						wrong += 1
				else:
					if not (r.g > 0.9 and r.r < 0.1 and r.b < 0.1):
						extra += 1
		var tex_size: Vector2 = spr.texture.get_size()
		if missing > 0 or extra > 0 or wrong > 0 or tex_size != Vector2(w, h):
			bad += 1
			print("piece %d: png %dx%d tex %s missing=%d extra=%d wrong=%d" % [id, w, h, str(tex_size), missing, extra, wrong])
		spr.queue_free()
	print("DONE bad pieces: ", bad)
	quit(0)
