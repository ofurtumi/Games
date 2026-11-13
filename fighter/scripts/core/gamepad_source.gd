class_name GamepadSource
extends InputSource
## A = jump, X = attack, Y = pick up, B = throw, RB/RT = aim, LB/LT/L3 = sprint.

const DEADZONE := 0.45

var device := 0


func _init(dev: int) -> void:
	device = dev
	label = "PAD %d" % (dev + 1)


func _btn(b: JoyButton) -> bool:
	return Input.is_joy_button_pressed(device, b)


func sample(_fighter: Node, _arena: Node) -> InputFrame:
	var f := InputFrame.new()
	var stick := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	if stick.length() > DEADZONE:
		# Snap to 8 directions by angle so diagonals feel deliberate.
		var a := snappedf(stick.angle(), PI / 4.0)
		f.move = Vector2i(roundi(cos(a)), roundi(sin(a)))
	var dx := int(_btn(JOY_BUTTON_DPAD_RIGHT)) - int(_btn(JOY_BUTTON_DPAD_LEFT))
	var dy := int(_btn(JOY_BUTTON_DPAD_DOWN)) - int(_btn(JOY_BUTTON_DPAD_UP))
	if dx != 0 or dy != 0:
		f.move = Vector2i(dx, dy)
	f.jump = _btn(JOY_BUTTON_A)
	f.attack = _btn(JOY_BUTTON_X)
	f.interact = _btn(JOY_BUTTON_Y)
	f.throw = _btn(JOY_BUTTON_B)
	f.aim = _btn(JOY_BUTTON_RIGHT_SHOULDER) or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	f.sprint = _btn(JOY_BUTTON_LEFT_SHOULDER) or _btn(JOY_BUTTON_LEFT_STICK) \
		or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.4
	return f


func start_pressed() -> bool:
	return _btn(JOY_BUTTON_START)


func device_key() -> String:
	return "pad%d" % device
