class_name Bindings
extends RefCounted
## Keyboard layouts. Physical keys, so they sit in the same spot on any keyboard layout.
## Edit freely. Gamepad mapping lives in gamepad_source.gd.
##
## KB1 (single player + first keyboard player): WASD move/aim, J attack, K jump,
## L aim-lock / block, H throw / pick up, Shift sprint.

static var KEYBOARD: Array = [
	{
		"name": "WASD+HJKL",
		"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
		"attack": [KEY_J], "jump": [KEY_K, KEY_SPACE], "aim": [KEY_L],
		"throw": [KEY_H], "sprint": [KEY_SHIFT], "interact": [KEY_E],
	},
	{ # Second player on the same keyboard: arrows + numpad (or , . / ; on laptops)
		"name": "ARROWS",
		"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
		"attack": [KEY_KP_1, KEY_PERIOD], "jump": [KEY_KP_2, KEY_SLASH], "aim": [KEY_KP_3, KEY_COMMA],
		"throw": [KEY_KP_0, KEY_SEMICOLON], "sprint": [KEY_KP_ENTER, KEY_APOSTROPHE], "interact": [],
	},
]
