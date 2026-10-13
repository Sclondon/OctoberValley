extends CanvasLayer
## The in-run display: the experience bar across the top; health, level and what you carry
## (top left); the stage, clock and objective (top middle) with the boss's health under it;
## kills, how dangerous the night has become and the rest of the team (top right); a marker
## that points at the altar; the interact prompt; banners; and a red edge when hurt or nearly
## dead. `relayout` fits it to a wide or an upright screen.

const Db := preload("res://scripts/db.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Fx := preload("res://scripts/fx.gd")
const Touch := preload("res://scripts/touch.gd")
const FONT := preload("res://fonts/PixelifySans.ttf")
const INK := Color("ffd9a0")
const DARK := Color("1a1026")
const EDGE := Color("e0702a")
## Below this share of health the screen's edge pulses and a heart beats.
const LOW_HEALTH := 0.3
## The night gets a new name as the difficulty passes each of these.
const DANGER := [[1.5, "CALM", "70e090"], [2.2, "UNEASY", "c8e070"], [3.0, "SPOOKY", "ffd060"],
	[4.0, "HAUNTED", "ffa040"], [5.5, "CURSED", "ff6a3a"], [7.5, "NIGHTMARE", "ff3a3a"], [1.0e9, "ALL HALLOWS", "ff30c0"]]
const EDGE_SHADER := "shader_type canvas_item;
uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(0.78, 0.04, 0.06);
void fragment() {
	float away = length(UV - 0.5) * 1.25;
	COLOR = vec4(tint, smoothstep(0.42, 0.9, away) * strength);
}"

## Main, read for the stage title, the altar and the test-yard flag.
var main: Node
var player: Node3D
var director: Node

var _root: Control
var _left: VBoxContainer
var _middle: VBoxContainer
var _right: VBoxContainer
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
var _danger: Label
var _team: Label
var _items: HFlowContainer
var _prompt: Label
var _banner: Label
var _banner_sub: Label
var _banner_box: VBoxContainer
var _flash: ColorRect
var _edge: ShaderMaterial
var _marker: Node2D
var _marker_arrow: Polygon2D
var _marker_text: Label
var _banner_tween: Tween
var _hurt := 0.0
var _clock := 0.0
var _beat := 0.0
var _boss_shown := 0.0


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var edge := ColorRect.new()
	var shader := Shader.new()
	shader.code = EDGE_SHADER
	_edge = ShaderMaterial.new()
	_edge.shader = shader
	edge.material = _edge
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(edge)

	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.85, 0.4, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	_marker = Node2D.new()
	_root.add_child(_marker)
	_marker_arrow = Polygon2D.new()
	_marker_arrow.polygon = PackedVector2Array([Vector2(16, 0), Vector2(-10, -12), Vector2(-4, 0), Vector2(-10, 12)])
	_marker.add_child(_marker_arrow)
	var arrow_edge := Line2D.new()
	arrow_edge.points = PackedVector2Array([Vector2(16, 0), Vector2(-10, -12), Vector2(-4, 0), Vector2(-10, 12), Vector2(16, 0)])
	arrow_edge.width = 3.0
	arrow_edge.default_color = DARK
	_marker_arrow.add_child(arrow_edge)
	_marker_text = _label(_marker, 20, true)
	_marker_text.custom_minimum_size = Vector2(120, 0)
	_marker_text.position = Vector2(-60, 16)

	_xp = _bar(_root, Color("f0a030"), Vector2(0, 12))
	_xp.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_xp.offset_bottom = 12.0

	_left = _column()
	_name = _label(_left, 26)
	_health = _bar(_left, Color("d83a4a"), Vector2(280, 26))
	_health.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_health_text = _label(_health, 18)
	_health_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_items = HFlowContainer.new()
	_items.add_theme_constant_override("h_separation", 4)
	_items.add_theme_constant_override("v_separation", 4)
	_items.custom_minimum_size.x = 280
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(_items)

	_middle = _column()
	_stage = _label(_middle, 24, true)
	_objective = _label(_middle, 20, true)
	_boss_box = VBoxContainer.new()
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_middle.add_child(_boss_box)
	_boss_name = _label(_boss_box, 26, true)
	_boss_name.add_theme_color_override("font_color", Color("ff7a5a"))
	_boss_bar = _bar(_boss_box, Color("c8201c"), Vector2(520, 20))
	_boss_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_right = _column()
	_stats = _label(_right, 22)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_danger = _label(_right, 20)
	_danger.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_team = _label(_right, 18)
	_team.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_prompt = _label(_root, 28, true)
	_banner_box = _column()
	_banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner = _label(_banner_box, 64, true)
	_banner_sub = _label(_banner_box, 26, true)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0

	player.inventory_changed.connect(_show_items)
	player.hurt_taken.connect(_on_hurt)
	_show_items()
	relayout()


## Places everything for the screen's shape. Main calls this when the window changes.
func relayout() -> void:
	var view := get_viewport().get_visible_rect().size
	var upright := view.y > view.x
	var touch := Touch.active
	_left.position = Vector2(14, 20)
	_left.size = Vector2(280, 0)
	# on a phone the pause button has the corner
	_right.size = Vector2(200, 0)
	_right.position = Vector2(view.x - 214 - (58 if touch else 0), 20)
	var middle_width := minf(view.x - 28.0, 560.0)
	_middle.size = Vector2(middle_width, 0)
	_middle.position = Vector2((view.x - middle_width) * 0.5, 176 if upright else 20)
	_boss_bar.custom_minimum_size.x = minf(520.0, middle_width)
	_prompt.size = Vector2(view.x, 40)
	_prompt.position = Vector2(0, view.y * (0.62 if upright else 0.7))
	_banner.add_theme_font_size_override("font_size", 46 if upright else 64)
	_banner_box.size = Vector2(view.x - 24.0, 0)
	_banner_box.position = Vector2(12, view.y * (0.24 if upright else 0.2))


## Big text across the middle that fades after a moment.
func banner(text: String, sub := "", color := INK) -> void:
	_banner.text = text
	_banner_sub.text = sub
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_sub.modulate.a = 1.0
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(1.3, 1.3)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(2.2)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.8)
	_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.8)


