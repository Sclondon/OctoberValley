extends Control
## Touch controls, for phones and tablets. They stay hidden until a finger touches the screen
## (or the game is started with --touch / ?touch).
##
##   left half     a stick that appears under the thumb: move
##   right half    drag to look around
##   JUMP, RUN     bottom right. RUN stays on until tapped again
##   USE           appears when there is something to use (the altar, the portal)
##   II            pause, top right
##
## Menus are ordinary buttons and take taps by themselves. Several fingers work at once.

const FONT := preload("res://fonts/PixelifySans.ttf")
const Flags := preload("res://scripts/flags.gd")

const STICK_RADIUS := 78.0
## Radians of camera turn per UI pixel dragged.
const LOOK_SENS := 0.0062
const INK := Color("ffd9a0")
const DARK := Color("1a1026")
const EDGE := Color("e0702a")

## True once the game knows it is being played by touch. The camera reads this so that a
## tap is not taken for a mouse click.
static var active := false

signal became_active

## Main, read for the state, the camera and the interact prompt.
var main: Node
var run_latched := false

var _stick_finger := -1
var _stick_from := Vector2.ZERO
var _stick := Vector2.ZERO
var _look_finger := -1
## button -> the finger holding it (-1 = none)
var _held := {"jump": -1, "run": -1, "use": -1, "pause": -1}
var _spots := {}
var _use_shown := false
var _clock := 0.0
var _forced := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_forced = Flags.all().has("touch")
	if _forced or _is_phone():
		_activate.call_deferred()


## True in a browser whose main pointer is a finger (a phone or tablet, not a laptop that
## happens to have a touch screen).
func _is_phone() -> bool:
	if not OS.has_feature("web"):
		return false
	var coarse: Variant = JavaScriptBridge.eval("navigator.maxTouchPoints > 0 && window.matchMedia('(pointer: coarse)').matches")
	return coarse is bool and coarse


func _activate() -> void:
	if active:
		return
	active = true
	became_active.emit()


## Back to keyboard and mouse: someone with both pressed a key.
func _deactivate() -> void:
	release_all()
	active = false


## Where each button's centre is and how big it is, for the current screen shape.
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	size = view  # the anchors are slow to follow a window that changes shape
	var w := view.x
	var h := view.y
	var lift := 60.0 if h > w else 0.0  # clear of the home bar on an upright phone
	_spots = {
		"jump": [Vector2(w - 96.0, h - 110.0 - lift), 62.0, "JUMP"],
		"run": [Vector2(w - 224.0, h - 76.0 - lift), 44.0, "RUN"],
		"use": [Vector2(w - 84.0, h - 250.0 - lift), 48.0, "USE"],
		"pause": [Vector2(w - 40.0, 52.0), 26.0, "II"],
	}


func playing() -> bool:
	return main != null and main.state == "playing"


func _process(delta: float) -> void:
	visible = active and playing()
	if not visible:
		if _stick_finger != -1 or _look_finger != -1 or run_latched or _held["jump"] != -1:
			release_all()
		return
	_clock += delta
	_use_shown = main.prompt_text() != ""
	queue_redraw()


## Lets go of everything (a menu opened, or the run ended).
func release_all() -> void:
	_stick_finger = -1
	_look_finger = -1
	_stick = Vector2.ZERO
	run_latched = false
	for button: String in _held:
		_held[button] = -1
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "jump", "sprint"]:
		Input.action_release(action)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_activate()
		if not playing():
			return
		if event.pressed:
			_down(event.index, event.position)
		else:
			_up(event.index)
	elif event is InputEventKey and event.pressed and active and not _forced and playing():
		_deactivate()
	elif event is InputEventScreenDrag and playing():
		_drag(event.index, event.position, event.relative)


func _down(finger: int, at: Vector2) -> void:
	_layout()
	for button: String in _spots:
		if button == "use" and not _use_shown:
			continue
		var spot: Array = _spots[button]
		var centre: Vector2 = spot[0]
		if at.distance_to(centre) > float(spot[1]) * 1.3:
			continue
		_held[button] = finger
		match button:
			"jump":
				Input.action_press("jump")
			"run":
				run_latched = not run_latched
				if run_latched:
					Input.action_press("sprint")
				else:
					Input.action_release("sprint")
			"use":
				_tap("interact")
			"pause":
				_tap("pause")
		return
	if at.x < get_viewport().get_visible_rect().size.x * 0.5:
		if _stick_finger == -1:
			_stick_finger = finger
			_stick_from = at
			_stick = Vector2.ZERO
	elif _look_finger == -1:
		_look_finger = finger


func _up(finger: int) -> void:
	if finger == _stick_finger:
		_stick_finger = -1
		_stick = Vector2.ZERO
		_apply_stick()
	if finger == _look_finger:
		_look_finger = -1
	for button: String in _held:
		if _held[button] == finger:
			_held[button] = -1
			if button == "jump":
				Input.action_release("jump")


func _drag(finger: int, at: Vector2, by: Vector2) -> void:
	if finger == _stick_finger:
		var pull := at - _stick_from
		if pull.length() > STICK_RADIUS:
			# the stick's base follows a thumb that has gone past its edge
			_stick_from = at - pull.normalized() * STICK_RADIUS
			pull = at - _stick_from
		_stick = pull / STICK_RADIUS
		_apply_stick()
	elif finger == _look_finger and main.cam:
		main.cam.turn(by * LOOK_SENS)


func _apply_stick() -> void:
	_push("move_right", _stick.x)
	_push("move_left", -_stick.x)
	_push("move_back", _stick.y)
	_push("move_forward", -_stick.y)


func _push(action: String, strength: float) -> void:
	if strength > 0.05:
		Input.action_press(action, minf(strength, 1.0))
	else:
		Input.action_release(action)


func _tap(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _draw() -> void:
	_layout()
	# the stick: where the thumb is, or a faint ring where it could go
	if _stick_finger != -1:
		draw_circle(_stick_from, STICK_RADIUS, Color(DARK, 0.3))
		draw_arc(_stick_from, STICK_RADIUS, 0.0, TAU, 48, Color(INK, 0.5), 3.0)
		draw_circle(_stick_from + _stick * STICK_RADIUS, 34.0, Color(INK, 0.55))
	else:
		var view := get_viewport().get_visible_rect().size
		var lift := 60.0 if view.y > view.x else 0.0
		var rest := Vector2(130.0, view.y - 130.0 - lift)
		draw_arc(rest, STICK_RADIUS, 0.0, TAU, 48, Color(INK, 0.22), 3.0)
		draw_circle(rest, 30.0, Color(INK, 0.14))
	for button: String in _spots:
		if button == "use" and not _use_shown:
			continue
		var spot: Array = _spots[button]
		var centre: Vector2 = spot[0]
		var radius: float = spot[1]
		var on: bool = _held[button] != -1 or (button == "run" and run_latched)
		var edge := EDGE if on or button == "use" else INK
		if button == "use":
			radius += sin(_clock * 6.0) * 3.0
		draw_circle(centre, radius, Color(EDGE if on else DARK, 0.5 if on else 0.38))
		draw_arc(centre, radius, 0.0, TAU, 48, Color(edge, 0.85), 3.0)
		var text: String = spot[2]
		var text_size := 24 if radius > 40.0 else 20
		draw_string(FONT, centre + Vector2(-radius, text_size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, text_size, Color(INK, 0.95))
