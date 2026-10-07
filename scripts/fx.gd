extends RefCounted
## Throwaway effects: floating damage numbers and one-shot sprite bursts.

const AnimSprite := preload("res://scripts/anim_sprite.gd")
const FONT := preload("res://fonts/PixelifySans.ttf")
const MAX_NUMBERS := 40

static var _numbers := 0
## While true (the co-op host), every effect is also noted in `events` for the guests:
## ["n", at, amount, colour] or ["b", at, sheet, height, colour, upright].
static var record := false
static var events: Array = []


## A number that pops up at `at`, drifts up and fades.
static func number(parent: Node, at: Vector3, amount: float, color := Color.WHITE) -> void:
	if record and events.size() < 60:
		events.append(["n", at, amount, color])
	if _numbers >= MAX_NUMBERS or not parent.is_inside_tree():
		return
	_numbers += 1
	var label := Label3D.new()
	label.text = str(maxi(int(round(amount)), 1))
	label.font = FONT
	label.font_size = 64
	label.outline_size = 16
	label.pixel_size = 0.011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.no_depth_test = true
	label.modulate = color
	label.position = at + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	parent.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y + 1.4, 0.55)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tween.tween_callback(label.queue_free)
	label.tree_exited.connect(func() -> void: _numbers -= 1)


## Plays a sheet once at `at` and removes it. `upright` keeps it vertical (lightning).
static func burst(parent: Node, at: Vector3, sheet: String, height: float, tint := Color.WHITE, upright := false) -> Sprite3D:
	if record and events.size() < 60:
		events.append(["b", at, sheet, height, tint, upright])
	var sprite := AnimSprite.make(sheet, height)
	if upright:
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.loop = false
	sprite.modulate = tint
	sprite.position = at
	sprite.finished.connect(sprite.queue_free)
	parent.add_child(sprite)
	return sprite
