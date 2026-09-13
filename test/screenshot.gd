extends SceneTree
## Renders the main scene windowed and saves a frame to the path in the SHOT env var.

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in range(6):
		await process_frame
	var img: Image = root.get_texture().get_image()
	var path: String = OS.get_environment("SHOT")
	print("saved ", path, " ", img.save_png(path))
	quit(0)