## A wash of colour over the screen that fades at once (the level-up).
func flash(color: Color, strength := 0.3) -> void:
	_flash.color = Color(color, strength)
	# the cards come up over a level-up and stop the game: this must fade all the same
	get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(_flash, "color:a", 0.0, 0.45)


func _process(delta: float) -> void:
	_clock += delta
	_name.text = "%s   LV %d" % [Db.HEROES[player.hero]["name"].to_upper(), player.level]
	_health.max_value = player.max_hp()
	_health.value = player.hp
	_health_text.text = "%d / %d" % [ceili(player.hp), int(player.max_hp())]
	_xp.max_value = player.xp_needed()
	_xp.value = player.xp
	var seconds := int(director.time)
	_stage.text = "%s   %d:%02d" % [main.stage_title, seconds / 60, seconds % 60]
	_stats.text = "KILLS %d" % player.kills
	var level: float = director.difficulty()
	for tier: Array in DANGER:
		if level < tier[0]:
			_danger.text = tier[1]
			_danger.add_theme_color_override("font_color", Color(str(tier[2])))
			break
	# co-op: the rest of the team
	var team := ""
	for seat: int in main.heroes:
		var mate: Node3D = main.heroes[seat]
		if mate != player:
			team += "P%d %s  %s\n" % [seat + 1, Db.HEROES[mate.hero]["name"].to_upper(),
				"DOWN" if mate.dead else "%d / %d" % [ceili(mate.hp), int(mate.max_hp())]]
	_team.text = team.strip_edges()
	_team.visible = team != ""

	var boss: Dictionary = main.boss_info()
	_boss_box.visible = not boss.is_empty()
	if not boss.is_empty():
		_boss_shown += delta
		_boss_name.text = boss["title"] + ("  (ENRAGED)" if boss["enraged"] else "")
		_boss_bar.max_value = boss["max_hp"]
		# the bar fills as the boss arrives
		_boss_bar.value = boss["hp"] * minf(_boss_shown / 1.0, 1.0)
	else:
		_boss_shown = 0.0

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
				var charged := int(altar.charge * 100.0)
				if not boss.is_empty() and altar.charge < 1.0:
					_objective.text = "Defeat the boss   Altar %d%%" % charged
				elif not boss.is_empty():
					_objective.text = "Altar charged: defeat the boss"
				elif away > altar.CHARGE_RADIUS:
					_objective.text = "Get back in the ring: altar %d%%" % charged
				else:
					_objective.text = "Hold the ring: altar %d%%" % charged
			"portal":
				_objective.text = "Enter the portal: %d m" % away
		var offer: String = main.prompt_text()
		if offer != "":
			_prompt.text = offer if Touch.active else "[E]  %s" % offer
	if player.dead and main.state == "playing":
		_prompt.text = "You are down. You get back up on the next stage."
	_point_at_altar(altar)

	# the red edge: a spike when hit, a slow pulse when nearly dead
	_hurt = maxf(_hurt - delta * 2.5, 0.0)
	var low: bool = not player.dead and player.active and player.hp < player.max_hp() * LOW_HEALTH
	var pulse := 0.6 + 0.25 * sin(_clock * 6.0) if low else 0.0
	_edge.set_shader_parameter("strength", maxf(_hurt * 0.75, pulse))
	_health_text.add_theme_color_override("font_color", Color("ff8a8a") if low and fmod(_clock, 0.5) < 0.25 else INK)
	_beat -= delta
	if low and _beat <= 0.0 and main.state == "playing":
		_beat = 0.85
		Sfx.play("beat", 0.9)


