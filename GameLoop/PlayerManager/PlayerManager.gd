class_name PlayerManager
extends Node2D

signal weapon_changed(hand_id: HandID, weapon: Weapon)

enum HandID {
	LEFT,
	RIGHT,
}

var _weapon_manager: WeaponManager

@onready var _player: Player = $Player

func _ready() -> void:
	DI.register("_player_manager", self)


func equip_weapon(hand_id: HandID, weapon_id: WeaponDB.WeaponID) -> bool:
	if not _is_valid_hand(hand_id):
		return false
	if not is_instance_valid(_weapon_manager):
		push_error("[PlayerManager] WeaponManager is unavailable")
		return false

	var weapon := _weapon_manager.create_weapon(weapon_id)
	if weapon == null:
		return false

	if not _player.equip_weapon(hand_id, weapon):
		weapon.free()
		return false
	weapon_changed.emit(hand_id, weapon)
	return true


func unequip_weapon(hand_id: HandID) -> void:
	if _is_valid_hand(hand_id):
		_player.unequip_weapon(hand_id)
		weapon_changed.emit(hand_id, null)


func get_mounted_weapon(hand_id: HandID) -> Weapon:
	if not _is_valid_hand(hand_id):
		return null
	return _player.get_mounted_weapon(hand_id)


func _is_valid_hand(hand_id: int) -> bool:
	if hand_id != HandID.LEFT and hand_id != HandID.RIGHT:
		push_error("[PlayerManager] Invalid hand ID: %s" % hand_id)
		return false
	return true
