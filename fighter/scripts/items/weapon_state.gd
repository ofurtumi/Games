class_name WeaponState
extends RefCounted
## A specific weapon in the world: def + mutable ammo/cooldown. Survives drops and pickups.

var def: WeaponDef
var ammo := 0
var cooldown := 0.0
var charge := 0.0
var spin := 0.0


func _init(d: WeaponDef) -> void:
	def = d
	ammo = d.ammo
