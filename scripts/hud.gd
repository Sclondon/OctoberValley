extends CanvasLayer
## The in-run display: health, experience and level (top left), stage, clock and objective
## (top middle), the boss's health under it, kills and difficulty (top right), what you carry
## (bottom left), the interact prompt, banners, and a red flash when hurt.

const Db := preload("res://scripts/db.gd")
const FONT := preload("res://fonts/PixelifySans.ttf")
const INK := Color("ffd9a0")
const DARK := Color("1a1026")

## Main, read for the stage title, the altar and the test-yard flag.
var main: Node
var player: Node3D
var director: Node

var _root: Control
var _name: Label
var _health: ProgressBar
var _health_text: Label
var _xp: ProgressBar
var _stage: Label
var _objective: Label
var _boss_box: Control
var _boss_name: Label
var _boss_bar: ProgressBar
var _stats: Label
var _items: HBoxContainer
var _prompt: Label
var _banner: Label
var _banner_sub: Label
var _flash: ColorRect
var _banner_tween: Tween


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.05, 0.05, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	var left := _column(Control.PRESET_TOP_LEFT, Vector2(16, 12))
	_name = _label(left, 26)
	_health = _bar(left, Color("d83a4a"), Vector2(300, 24))
	_health_text = _label(_health, 18)
	_health_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp = _bar(left, Color("f0a030"), Vector2(300, 10))

	var middle := _column(Control.PRESET_CENTER_TOP, Vector2(0, 12))
	middle.alignment = BoxContainer.ALIGNMENT_BEGIN
	_stage = _label(middle, 26, true)
	_objective = _label(middle, 20, true)
	_boss_box = VBoxContainer.new()
	middle.add_child(_boss_box)
	_boss_name = _label(_boss_box, 24, true)
	_boss_name.add_theme_color_override("font_color", Color("ff7a5a"))
	_boss_bar = _bar(_boss_box, Color("c8201c"), Vector2(520, 18))

	var right := _column(Control.PRESET_TOP_RIGHT, Vector2(-16, 12))
	_stats = _label(right, 22)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_items = HBoxContainer.new()
	_items.add_theme_constant_override("separation", 6)
	_root.add_child(_items)
	_items.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_items.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_items.position += Vector2(16, -16)

	var low := _column(Control.PRESET_CENTER_BOTTOM, Vector2(0, -90))
	low.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt = _label(low, 28, true)

	var centre := _column(Control.PRESET_CENTER, Vector2(0, -150))
	_banner = _label(centre, 64, true)
	_banner_sub = _label(centre, 28, true)
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0

	player.inventory_changed.connect(_show_items)
	player.hurt_taken.connect(_on_hurt)
	_show_items()


## Big text across the middle that fades after a moment.
func banner(text: String, sub := "") -> void:
	_banner.text = text
	_banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_sub.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(2.2)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.8)
	_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.8)


func _process(_delta: float) -> void:
	_name.text = "%s   LV %d" % [Db.HEROES[player.hero]["name"].to_upper(), player.level]
	_health.max_value = player.max_hp()
	_health.value = player.hp
	_health_text.text = "%d / %d" % [ceili(player.hp), int(player.max_hp())]
	_xp.max_value = player.xp_needed()
	_xp.value = player.xp
	var seconds := int(director.time)
	_stage.text = "%s   %d:%02d" % [main.stage_title, seconds / 60, seconds % 60]
	_stats.text = "KILLS %d\nDIFFICULTY %.1f\nENEMIES %d" % [player.kills, director.difficulty(), main.enemy_count()]
	# co-op: the rest of the team
	for seat: int in main.heroes:
		var mate: Node3D = main.heroes[seat]
		if mate != player:
			_stats.text += "\nP%d %s  %s" % [seat + 1, Db.HEROES[mate.hero]["name"].to_upper(),
				"DOWN" if mate.dead else "%d / %d" % [ceili(mate.hp), int(mate.max_hp())]]

	var boss: Dictionary = main.boss_info()
	_boss_box.visible = not boss.is_empty()
	if not boss.is_empty():
		_boss_name.text = boss["title"] + ("  (ENRAGED)" if boss["enraged"] else "")
		_boss_bar.max_value = boss["max_hp"]
		_boss_bar.value = boss["hp"]

	var altar: Node3D = main.altar
	_prompt.text = ""
	if main.in_test:
		_objective.text = "Test yard: F1 turns the enemies on and off"
	elif altar == null:
		_objective.text = ""
	else:
		var away := int(altar.global_position.distance_to(player.global_position))
		match altar.state:
			"idle":
				_objective.text = "Find the altar: %d m" % away
			"boss":
				_objective.text = "Defeat the boss"
			"portal":
				_objective.text = "Enter the portal: %d m" % away
		var offer: String = altar.prompt(player.global_position)
		if offer != "" and not player.dead:
			_prompt.text = "[E]  %s" % offer
	if player.dead and main.state == "playing":
		_prompt.text = "You are down. You get back up on the next stage."


func _on_hurt(_amount: float) -> void:
	_flash.color.a = 0.35
	create_tween().tween_property(_flash, "color:a", 0.0, 0.3)


## Rebuilds the row of weapon and passive icons with their levels.
func _show_items() -> void:
	for child in _items.get_children():
		child.queue_free()
	for weapon in player.weapons:
		_item(weapon.def["icon"], weapon.level)
	for id: String in player.passives:
		_item(Db.PASSIVES[id]["icon"], player.passives[id])


func _item(icon_id: String, item_level: int) -> void:
	var icon := TextureRect.new()
	icon.texture = Db.icon(icon_id)
	icon.custom_minimum_size = Vector2(52, 52)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var number := _label(icon, 20)
	number.text = str(item_level)
	number.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	number.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	number.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_items.add_child(icon)


func _column(preset: Control.LayoutPreset, offset: Vector2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_root.add_child(box)
	box.set_anchors_and_offsets_preset(preset)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if preset == Control.PRESET_TOP_LEFT:
		box.grow_horizontal = Control.GROW_DIRECTION_END
	elif preset == Control.PRESET_TOP_RIGHT:
		box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.position += offset
	return box


func _label(parent: Node, size: int, centred := false) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centred:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _bar(parent: Node, color: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(DARK, 0.85)
	back.set_border_width_all(2)
	back.border_color = DARK
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_border_width_all(2)
	fill.border_color = DARK
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar
