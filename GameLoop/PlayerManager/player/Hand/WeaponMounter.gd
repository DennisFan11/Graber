class_name WeaponMounter
extends Node2D

var _mounted_weapon: Weapon


func mount_weapon(weapon: Weapon) -> bool:
	if not is_instance_valid(weapon):
		push_error("[WeaponMounter] Cannot mount an invalid weapon")
		return false

	if weapon == _mounted_weapon:
		return true

	if weapon.get_parent() != null:
		push_error("[WeaponMounter] Weapon must not already have a parent")
		return false

	unmount_weapon()
	_mounted_weapon = weapon
	add_child(_mounted_weapon)
	_mounted_weapon.transform = Transform2D.IDENTITY
	return true


func unmount_weapon() -> void:
	if is_instance_valid(_mounted_weapon):
		var old_weapon := _mounted_weapon
		remove_child(old_weapon)
		old_weapon.queue_free()
	_mounted_weapon = null


func has_weapon() -> bool:
	return is_instance_valid(_mounted_weapon)


func use_weapon() -> bool:
	if not has_weapon():
		return false
	_mounted_weapon.use()
	return true


func get_mounted_weapon() -> Weapon:
	if not is_instance_valid(_mounted_weapon):
		_mounted_weapon = null
	return _mounted_weapon
