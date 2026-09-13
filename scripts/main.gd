extends Node2D
## Prototype puzzle scene: pieces start in a scrollable tray under the board.
## Drag a tray piece upward to lift it onto the board, swipe sideways to scroll the tray,
## drop a piece over the tray to put it back. Toggle shows the original; Finish grades.
## Pieces are cat-only cutouts; the between-cat background is painted on the board.

const PUZZLE_DIR := "res://puzzles/cats-01"
const SNAP_TOLERANCE := 40.0  # source pixels; also the grading tolerance
const BOARD_SIZE := Vector2(2048, 2048)
const TRAY_RECT := Rect2(0, 2208, 2048, 360)  # canvas coordinates
const TRAY_SCALE := 0.7
const TRAY_GAP := 30.0
const TRAY_MARGIN := 40.0
const LIFT_THRESHOLD := 24.0    # upward move (canvas px) that lifts a tray piece
const SCROLL_THRESHOLD := 24.0  # sideways move that starts scrolling the tray
const WHEEL_STEP := 160.0

enum Pointer { IDLE, TRAY_PRESS, TRAY_SCROLL, DRAG }

@onready var pieces_root: Node2D = $Board/Pieces
@onready var reference: Sprite2D = $Board/Reference
@onready var background: Sprite2D = $Board/Background
@onready var tray_content: Node2D = $Tray/Content
@onready var score_label: Label = $UI/Bar/Row/Score
@onready var show_original: CheckButton = $UI/Bar/Row/ShowOriginal
@onready var finish_button: Button = $UI/Bar/Row/Finish
@onready var shuffle_button: Button = $UI/Bar/Row/Shuffle

var pieces: Array[Piece] = []
var tray_order: Array[Piece] = []
var dragging: Piece = null
var rng := RandomNumberGenerator.new()

var _drag_offset := Vector2.ZERO
var _pointer := Pointer.IDLE
var _press_point := Vector2.ZERO
var _last_point := Vector2.ZERO
var _press_piece: Piece = null
var _tray_content_width := 0.0


func _ready() -> void:
	reference.texture = load(PUZZLE_DIR + "/source.png")
	reference.centered = false
	reference.visible = false
	background.texture = load(PUZZLE_DIR + "/background.png")
	background.centered = false
	_load_pieces()
	shuffle()
	show_original.toggled.connect(set_show_original)
	finish_button.pressed.connect(finish)
	shuffle_button.pressed.connect(shuffle)


func _load_pieces() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PUZZLE_DIR + "/manifest.json"))
	for entry: Dictionary in manifest["pieces"]:
		var piece := Piece.new()
		piece.setup(entry, load(PUZZLE_DIR + "/pieces/piece_%03d.png" % int(entry["id"])))
		tray_content.add_child(piece)
		pieces.append(piece)


## Everything back into the tray in a fresh random order; the board is left empty.
func shuffle() -> void:
	_pointer = Pointer.IDLE
	dragging = null
	_press_piece = null
	tray_order.clear()
	var order := pieces.duplicate()
	order.shuffle()
	for piece in order:
		_put_in_tray(piece)
	_layout_tray()
	set_tray_scroll(0.0)
	score_label.text = "Score: -"


func set_show_original(on: bool) -> void:
	if on and dragging != null:
		return_to_tray(dragging)
		dragging = null
		_pointer = Pointer.IDLE
	reference.visible = on
	pieces_root.visible = not on
	background.visible = not on


# --- tray --------------------------------------------------------------------

func _put_in_tray(piece: Piece) -> void:
	if piece.get_parent() != tray_content:
		piece.get_parent().remove_child(piece)
		tray_content.add_child(piece)
	piece.scale = Vector2.ONE * TRAY_SCALE
	piece.in_tray = true
	if not tray_order.has(piece):
		tray_order.append(piece)


func _layout_tray() -> void:
	var x := TRAY_MARGIN
	for piece in tray_order:
		piece.position = Vector2(x, (TRAY_RECT.size.y - piece.size.y * TRAY_SCALE) / 2.0)
		x += piece.size.x * TRAY_SCALE + TRAY_GAP
	_tray_content_width = x - TRAY_GAP + TRAY_MARGIN
	set_tray_scroll(tray_scroll())  # re-clamp


func tray_scroll() -> float:
	return tray_content.position.x


func set_tray_scroll(x: float) -> void:
	var min_x := minf(0.0, TRAY_RECT.size.x - _tray_content_width)
	tray_content.position.x = clampf(x, min_x, 0.0)


func return_to_tray(piece: Piece) -> void:
	_put_in_tray(piece)
	_layout_tray()


