extends RefCounted

# Input actions with default keys. Each action has a primary key the player
# can rebind (saved in the save file) and an optional fixed alternate.
# Mouse buttons are stored as MOUSE + button index.

const MOUSE = 1000

const ACTIONS = [
	["thrust", "Thrust", KEY_W, KEY_UP],
	["brake", "Brake / drift", KEY_S, KEY_DOWN],
	["left", "Steer left", KEY_A, KEY_LEFT],
	["right", "Steer right", KEY_D, KEY_RIGHT],
	["hop", "Hop", KEY_SPACE, 0],
	["boost", "Boost", KEY_SHIFT, 0],
	["strafe_left", "Strafe left", KEY_Q, 0],
	["strafe_right", "Strafe right", KEY_E, 0],
	["laser", "Laser", MOUSE + MOUSE_BUTTON_LEFT, 0],
	["rocket", "Missile", MOUSE + MOUSE_BUTTON_RIGHT, 0],
	["drop", "Drop bomb", KEY_V, 0],
	["warp", "Warp", KEY_Z, 0],
	["charge", "Seismic charge", KEY_F, 0],
	["respawn", "Respawn", KEY_X, 0],
	["garage", "Garage", KEY_G, 0],
	["builder", "Track builder", KEY_B, 0],
	["camera", "Camera", KEY_C, 0],
]

static func default_key(action: String) -> int:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return 0

static func _key_event(k: int) -> InputEvent:
	if k >= MOUSE and k < MOUSE + 32:
		var m = InputEventMouseButton.new()
		m.button_index = k - MOUSE
		return m
	var e = InputEventKey.new()
	e.physical_keycode = k
	return e

# Registers every action; `overrides` maps action -> physical keycode.
static func apply(overrides: Dictionary) -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
		InputMap.action_erase_events(a[0])
		InputMap.action_add_event(a[0], _key_event(overrides.get(a[0], a[2])))
		if a[3] != 0:
			InputMap.action_add_event(a[0], _key_event(a[3]))

static func key_name(action: String, overrides: Dictionary) -> String:
	var k = overrides.get(action, default_key(action))
	if k >= MOUSE and k < MOUSE + 32:
		return {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse"}.get(k - MOUSE, "Mouse %d" % (k - MOUSE))
	return OS.get_keycode_string(k)
