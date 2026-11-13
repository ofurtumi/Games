class_name InputFrame
extends RefCounted
## One tick of player intent. The simulation ONLY reads these, never Input directly,
## so a frame can come from a keyboard, a gamepad, a bot, or (later) the network.
## Sources report held state; edge detection happens in the fighter.

var move := Vector2i.ZERO # x: -1..1, y: -1 (up)..1 (down)
var jump := false
var attack := false
var aim := false
var sprint := false
var throw := false
var interact := false


## Packs the frame into 10 bits — what you'd send over the wire later.
func to_bits() -> int:
	var b := (move.x + 1) | ((move.y + 1) << 2)
	if jump: b |= 1 << 4
	if attack: b |= 1 << 5
	if aim: b |= 1 << 6
	if sprint: b |= 1 << 7
	if throw: b |= 1 << 8
	if interact: b |= 1 << 9
	return b


static func from_bits(b: int) -> InputFrame:
	var f := InputFrame.new()
	f.move = Vector2i((b & 3) - 1, ((b >> 2) & 3) - 1)
	f.jump = (b & (1 << 4)) != 0
	f.attack = (b & (1 << 5)) != 0
	f.aim = (b & (1 << 6)) != 0
	f.sprint = (b & (1 << 7)) != 0
	f.throw = (b & (1 << 8)) != 0
	f.interact = (b & (1 << 9)) != 0
	return f
