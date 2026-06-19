class_name WeaponManager
extends Node


func _ready() -> void:
	DI.register("_weapon_manager", self)


func create_weapon(weapon_id: WeaponDB.WeaponID) -> Weapon:
	var weapon_scene := WeaponDB.get_scene(weapon_id)
	if weapon_scene == null:
		push_error("[WeaponManager] Unknown weapon ID: %s" % weapon_id)
		return null

	var instance := weapon_scene.instantiate()
	if instance is not Weapon:
		push_error("[WeaponManager] Weapon scene root must inherit Weapon: %s" % weapon_id)
		instance.free()
		return null

	return instance as Weapon
