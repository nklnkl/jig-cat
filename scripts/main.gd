extends Node2D
## Prototype puzzle scene: scrambled cat pieces on a board, drag to move,
## toggle to peek at the original composition, Finish to get a grade.
## Pieces are cat-only cutouts; the between-cat background is painted on the board.

const PUZZLE_DIR := "res://puzzles/cats-01"
const SNAP_TOLERANCE := 40.0  # source pixels; also the grading tolerance
const BOARD_SIZE := Vector2(2048, 2048)

@onready var pieces_root: Node2D = $Board/Pieces
@onready var reference: Sprite2D = $Board/Reference
@onready var background: Sprite2D = $Board/Background
@onready var score_label: Label = $UI/Bar/Row/Score
@onready var show_original: CheckButton = $UI/Bar/Row/ShowOriginal
@onready var finish_button: Button = $UI/Bar/Row/Finish
@onready var shuffle_button: Button = $UI/Bar/Row/Shuffle

var pieces: Array[Piece] = []
var dragging: Piece = null
var _drag_offset := Vector2.ZERO
var rng := RandomNumberGenerator.new()


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
		pieces_root.add_child(piece)
		pieces.append(piece)


## Scatter every piece inside the board, never within 3x tolerance of its home
## so nothing starts "placed" for free.
func shuffle() -> void:
	for piece in pieces:
		var limit := BOARD_SIZE - piece.size
		var pos := piece.true_position
		while pos.distance_to(piece.true_position) < SNAP_TOLERANCE * 3.0:
			pos = Vector2(rng.randf_range(0.0, limit.x), rng.randf_range(0.0, limit.y))
		piece.position = pos
	# random stacking order too
	var order := pieces.duplicate()
	order.shuffle()
	for piece in order:
		pieces_root.move_child(piece, -1)
	dragging = null
	score_label.text = "Score: -"


func set_show_original(on: bool) -> void:
	if on:
		_release()
	reference.visible = on
	pieces_root.visible = not on
	background.visible = not on


# --- dragging -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if reference.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_at(pieces_root.get_local_mouse_position())
		else:
			drag_to(pieces_root.get_local_mouse_position())  # apply the final pointer position even without a motion event
			_release()
	elif event is InputEventMouseMotion and dragging != null:
		drag_to(pieces_root.get_local_mouse_position())


## Topmost piece whose opaque pixels cover the point (board coordinates).
func piece_at(board_point: Vector2) -> Piece:
	for i in range(pieces_root.get_child_count() - 1, -1, -1):
		var piece := pieces_root.get_child(i) as Piece
		if piece.contains_local_point(board_point - piece.position):
			return piece
	return null


func grab_at(board_point: Vector2) -> void:
	var piece := piece_at(board_point)
	if piece == null:
		return
	dragging = piece
	_drag_offset = piece.position - board_point
	pieces_root.move_child(piece, -1)


func drag_to(board_point: Vector2) -> void:
	if dragging == null:
		return
	dragging.position = board_point + _drag_offset


func _release() -> void:
	if dragging == null:
		return
	if dragging.is_placed(SNAP_TOLERANCE):
		dragging.position = dragging.true_position
	dragging = null


# --- grading --------------------------------------------------------------------

func grade() -> Dictionary:
	var placed := 0
	for piece in pieces:
		if piece.is_placed(SNAP_TOLERANCE):
			placed += 1
	var total := pieces.size()
	var percent := int(round(100.0 * placed / total)) if total > 0 else 0
	return {"placed": placed, "total": total, "percent": percent}


func finish() -> void:
	_release()
	var g := grade()
	score_label.text = "Score: %d%% (%d/%d)" % [g["percent"], g["placed"], g["total"]]
