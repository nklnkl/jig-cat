extends SceneTree
## Headless smoke test for the prototype. Run:
##   godot --headless --path . -s test/smoke.gd
## Exit code 0 = all checks passed.

var _fails: Array[String] = []


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		_fails.append(what)


func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	print("loading")
	_check(main.pieces.size() == 108, "108 pieces loaded")
	var placed_at_start: int = main.grade()["placed"]
	_check(placed_at_start == 0, "shuffle leaves nothing placed (got %d)" % placed_at_start)
	for p in main.pieces:
		var inside: bool = p.position.x >= 0 and p.position.y >= 0 \
			and p.position.x + p.size.x <= 2048 and p.position.y + p.size.y <= 2048
		if not inside:
			_check(false, "piece %d shuffled outside the board" % p.id)
			break

	print("hit testing")
	var piece: Piece = main.pieces[0]
	var opaque := Vector2(-1, -1)
	var transparent := Vector2(-1, -1)
	for y in range(int(piece.size.y)):
		for x in range(int(piece.size.x)):
			if piece.contains_local_point(Vector2(x, y)):
				if opaque.x < 0:
					opaque = Vector2(x, y)
			elif transparent.x < 0:
				transparent = Vector2(x, y)
	_check(opaque.x >= 0 and transparent.x >= 0, "piece 0 has opaque and transparent pixels")
	# bring another piece on top of piece 0 at the same spot: topmost wins on its opaque pixel
	var other: Piece = main.pieces[1]
	other.position = piece.position
	main.pieces_root.move_child(other, -1)
	main.pieces_root.move_child(piece, -1)
	_check(main.piece_at(piece.position + opaque) == piece, "topmost opaque pixel picks the top piece")
	main.pieces_root.move_child(other, -1)
	var got: Piece = main.piece_at(piece.position + opaque)
	_check(got == other or (got == piece and not other.contains_local_point(opaque)),
		"raising the other piece makes it the pick where it is opaque")
	_check(main.piece_at(Vector2(-50, -50)) == null, "off-board point picks nothing")

	print("dragging + snapping")
	main.shuffle()
	var target: Piece = main.pieces[7]
	main.pieces_root.move_child(target, -1)
	main.grab_at(target.position + _first_opaque(target))
	_check(main.dragging == target, "grab picks the piece under the pointer")
	var near_home := target.true_position + Vector2(25, -20)
	main.drag_to(near_home - main._drag_offset)
	_check(target.position == near_home, "drag moves the piece with the pointer")
	main._release()
	_check(target.position == target.true_position, "release within tolerance snaps home")
	_check(main.dragging == null, "release clears the drag")
	main.grab_at(target.true_position + _first_opaque(target))
	main.drag_to(target.true_position + Vector2(200, 0) - main._drag_offset)
	main._release()
	_check(target.position != target.true_position, "release outside tolerance does not snap")

	print("grading")
	main.shuffle()
	for i in range(30):
		main.pieces[i].position = main.pieces[i].true_position
	var g: Dictionary = main.grade()
	_check(g["placed"] == 30 and g["total"] == 108 and g["percent"] == 28, "30/108 placed grades 28%% (got %s)" % str(g))
	main.pieces[30].position = main.pieces[30].true_position + Vector2(39, 0)
	_check(main.grade()["placed"] == 31, "a piece within tolerance counts as placed")
	main.pieces[31].position = main.pieces[31].true_position + Vector2(41, 0)
	_check(main.grade()["placed"] == 31, "a piece just outside tolerance does not count")
	main.finish()
	_check(main.score_label.text == "Score: 29% (31/108)", "finish writes the score label (got '%s')" % main.score_label.text)

	print("real input path (events pushed through the viewport)")
	main.shuffle()
	var tp: Piece = main.pieces[3]
	main.pieces_root.move_child(tp, -1)
	var tp_start: Vector2 = tp.position
	var canvas_pt: Vector2 = tp.position + _first_opaque(tp) + main.get_node("Board").position
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = canvas_pt
	down.global_position = canvas_pt
	root.push_input(down, true)
	await process_frame
	_check(main.dragging == tp, "a press on the board reaches the drag code (nothing swallows board input)")
	var mv := InputEventMouseMotion.new()
	mv.position = canvas_pt + Vector2(100, 50)
	mv.global_position = mv.position
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(mv, true)
	await process_frame
	_check(tp.position.distance_to(tp_start + Vector2(100, 50)) < 1.0, "motion drags the piece (got %s from %s)" % [str(tp.position), str(tp_start)])
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = mv.position
	up.global_position = mv.position
	root.push_input(up, true)
	await process_frame
	_check(main.dragging == null, "release through the viewport ends the drag")

	print("toggle")
	main.set_show_original(true)
	_check(main.reference.visible and not main.pieces_root.visible, "show original hides pieces")
	main.set_show_original(false)
	_check(not main.reference.visible and main.pieces_root.visible, "hide original shows pieces")

	if _fails.is_empty():
		print("SMOKE PASS")
		quit(0)
	else:
		print("SMOKE FAIL: ", _fails)
		quit(1)


func _first_opaque(p: Piece) -> Vector2:
	for y in range(int(p.size.y)):
		for x in range(int(p.size.x)):
			if p.contains_local_point(Vector2(x, y)):
				return Vector2(x, y)
	return Vector2.ZERO
