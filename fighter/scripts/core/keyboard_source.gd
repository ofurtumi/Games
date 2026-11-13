class_name KeyboardSource
extends InputSource

var keys: Dictionary
var layout := 0


func _init(layout_index: int) -> void:
	layout = layout_index
	keys = Bindings.KEYBOARD[layout_index]
	label = "KB%d %s" % [layout_index + 1, keys["name"]]


func _down(action: String) -> bool:
	for k in keys[action]:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func sample(_fighter: Node, _arena: Node) -> InputFrame:
	var f := InputFrame.new()
	f.move.x = int(_down("right")) - int(_down("left"))
	f.move.y = int(_down("down")) - int(_down("up"))
	f.jump = _down("jump")
	f.attack = _down("attack")
	f.aim = _down("aim")
	f.sprint = _down("sprint")
	f.throw = _down("throw")
	f.interact = _down("interact")
	return f


func device_key() -> String:
	return "kb%d" % layout
