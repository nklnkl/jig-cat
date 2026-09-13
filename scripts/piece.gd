class_name Piece
extends Sprite2D
## One jigsaw piece: a cutout sprite that knows where it truly belongs and can
## answer pixel-accurate "is this point on me?" queries via its alpha bitmap.

var id: int = -1
var true_position := Vector2.ZERO
var size := Vector2.ZERO
var _bitmap := BitMap.new()


func setup(entry: Dictionary, tex: Texture2D) -> void:
	id = int(entry["id"])
	true_position = Vector2(float(entry["x"]), float(entry["y"]))
	size = Vector2(float(entry["w"]), float(entry["h"]))
	texture = tex
	centered = false
	_bitmap.create_from_image_alpha(tex.get_image())


## Point in this piece's local coordinates (pixels from its top-left corner).
func contains_local_point(local: Vector2) -> bool:
	if local.x < 0.0 or local.y < 0.0 or local.x >= size.x or local.y >= size.y:
		return false
	return _bitmap.get_bit(int(local.x), int(local.y))


func distance_from_home() -> float:
	return position.distance_to(true_position)


func is_placed(tolerance: float) -> bool:
	return distance_from_home() <= tolerance