## Move a piece out of the tray onto the board at a board position (pieces_root coordinates).
func place_on_board(piece: Piece, board_pos: Vector2) -> void:
	tray_order.erase(piece)
	if piece.get_parent() != pieces_root:
		piece.get_parent().remove_child(piece)
		pieces_root.add_child(piece)
	piece.scale = Vector2.ONE
	piece.in_tray = false
	piece.position = board_pos
	pieces_root.move_child(piece, -1)
	_layout_tray()


# --- picking (canvas coordinates) ----------------------------------------------

func _topmost_under(parent: Node2D, canvas_point: Vector2) -> Piece:
	for i in range(parent.get_child_count() - 1, -1, -1):
		var piece := parent.get_child(i) as Piece
		if piece != null and piece.contains_local_point(piece.to_local(canvas_point)):
			return piece
	return null


func board_piece_at(canvas_point: Vector2) -> Piece:
	return _topmost_under(pieces_root, canvas_point)


func tray_piece_at(canvas_point: Vector2) -> Piece:
	if not TRAY_RECT.has_point(canvas_point):
		return null
	return _topmost_under(tray_content, canvas_point)


# --- pointer -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if reference.visible:
		return
	if event is InputEventMouseButton:
		var pt: Vector2 = make_input_local(event).position
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_at(pt)
			else:
				release_at(pt)
		elif event.pressed and TRAY_RECT.has_point(pt):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
				set_tray_scroll(tray_scroll() + WHEEL_STEP)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
				set_tray_scroll(tray_scroll() - WHEEL_STEP)
	elif event is InputEventMouseMotion:
		move_to(make_input_local(event).position)


func press_at(canvas_point: Vector2) -> void:
	_press_point = canvas_point
	_last_point = canvas_point
	if TRAY_RECT.has_point(canvas_point):
		_press_piece = tray_piece_at(canvas_point)
		_pointer = Pointer.TRAY_PRESS
		return
	var piece := board_piece_at(canvas_point)
	if piece == null:
		return
	dragging = piece
	_drag_offset = piece.position - pieces_root.to_local(canvas_point)
	pieces_root.move_child(piece, -1)
	_pointer = Pointer.DRAG


func move_to(canvas_point: Vector2) -> void:
	match _pointer:
		Pointer.TRAY_PRESS:
			var d := canvas_point - _press_point
			if _press_piece != null and d.y < -LIFT_THRESHOLD:
				_lift(_press_piece, canvas_point)
			elif absf(d.x) > SCROLL_THRESHOLD:
				_pointer = Pointer.TRAY_SCROLL
				set_tray_scroll(tray_scroll() + d.x)  # include the distance moved before scrolling kicked in
		Pointer.TRAY_SCROLL:
			set_tray_scroll(tray_scroll() + canvas_point.x - _last_point.x)
		Pointer.DRAG:
			_drag_to(canvas_point)
	_last_point = canvas_point


func release_at(canvas_point: Vector2) -> void:
	# a press in the tray that ends over the board lifts the piece even if no motion event arrived
	if _pointer == Pointer.TRAY_PRESS and _press_piece != null and not TRAY_RECT.has_point(canvas_point):
		_lift(_press_piece, canvas_point)
	if _pointer == Pointer.DRAG and dragging != null:
		_drag_to(canvas_point)  # apply the final pointer position even without a motion event
		if TRAY_RECT.has_point(canvas_point):
			return_to_tray(dragging)
		elif dragging.is_placed(SNAP_TOLERANCE):
			dragging.position = dragging.true_position
		dragging = null
	_pointer = Pointer.IDLE
	_press_piece = null


## Lift a tray piece onto the board, keeping the grabbed pixel under the pointer.
func _lift(piece: Piece, canvas_point: Vector2) -> void:
	var grab_local := piece.to_local(_press_point)  # pixel grabbed at press time, independent of scale
	place_on_board(piece, pieces_root.to_local(canvas_point) - grab_local)
	dragging = piece
	_drag_offset = -grab_local
	_pointer = Pointer.DRAG


func _drag_to(canvas_point: Vector2) -> void:
	if dragging == null:
		return
	dragging.position = pieces_root.to_local(canvas_point) + _drag_offset


# --- grading --------------------------------------------------------------------

func grade() -> Dictionary:
	var placed := 0
	for piece in pieces:
		if not piece.in_tray and piece.is_placed(SNAP_TOLERANCE):
			placed += 1
	var total := pieces.size()
	var percent := int(round(100.0 * placed / total)) if total > 0 else 0
	return {"placed": placed, "total": total, "percent": percent}


func finish() -> void:
	if dragging != null:
		release_at(_last_point)
	var g := grade()
	score_label.text = "Score: %d%% (%d/%d)" % [g["percent"], g["placed"], g["total"]]
