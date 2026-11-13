class_name InputSource
extends RefCounted
## Base class: something that produces an InputFrame for a fighter each tick.

var label := "?"
var is_bot := false


func sample(_fighter: Node, _arena: Node) -> InputFrame:
	return InputFrame.new()


## Stable id used by the lobby to tell devices apart.
func device_key() -> String:
	return label
