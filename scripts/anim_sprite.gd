extends Sprite3D
## A pixel-art sprite sheet in the 3D world: unshaded, nearest-filtered, animated. Used for
## enemies, shots, pickups and props.

const Db := preload("res://scripts/db.gd")

signal finished

var fps := 8.0
var loop := true
var clock := 0.0


## `height` is the sprite's height in metres. With `feet` the origin is where the art stands
## on the ground (see Db.feet), and with `rooted` it is also centred on that spot.
static func make(sheet_id: String, height: float, feet := false, rooted := false) -> Sprite3D:
	var info := Db.sheet(sheet_id)
	var sprite: Sprite3D = load("res://scripts/anim_sprite.gd").new()
	var sheet_texture: Texture2D = info[0]
	sprite.texture = sheet_texture
	sprite.hframes = info[1]
	sprite.fps = info[2]
	sprite.pixel_size = height / sheet_texture.get_height()
	if feet:
		var stand := Db.feet(sheet_id)
		sprite.offset = Vector2(-stand.x if rooted else 0.0, sheet_texture.get_height() * 0.5 - stand.y)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.set_process(sprite.hframes > 1)
	return sprite


func _process(delta: float) -> void:
	clock += delta
	var index := int(clock * fps)
	if loop:
		frame = index % hframes
	elif index >= hframes:
		frame = hframes - 1
		set_process(false)
		finished.emit()
	else:
		frame = index
