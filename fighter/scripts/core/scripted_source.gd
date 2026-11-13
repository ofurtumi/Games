class_name ScriptedSource
extends InputSource
## Plays back a timeline of inputs, for tests. Steps: [[duration, {field: value}], ...]

var steps: Array = []
var t := 0.0


func _init(s: Array) -> void:
	steps = s
	label = "SCRIPT"


func sample(_fighter: Node, _arena: Node) -> InputFrame:
	t += 1.0 / Engine.physics_ticks_per_second
	var f := InputFrame.new()
	var acc := 0.0
	for st in steps:
		acc += float(st[0])
		if t <= acc:
			for k in st[1]:
				f.set(k, st[1][k])
			return f
	return f
