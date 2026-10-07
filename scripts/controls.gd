extends RefCounted
## The input map, made in code so keyboard, mouse and gamepad live in one table.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E],
	"pause": [KEY_ESCAPE],
	"toggle_spawns": [KEY_F1],
}

const PAD_BUTTONS := {
	"jump": JOY_BUTTON_A,
	"sprint": JOY_BUTTON_LEFT_STICK,
	"interact": JOY_BUTTON_X,
	"pause": JOY_BUTTON_START,
}

# action: [axis, direction]
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
}


static func setup() -> void:
	for action: String in KEYS:
		_ensure(action)
		for key: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	for action: String in PAD_BUTTONS:
		_ensure(action)
		var event := InputEventJoypadButton.new()
		event.button_index = PAD_BUTTONS[action]
		InputMap.action_add_event(action, event)
	for action: String in PAD_AXES:
		_ensure(action)
		var event := InputEventJoypadMotion.new()
		event.axis = PAD_AXES[action][0]
		event.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, event)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
