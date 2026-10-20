class_name InputActions
extends RefCounted
## Every control, for keyboard and gamepad, registered in code so the bindings live in one
## readable place instead of serialized events in project.godot.

const BINDINGS := {
	"steer_port": [KEY_A, KEY_LEFT],
	"steer_starboard": [KEY_D, KEY_RIGHT],
	"more_sail": [KEY_W, KEY_UP],
	"less_sail": [KEY_S, KEY_DOWN],
	"sheet_in": [KEY_Q],
	"sheet_out": [KEY_E],
	"toggle_automatic_trim": [KEY_T],
	"board": [KEY_G],
	"moor": [KEY_M],
	"fire": [KEY_SPACE],
	"change_shot": [KEY_C],
	"back_headsails": [KEY_B],
	"reset": [KEY_R],
	"time_faster": [KEY_PERIOD],
	"time_slower": [KEY_COMMA],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"toggle_help": [KEY_H, KEY_F1],
	"toggle_fullscreen": [KEY_F11],
}

const GAMEPAD_BUTTONS := {
	"more_sail": JOY_BUTTON_RIGHT_SHOULDER,
	"less_sail": JOY_BUTTON_LEFT_SHOULDER,
	"toggle_automatic_trim": JOY_BUTTON_Y,
	"board": JOY_BUTTON_A,
	"moor": JOY_BUTTON_LEFT_STICK,
	"fire": JOY_BUTTON_B,
	"change_shot": JOY_BUTTON_RIGHT_STICK,
	"back_headsails": JOY_BUTTON_X,
	"reset": JOY_BUTTON_START,
	"toggle_help": JOY_BUTTON_GUIDE,
	"zoom_in": JOY_BUTTON_DPAD_UP,
	"zoom_out": JOY_BUTTON_DPAD_DOWN,
	"time_faster": JOY_BUTTON_DPAD_RIGHT,
	"time_slower": JOY_BUTTON_DPAD_LEFT,
}

# Action, axis, and the direction along it.
const GAMEPAD_AXES := [
	["steer_port", JOY_AXIS_LEFT_X, -1.0],
	["steer_starboard", JOY_AXIS_LEFT_X, 1.0],
	["sheet_in", JOY_AXIS_TRIGGER_LEFT, 1.0],
	["sheet_out", JOY_AXIS_TRIGGER_RIGHT, 1.0],
]


const MOUSE_BUTTONS := {
	"zoom_in": MOUSE_BUTTON_WHEEL_UP,
	"zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
	"set_course": MOUSE_BUTTON_LEFT,
}


static func register() -> void:
	for action: String in BINDINGS:
		_ensure(action)
		for keycode: Key in BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	for action: String in GAMEPAD_BUTTONS:
		_ensure(action)
		var event := InputEventJoypadButton.new()
		event.button_index = GAMEPAD_BUTTONS[action]
		InputMap.action_add_event(action, event)
	for action: String in MOUSE_BUTTONS:
		_ensure(action)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTONS[action]
		InputMap.action_add_event(action, event)
	for binding: Array in GAMEPAD_AXES:
		_ensure(binding[0])
		var event := InputEventJoypadMotion.new()
		event.axis = binding[1]
		event.axis_value = binding[2]
		InputMap.action_add_event(binding[0], event)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