## An arrow at the edge of the screen toward the altar, or a mark over it when it is in view.
func _point_at_altar(altar: Node3D) -> void:
	var cam := get_viewport().get_camera_3d()
	if altar == null or cam == null or main.in_test or player.dead:
		_marker.visible = false
		return
	var away := altar.global_position.distance_to(player.global_position)
	_marker.visible = away > 14.0
	if not _marker.visible:
		return
	var view := get_viewport().get_visible_rect().size
	var centre := view * 0.5
	var aim: Vector3 = altar.global_position + Vector3.UP * 3.0
	var spot := cam.unproject_position(aim)
	var behind := cam.is_position_behind(aim)
	if behind:
		spot = centre * 2.0 - spot
	var inset := Rect2(Vector2(60, 150), view - Vector2(120, 330))
	var color: Color = altar.COLORS[altar.state].lightened(0.25)
	_marker_arrow.color = color
	_marker_text.text = "%d m" % int(away)
	_marker_text.add_theme_color_override("font_color", color)
	if not behind and inset.has_point(spot):
		_marker.position = spot
		_marker_arrow.rotation = PI * 0.5
		_marker_arrow.position = Vector2(0, -6 + sin(_clock * 5.0) * 4.0)
	else:
		var dir := (spot - centre).normalized()
		if behind and absf(dir.y) > 0.9:
			dir = Vector2(signf(dir.x) if dir.x != 0.0 else 1.0, 0.3).normalized()
		# out from the centre until it meets the inset's edge
		var reach := minf(
			(inset.size.x * 0.5) / maxf(absf(dir.x), 0.001),
			(inset.size.y * 0.5) / maxf(absf(dir.y), 0.001))
		_marker.position = inset.get_center() + dir * reach
		_marker_arrow.position = Vector2.ZERO
		_marker_arrow.rotation = dir.angle()


func _on_hurt(amount: float) -> void:
	_hurt = 1.0
	Sfx.play("hurt", 1.0, randf_range(0.92, 1.08))
	Fx.shake(clampf(0.3 + amount / 60.0, 0.3, 0.8))


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
	icon.custom_minimum_size = Vector2(42, 42)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var number := _label(icon, 18)
	number.text = str(item_level)
	number.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	number.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	number.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_items.add_child(icon)


func _column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_root.add_child(box)
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
