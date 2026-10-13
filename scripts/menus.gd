extends CanvasLayer
## Every screen over the game: the title and hero select, the co-op room screens, the upgrade
## cards after a level-up or a chest, the pause menu and the game-over screen. It keeps
## working while the tree is paused. Buttons take the mouse, a tap, the arrow keys or a
## gamepad; cards also take 1-3. Each screen lays itself out for a wide or an upright window
## and is rebuilt when the window changes shape (`relayout`).

const Db := preload("res://scripts/db.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Save := preload("res://scripts/save.gd")
const Touch := preload("res://scripts/touch.gd")
const FONT := preload("res://fonts/PixelifySans.ttf")
const INK := Color("ffd9a0")
const DARK := Color("1a1026")
const PANEL := Color("2a1c3c")
const EDGE := Color("e0702a")
const GOLD := Color("ffd060")

signal hero_focused(hero: String)
signal hero_chosen(hero: String)
signal test_chosen(hero: String)
signal upgrade_chosen(id: String)
signal resumed
signal retried
signal quit_to_title
signal coop_opened
signal coop_created
signal coop_joined(code: String)
signal coop_hero_picked(hero: String)
signal coop_started
signal sound_toggled

var _dim: ColorRect
var _box: VBoxContainer
var _cards: Array[Button] = []
var _hero := "joe"
## The screen that is up, so it can be drawn again for a new window shape.
var _again := Callable()
var _upright := false
var _hero_cards := {}
var _play: Button
var _note := ""


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(_box)
	close()


func close() -> void:
	visible = false
	_again = Callable()
	_clear()


## Draws the open screen again (the window changed shape, or the sound was switched).
func relayout() -> void:
	if visible and _again.is_valid():
		_again.call()


func _clear() -> void:
	_cards.clear()
	_hero_cards.clear()
	_play = null
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()


## `note` is shown under the title (why a co-op game ended, say).
func title(hero: String, note := "") -> void:
	_note = note
	_open(0.3, _title_again)
	_hero = hero
	_text("OCTOBER\nVALLEY" if _upright else "OCTOBER VALLEY", 84, EDGE)
	_text(note if note != "" else "Find the altar. Beat the boss. Take the portal.", 22, GOLD if note != "" else INK)
	var grid := GridContainer.new()
	grid.columns = 2 if _upright else 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(grid)
	for id in Db.HERO_ORDER:
		var def: Dictionary = Db.HEROES[id]
		var weapon: Dictionary = Db.WEAPONS[def["weapon"]]
		var best: Dictionary = Save.best(id)
		var record := "BEST  %s" % _commas(int(best["score"])) if best.has("score") else ""
		var card := _card(grid, Db.icon(weapon["icon"]), def["name"], weapon["name"], def["perk"], Vector2(276, 206) if _upright else Vector2(232, 232), record)
		_hero_cards[id] = card
		card.focus_entered.connect(_select_hero.bind(id))
		card.pressed.connect(func() -> void:
			_select_hero(id)
			# a tap only chooses; with a mouse or a key the pointer was already on the card
			if not Touch.active:
				hero_chosen.emit(id))
		if id == hero:
			_focus_soon(card)
	var extras := _row()
	_play = _button("PLAY AS %s" % Db.HEROES[hero]["name"].to_upper(), func() -> void: hero_chosen.emit(_hero), 30, _box if _upright else extras)
	_play.custom_minimum_size = Vector2(566 if _upright else 300, 60)
	_skin(_play, true)
	if _upright:
		_box.move_child(_play, extras.get_index())
	_button("CO-OP", func() -> void: coop_opened.emit(), 24, extras).custom_minimum_size = Vector2(180, 52)
	if not Touch.active:
		_button("TEST YARD", func() -> void: test_chosen.emit(_hero), 24, extras).custom_minimum_size = Vector2(180, 52)
	_sound_button(extras)
	if Touch.active:
		_text("Left thumb moves, right thumb looks. Weapons fire by themselves.", 18)
	else:
		_text("WASD move   Mouse look   Space jump (x2)   Shift sprint   E interact   Esc pause   M sound", 18)
	_mark_hero()


func _title_again() -> void:
	title(_hero, _note)


func _select_hero(id: String) -> void:
	var changed := id != _hero
	_hero = id
	_mark_hero()
	if changed:
		hero_focused.emit(id)


func _mark_hero() -> void:
	for id: String in _hero_cards:
		_skin(_hero_cards[id], id == _hero)
	if _play:
		_play.text = "PLAY AS %s" % Db.HEROES[_hero]["name"].to_upper()


## `heading` is LEVEL UP or TREASURE. `player` words each card for what it already owns.
func upgrades(heading: String, ids: Array[String], player: Node) -> void:
	_open(0.55, upgrades.bind(heading, ids, player))
	var top := _text(heading, 64, GOLD if heading == "TREASURE" else EDGE)
	var holder: BoxContainer = VBoxContainer.new() if _upright else _row()
	if _upright:
		holder.add_theme_constant_override("separation", 12)
		_box.add_child(holder)
	for i in ids.size():
		var id := ids[i]
		var words: Array = player.describe_upgrade(id)
		var card := _card(holder, Db.icon(Db.upgrade_def(id)["icon"]), words[0] if Touch.active else "%d. %s" % [i + 1, words[0]], words[1], words[2], Vector2(552, 150) if _upright else Vector2(250, 290), "", _upright)
		card.pressed.connect(func() -> void: upgrade_chosen.emit(id))
		_cards.append(card)
		# the cards drop in one after the other
		card.modulate.a = 0.0
		var tween := card.create_tween()
		tween.tween_interval(0.07 * i)
		tween.tween_property(card, "modulate:a", 1.0, 0.16)
	_focus_soon(_cards[0])
	top.pivot_offset = Vector2(top.get_combined_minimum_size().x * 0.5, 40)
	top.scale = Vector2(1.5, 1.5)
	top.create_tween().tween_property(top, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Co-op, before a room: make one, or join one with its code.
func coop(note := "") -> void:
	_open(0.6, coop.bind(note))
	_text("CO-OP", 64, EDGE)
	if note != "":
		_text(note, 26, Color("ff6a5a"))
	_text("Up to four heroes, one horde. Make a room and share its code.", 22)
	_focus_soon(_button("MAKE A ROOM", func() -> void: coop_created.emit()))
	var row := _row()
	var entry := LineEdit.new()
	entry.placeholder_text = "CODE"
	entry.max_length = 4
	entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.custom_minimum_size = Vector2(200, 60)
	entry.virtual_keyboard_enabled = true
	entry.add_theme_font_override("font", ThemeDB.fallback_font)
	entry.add_theme_font_size_override("font_size", 34)
	entry.text_changed.connect(func(typed: String) -> void:
		var caret := entry.caret_column
		entry.text = typed.to_upper()
		entry.caret_column = caret)
	row.add_child(entry)
	var join := func() -> void:
		var code := entry.text.strip_edges().to_upper()
		if code.length() == 4:
			coop_joined.emit(code)
		else:
			coop("A room code is four letters or numbers.")
	entry.text_submitted.connect(func(_text: String) -> void: join.call())
	_button("JOIN", join, 30, row).custom_minimum_size = Vector2(160, 60)
	_button("BACK", func() -> void: quit_to_title.emit())


## The room, before the game starts. `players` is [{slot, name, hero, away}].
func lobby(code: String, players: Array, my_seat: int, leader: bool) -> void:
	_open(0.6, lobby.bind(code, players, my_seat, leader))
	_text("ROOM CODE", 34, EDGE)
	var plain := _text("  ".join(code.split("")), 72)
	plain.add_theme_font_override("font", ThemeDB.fallback_font)
	_text("Friends join with this code from CO-OP on the title screen. Keep this window in view: a hidden tab stops the game.", 18)
	for entry: Dictionary in players:
		var seat := int(entry["slot"])
		var who: String = Db.HEROES[str(entry["hero"])]["name"] if Db.HEROES.has(str(entry["hero"])) else "?"
		_text("P%d   %s%s%s" % [seat + 1, who.to_upper(), "   (YOU)" if seat == my_seat else "", "   (AWAY)" if entry.get("away", false) else ""], 26, GOLD if seat == my_seat else INK)
	var grid := GridContainer.new()
	grid.columns = 2 if _upright else 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(grid)
	for id in Db.HERO_ORDER:
		_button(Db.HEROES[id]["name"].to_upper(), func() -> void: coop_hero_picked.emit(id), 24, grid).custom_minimum_size = Vector2(150, 52)
	var row := _row()
	if leader:
		var start := _button("START", func() -> void: coop_started.emit(), 30, row)
		start.custom_minimum_size = Vector2(240, 56)
		_skin(start, true)
		_focus_soon(start)
	else:
		_text("Waiting for P1 to start...", 24)
	_button("LEAVE", func() -> void: quit_to_title.emit(), 30, row).custom_minimum_size = Vector2(200, 56)


## A message while waiting on the server or the host, with a way out.
func notice(text: String) -> void:
	_open(0.6, notice.bind(text))
	_text(text, 34)
	_focus_soon(_button("BACK", func() -> void: quit_to_title.emit()))


## `frozen`: the game is stopped behind this (it is not in co-op).
func pause(frozen := true) -> void:
	_open(0.6, pause.bind(frozen))
	_text("PAUSED" if frozen else "MENU", 64, EDGE)
	_focus_soon(_button("RESUME", func() -> void: resumed.emit()))
	_sound_button(_box).custom_minimum_size = Vector2(320, 0)
	_button("QUIT TO TITLE", func() -> void: quit_to_title.emit())
	if Touch.active:
		_text("Left thumb moves, right thumb looks. RUN stays on until you tap it again.", 18)
	else:
		_text("WASD move   Space jump (x2)   Shift sprint   E interact   M sound", 18)


## The end of a run. `lines` are small print; `score` and `best` are shown large ("" = leave
## out). `can_retry` is false in co-op, where the only way on is back to the title.
func game_over(lines: Array, can_retry := true, score := "", best := "") -> void:
	_open(0.72, game_over.bind(lines, can_retry, score, best))
	_text("YOU DIED", 84, Color("d83a4a"))
	if score != "":
		_text(score, 44, GOLD)
	if best != "":
		_text(best, 24, EDGE)
	for line: String in lines:
		_text(line, 22)
	var row := _row()
	if can_retry:
		var again := _button("TRY AGAIN", func() -> void: retried.emit(), 30, row)
		again.custom_minimum_size = Vector2(260, 60)
		_skin(again, true)
		_focus_soon(again)
		_button("TITLE", func() -> void: quit_to_title.emit(), 30, row).custom_minimum_size = Vector2(200, 60)
	else:
		_focus_soon(_button("TITLE", func() -> void: quit_to_title.emit(), 30, row))


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	var index := key.physical_keycode - KEY_1
	if index >= 0 and index < _cards.size():
		get_viewport().set_input_as_handled()
		_cards[index].pressed.emit()


func _open(dim: float, again: Callable) -> void:
	_clear()
	_again = again
	visible = true
	_dim.color = Color(DARK, dim)
	var view := get_viewport().get_visible_rect().size
	_upright = view.y > view.x


func _commas(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


func _text(text: String, size: int, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", maxi(size / 6, 4))
	label.add_theme_constant_override("line_spacing", -8 if size > 60 else 0)
	if size <= 34:
		# small print wraps instead of running off a narrow screen
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = minf(get_viewport().get_visible_rect().size.x - 40.0, 1000.0)
	_box.add_child(label)
	return label


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_box.add_child(row)
	return row


func _sound_button(parent: Node) -> Button:
	var button := _button("SOUND OFF" if Sfx.muted() else "SOUND ON", func() -> void: sound_toggled.emit(), 24, parent)
	button.custom_minimum_size = Vector2(180, 52)
	return button


func _button(text: String, action: Callable, size := 30, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 56)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", GOLD)
	_skin(button)
	_wire(button)
	button.pressed.connect(action)
	(parent if parent else _box).add_child(button)
	return button


## Hover takes the focus, and moving and pressing make their sounds.
func _wire(button: Button) -> void:
	button.mouse_entered.connect(button.grab_focus)
	button.focus_entered.connect(func() -> void: Sfx.play("move", 0.6))
	button.pressed.connect(func() -> void: Sfx.play("pick"))


## A button with an icon, a name, a tag line, a description and an optional footnote. `wide`
## puts the icon beside the words instead of above them (upright screens).
func _card(parent: Node, icon: Texture2D, heading: String, tag: String, body: String, card_size: Vector2, foot := "", wide := false) -> Button:
	var card := Button.new()
	card.custom_minimum_size = card_size
	_skin(card)
	_wire(card)
	parent.add_child(card)
	var layout: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 12
	layout.offset_right = -12
	layout.offset_top = 10
	layout.offset_bottom = -10
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 16 if wide else 2)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(layout)
	var picture := TextureRect.new()
	picture.texture = icon
	var icon_size := 96.0 if wide or card_size.y > 260.0 else 72.0
	picture.custom_minimum_size = Vector2(icon_size, icon_size)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(picture)
	var words: BoxContainer = layout
	if wide:
		words = VBoxContainer.new()
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(words)
	for part: Array in [[heading, 26, INK], [tag, 18, EDGE], [body, 18, INK], [foot, 16, GOLD]]:
		if part[0] == "":
			continue
		var label := Label.new()
		label.text = part[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", part[1])
		label.add_theme_color_override("font_color", part[2])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(label)
	return card


## `chosen` gives the button the bright border all the time, not only under the pointer.
func _skin(button: Button, chosen := false) -> void:
	for state: String in ["normal", "hover", "focus", "pressed"]:
		var lit := chosen or state != "normal"
		var box := StyleBoxFlat.new()
		box.bg_color = PANEL.lightened(0.12) if state != "normal" else (PANEL.lightened(0.06) if chosen else PANEL)
		box.border_color = EDGE if lit else DARK
		box.set_border_width_all(4)
		box.set_corner_radius_all(4)
		box.set_content_margin_all(10)
		button.add_theme_stylebox_override(state, box)


## Gives `button` the focus once it is on screen, unless the screen has changed by then.
func _focus_soon(button: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(button) and button.is_inside_tree() and visible:
		button.grab_focus()
