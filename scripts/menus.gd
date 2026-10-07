extends CanvasLayer
## Every screen over the game: the title and hero select, the co-op room screens, the upgrade
## cards after a level-up or a chest, the pause menu and the game-over screen. It keeps
## working while the tree is paused. Buttons take the mouse, the arrow keys or a gamepad;
## cards also take 1-3.

const Db := preload("res://scripts/db.gd")
const FONT := preload("res://fonts/PixelifySans.ttf")
const INK := Color("ffd9a0")
const DARK := Color("1a1026")
const PANEL := Color("2a1c3c")
const EDGE := Color("e0702a")

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

var _dim: ColorRect
var _box: VBoxContainer
var _cards: Array[Button] = []
var _hero := "joe"


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
	_box.add_theme_constant_override("separation", 18)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(_box)
	close()


func close() -> void:
	visible = false
	_cards.clear()
	for child in _box.get_children():
		child.queue_free()


## `note` is shown under the title (why a co-op game ended, say).
func title(hero: String, note := "") -> void:
	_open(0.25)
	_hero = hero
	_text("OCTOBER VALLEY", 96, EDGE)
	_text(note if note != "" else "Pick a hero. Find the altar, beat the boss, take the portal.", 22)
	var row := _row()
	for id in Db.HERO_ORDER:
		var def: Dictionary = Db.HEROES[id]
		var weapon: Dictionary = Db.WEAPONS[def["weapon"]]
		var card := _card(row, Db.icon(weapon["icon"]), def["name"], weapon["name"], def["perk"])
		card.focus_entered.connect(func() -> void:
			_hero = id
			hero_focused.emit(id))
		card.mouse_entered.connect(card.grab_focus)
		card.pressed.connect(func() -> void: hero_chosen.emit(id))
		if id == hero:
			card.grab_focus.call_deferred()
	var extras := _row()
	_button("CO-OP", func() -> void: coop_opened.emit(), 24, extras)
	_button("TEST YARD", func() -> void: test_chosen.emit(_hero), 24, extras)
	_text("WASD move   Mouse look   Space jump (x2)   Shift sprint   E interact   Esc pause", 18)


## `heading` is LEVEL UP or TREASURE. `player` words each card for what it already owns.
func upgrades(heading: String, ids: Array[String], player: Node) -> void:
	_open(0.55)
	_text(heading, 64, EDGE)
	var row := _row()
	for i in ids.size():
		var id := ids[i]
		var words: Array = player.describe_upgrade(id)
		var card := _card(row, Db.icon(Db.upgrade_def(id)["icon"]), "%d. %s" % [i + 1, words[0]], words[1], words[2])
		card.mouse_entered.connect(card.grab_focus)
		card.pressed.connect(func() -> void: upgrade_chosen.emit(id))
		_cards.append(card)
	_cards[0].grab_focus.call_deferred()


## Co-op, before a room: make one, or join one with its code.
func coop(note := "") -> void:
	_open(0.6)
	_text("CO-OP", 64, EDGE)
	if note != "":
		_text(note, 28, Color("ff6a5a"))
	_text("Up to four heroes, one horde. Make a room and share its code.", 22)
	_button("MAKE A ROOM", func() -> void: coop_created.emit()).grab_focus.call_deferred()
	var row := _row()
	var entry := LineEdit.new()
	entry.placeholder_text = "CODE"
	entry.max_length = 4
	entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.custom_minimum_size = Vector2(200, 0)
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
	_button("JOIN", join, 30, row).custom_minimum_size = Vector2(160, 0)
	_button("BACK", func() -> void: quit_to_title.emit())


