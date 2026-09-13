extends SceneTree
## Headless smoke test for the prototype. Run:
##   godot --headless --path . -s test/smoke.gd
## Exit code 0 = all checks passed.

const TRAY_SCALE := 0.7

var _fails: Array[String] = []
var main


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		_fails.append(what)


func _first_opaque(p: Piece) -> Vector2:
	for y in range(int(p.size.y)):
		for x in range(int(p.size.x)):
			if p.contains_local_point(Vector2(x, y)):
				return Vector2(x, y)
	return Vector2.ZERO


## Canvas point on the centre of an opaque pixel of a piece, wherever it currently lives.
func _grip(p: Piece) -> Vector2:
	return p.to_global(_first_opaque(p) + Vector2(0.5, 0.5))


func _tray_x_range(p: Piece) -> Vector2:
	return Vector2(p.position.x, p.position.x + p.size.x * TRAY_SCALE)


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var board_origin: Vector2 = main.get_node("Board").position

	print("loading")
	_check(main.pieces.size() == 108, "108 pieces loaded")
	_check(main.tray_order.size() == 108 and main.pieces_root.get_child_count() == 0, "all pieces start in the tray, board empty")
	_check(main.grade()["placed"] == 0, "nothing counts as placed at the start")
	var ordered := true
	for i in range(1, main.tray_order.size()):
		if _tray_x_range(main.tray_order[i - 1]).y > _tray_x_range(main.tray_order[i]).x:
			ordered = false
	_check(ordered, "tray pieces sit left to right without overlapping")
	_check(main._tray_content_width > main.TRAY_RECT.size.x, "tray content is wider than the tray (needs scrolling)")
	for p in main.pieces:
		if p.scale != Vector2.ONE * TRAY_SCALE:
			_check(false, "piece %d is not at tray scale" % p.id)
			break

	print("tray scrolling")
	var first: Piece = main.tray_order[0]
	var g := _grip(first)
	main.press_at(g)
	main.move_to(g + Vector2(-60, 0))
	main.move_to(g + Vector2(-260, 0))
	_check(main._pointer == main.Pointer.TRAY_SCROLL, "a sideways move on a tray piece scrolls instead of lifting")
	_check(is_equal_approx(main.tray_scroll(), -260.0), "tray scrolled by the sideways distance (got %f)" % main.tray_scroll())
	main.release_at(g + Vector2(-260, 0))
	_check(first.in_tray and main.pieces_root.get_child_count() == 0, "scrolling leaves the piece in the tray")
	main.set_tray_scroll(500.0)
	_check(main.tray_scroll() == 0.0, "scroll clamps at the left edge")
	main.set_tray_scroll(-1.0e9)
	_check(is_equal_approx(main.tray_scroll(), main.TRAY_RECT.size.x - main._tray_content_width), "scroll clamps at the right edge")
	main.set_tray_scroll(0.0)

	print("lifting a tray piece onto the board")
	var lifted: Piece = main.tray_order[1]
	g = _grip(lifted)
	var grab_local := _first_opaque(lifted) + Vector2(0.5, 0.5)
	main.press_at(g)
	main.move_to(g + Vector2(3, -10))
	_check(lifted.in_tray, "a small move does not lift yet")
	main.move_to(g + Vector2(3, -100))
	_check(main.dragging == lifted and not lifted.in_tray and lifted.get_parent() == main.pieces_root, "pulling upward lifts the piece onto the board")
	_check(lifted.scale == Vector2.ONE, "lifted piece is back at full scale")
	_check(lifted.to_local(g + Vector2(3, -100)).distance_to(grab_local) < 0.5, "the grabbed pixel stays under the pointer after lifting")
	_check(not main.tray_order.has(lifted), "lifted piece left the tray order")
	var home_canvas: Vector2 = board_origin + lifted.true_position + grab_local + Vector2(25, -20)
	main.move_to(home_canvas)
	main.release_at(home_canvas)
	_check(lifted.position == lifted.true_position, "release within tolerance snaps home")
	_check(main.dragging == null and main._pointer == main.Pointer.IDLE, "release clears the drag")

	print("press in tray, release on board with no motion")
	var jumped: Piece = main.tray_order[0]
	g = _grip(jumped)
	main.press_at(g)
	main.release_at(Vector2(900, 900))
	_check(not jumped.in_tray and jumped.get_parent() == main.pieces_root and main.dragging == null, "a press-release across tray and board lifts the piece onto the board")
	_check(jumped.to_local(Vector2(900, 900)).distance_to(_first_opaque(jumped) + Vector2(0.5, 0.5)) < 0.5, "it lands with the grabbed pixel at the release point")
	main.return_to_tray(jumped)

	print("board dragging and picking")
	g = _grip(lifted)
	main.press_at(g)
	main.move_to(g + Vector2(300, 0))
	main.release_at(g + Vector2(300, 0))
	_check(lifted.position == lifted.true_position + Vector2(300, 0), "a board piece drags with the pointer and does not snap when far")
	var other: Piece = main.tray_order[0]
	main.place_on_board(other, lifted.position)
	var op := _first_opaque(lifted)
	var pick: Piece = main.board_piece_at(board_origin + lifted.position + op)
	_check(pick == other or (pick == lifted and not other.contains_local_point(op)), "topmost opaque pixel wins on the board")
	main.pieces_root.move_child(lifted, -1)
	_check(main.board_piece_at(board_origin + lifted.position + op) == lifted, "raising a piece makes it the pick")
	_check(main.board_piece_at(Vector2(-50, -50)) == null, "off-board point picks nothing")

	print("returning a piece to the tray")
	g = _grip(other)
	main.press_at(g)
	var tray_pt := Vector2(1000, main.TRAY_RECT.position.y + 100)
	main.move_to(tray_pt)
	main.release_at(tray_pt)
	_check(other.in_tray and other.get_parent() == main.tray_content and main.tray_order[-1] == other, "dropping over the tray puts the piece back at the end of the tray")
	_check(other.scale == Vector2.ONE * TRAY_SCALE, "returned piece is at tray scale again")

	print("grading")
	main.shuffle()
	_check(main.tray_order.size() == 108 and main.pieces_root.get_child_count() == 0, "shuffle returns everything to the tray")
	for i in range(30):
		main.place_on_board(main.pieces[i], main.pieces[i].true_position)
	var gr: Dictionary = main.grade()
	_check(gr["placed"] == 30 and gr["total"] == 108 and gr["percent"] == 28, "30/108 placed grades 28%% (got %s)" % str(gr))
	main.place_on_board(main.pieces[30], main.pieces[30].true_position + Vector2(39, 0))
	_check(main.grade()["placed"] == 31, "a piece within tolerance counts as placed")
	main.place_on_board(main.pieces[31], main.pieces[31].true_position + Vector2(41, 0))
	_check(main.grade()["placed"] == 31, "a piece just outside tolerance does not count")
	main.finish()
	_check(main.score_label.text == "Score: 29% (31/108)", "finish writes the score label (got '%s')" % main.score_label.text)

	print("real input path (events pushed through the viewport)")
	main.shuffle()
	var tp: Piece = main.tray_order[0]
	g = _grip(tp)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = g
	down.global_position = g
	root.push_input(down, true)
	await process_frame
	_check(main._pointer == main.Pointer.TRAY_PRESS and main._press_piece == tp, "a press on the tray reaches the game (nothing swallows tray input)")
	var mv := InputEventMouseMotion.new()
	mv.position = g + Vector2(0, -120)
	mv.global_position = mv.position
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(mv, true)
	await process_frame
	_check(main.dragging == tp and tp.get_parent() == main.pieces_root, "motion through the viewport lifts the piece")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = mv.position
	up.global_position = mv.position
	root.push_input(up, true)
	await process_frame
	_check(main.dragging == null and not tp.in_tray, "release through the viewport leaves the piece on the board")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = Vector2(1000, main.TRAY_RECT.position.y + 100)
	wheel.global_position = wheel.position
	root.push_input(wheel, true)
	await process_frame
	_check(is_equal_approx(main.tray_scroll(), -main.WHEEL_STEP), "mouse wheel over the tray scrolls it (got %f)" % main.tray_scroll())

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
