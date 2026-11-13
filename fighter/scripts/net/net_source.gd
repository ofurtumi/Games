class_name NetSource
extends InputSource
## Server side: input for a fighter controlled by a remote client. Frames arrive in batches
## and are played back one per tick so short taps are never lost. If the queue runs dry the
## last frame is held; if it grows (lag spike) old frames are skipped to stay responsive.

const MAX_QUEUE := 6
const CATCH_UP := 2

var peer_id := 0
var slot := 0
var queue := PackedInt32Array()
var last := 0


func _init(peer: int, s: int) -> void:
	peer_id = peer
	slot = s
	label = "NET %d.%d" % [peer, s]


func push(bits: int) -> void:
	queue.append(bits)
	if queue.size() > MAX_QUEUE:
		queue = queue.slice(queue.size() - CATCH_UP)


func sample(_fighter: Node, _arena: Node) -> InputFrame:
	if not queue.is_empty():
		last = queue[0]
		queue.remove_at(0)
	return InputFrame.from_bits(last)


func device_key() -> String:
	return label
