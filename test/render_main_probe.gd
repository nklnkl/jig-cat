extends SceneTree
## Renders main.tscn into an unscaled offscreen viewport, saves the frame and the draw order.

func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 2208)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	for i in range(4):
		await process_frame
	var path: String = OS.get_environment("SHOT")
	vp.get_texture().get_image().save_png(path)
	var order := []
	for child in main.pieces_root.get_children():
		order.append({"id": child.id, "x": child.position.x, "y": child.position.y})
	var f := FileAccess.open(path + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(order))
	f.close()
	print("saved")
	quit(0)
