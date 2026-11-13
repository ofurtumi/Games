class_name Layers
extends RefCounted
## Physics layer bits, shared by everything.

const TERRAIN := 1
const FIGHTERS := 2
const PROPS := 4
const PICKUPS := 8
const PLATFORMS := 32

const PLATFORM_BIT := 6 # for set_collision_mask_value()
const BODY_MASK := TERRAIN | PLATFORMS | PROPS
const SHOT_MASK := TERRAIN | FIGHTERS | PROPS
