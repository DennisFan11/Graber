class_name WeaponDB
extends RefCounted

enum WeaponID {
	BLADE_A,
}

const WEAPON_SCENES: Dictionary = {
	WeaponID.BLADE_A: preload("res://GameLoop/WeaponManager/Weapons/BladeA/BladeA.tscn"),
}


static func get_scene(weapon_id: WeaponID) -> PackedScene:
	return WEAPON_SCENES.get(weapon_id) as PackedScene