## The room, before the game starts. `players` is [{slot, name, hero, away}].
func lobby(code: String, players: Array, my_seat: int, leader: bool) -> void:
	_open(0.6)
	_text("ROOM CODE", 40, EDGE)
	var plain := _text("  ".join(code.split("")), 84)
	plain.add_theme_font_override("font", ThemeDB.fallback_font)
	_text("Friends join with this code from CO-OP on the title screen.", 22)
	_text("Keep this window in view: a hidden browser tab stops the game.", 18)
	for entry: Dictionary in players:
		var seat := int(entry["slot"])
		var who: String = Db.HEROES[str(entry["hero"])]["name"] if Db.HEROES.has(str(entry["hero"])) else "?"
		_text("P%d   %s%s%s" % [seat + 1, who.to_upper(), "   (YOU)" if seat == my_seat else "", "   (AWAY)" if entry.get("away", false) else ""], 28)
	var row := _row()
	for id in Db.HERO_ORDER:
		_button(Db.HEROES[id]["name"].to_upper(), func() -> void: coop_hero_picked.emit(id), 24, row).custom_minimum_size = Vector2(150, 0)
	if leader:
		_button("START", func() -> void: coop_started.emit()).grab_focus.call_deferred()
	else:
		_text("Waiting for P1 to start...", 24)
	_button("LEAVE", func() -> void: quit_to_title.emit())


## A message while waiting on the server or the host, with a way out.
func notice(text: String) -> void:
	_open(0.6)
	_text(text, 36)
	_button("BACK", func() -> void: quit_to_title.emit()).grab_focus.call_deferred()


## `frozen`: the game is stopped behind this (it is not in co-op).
func pause(frozen := true) -> void:
	_open(0.55)
	_text("PAUSED" if frozen else "MENU", 64, EDGE)
	_button("RESUME", func() -> void: resumed.emit()).grab_focus.call_deferred()
	_button("QUIT TO TITLE", func() -> void: quit_to_title.emit())


## `can_retry` is false in co-op, where the only way on is back to the title.
func game_over(lines: Array, can_retry := true) -> void:
	_open(0.7)
	_text("YOU DIED", 96, Color("d83a4a"))
	for line: String in lines:
		_text(line, 26)
	if can_retry:
		_button("TRY AGAIN", func() -> void: retried.emit()).grab_focus.call_deferred()
		_button("TITLE", func() -> void: quit_to_title.emit())
	else:
		_button("TITLE", func() -> void: quit_to_title.emit()).grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	var index := key.physical_keycode - KEY_1
	if index >= 0 and index < _cards.size():
		get_viewport().set_input_as_handled()
		_cards[index].pressed.emit()


func _open(dim: float) -> void:
	close()
	visible = true
	_dim.color = Color(DARK, dim)


func _text(text: String, size: int, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", maxi(size / 6, 4))
	_box.add_child(label)
	return label


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	_box.add_child(row)
	return row


func _button(text: String, action: Callable, size := 30, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", INK)
	_skin(button)
	button.mouse_entered.connect(button.grab_focus)
	button.pressed.connect(action)
	(parent if parent else _box).add_child(button)
	return button


## A tall button with an icon, a name, a tag line and a description.
func _card(row: HBoxContainer, icon: Texture2D, heading: String, tag: String, body: String) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(250, 300)
	_skin(card)
	row.add_child(card)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 14
	column.offset_right = -14
	column.offset_top = 14
	column.offset_bottom = -14
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var picture := TextureRect.new()
	picture.texture = icon
	picture.custom_minimum_size = Vector2(96, 96)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(picture)
	for part: Array in [[heading, 26, INK], [tag, 18, EDGE], [body, 18, INK]]:
		var label := Label.new()
		label.text = part[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", part[1])
		label.add_theme_color_override("font_color", part[2])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
	return card


func _skin(button: Button) -> void:
	for state: String in ["normal", "hover", "focus", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = PANEL if state == "normal" else PANEL.lightened(0.12)
		box.border_color = DARK if state == "normal" else EDGE
		box.set_border_width_all(4)
		box.set_content_margin_all(10)
		button.add_theme_stylebox_override(state, box)
