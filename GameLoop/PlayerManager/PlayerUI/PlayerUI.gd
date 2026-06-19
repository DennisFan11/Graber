class_name PlayerUI
extends Node2D

@export var default_weapon_id: WeaponDB.WeaponID = WeaponDB.WeaponID.BLADE_A

var _player_manager: PlayerManager

@onready var _left_status: Label = %LeftStatus
@onready var _right_status: Label = %RightStatus
@onready var _left_icon: TextureRect = %LeftIcon
@onready var _right_icon: TextureRect = %RightIcon


func _ready() -> void:
	_refresh_all()


func _process(_delta: float) -> void:
	if not is_instance_valid(_player_manager):
		return

	if Input.is_action_just_pressed(&"L_WEAPON"):
		_toggle_weapon(PlayerManager.HandID.LEFT)
	if Input.is_action_just_pressed(&"R_WEAPON"):
		_toggle_weapon(PlayerManager.HandID.RIGHT)


func _on_injected() -> void:
	if not is_instance_valid(_player_manager):
		return
	if not _player_manager.weapon_changed.is_connected(_on_weapon_changed):
		_player_manager.weapon_changed.connect(_on_weapon_changed)
	_refresh_all()


func _toggle_weapon(hand_id: PlayerManager.HandID) -> void:
	if _player_manager.get_mounted_weapon(hand_id) == null:
		_player_manager.equip_weapon(hand_id, default_weapon_id)
	else:
		_player_manager.unequip_weapon(hand_id)


func _on_weapon_changed(hand_id: PlayerManager.HandID, weapon: Weapon) -> void:
	_update_hand(hand_id, weapon)


func _refresh_all() -> void:
	if not is_node_ready():
		return

	if not is_instance_valid(_player_manager):
		_update_hand(PlayerManager.HandID.LEFT, null)
		_update_hand(PlayerManager.HandID.RIGHT, null)
		return

	_update_hand(
		PlayerManager.HandID.LEFT,
		_player_manager.get_mounted_weapon(PlayerManager.HandID.LEFT)
	)
	_update_hand(
		PlayerManager.HandID.RIGHT,
		_player_manager.get_mounted_weapon(PlayerManager.HandID.RIGHT)
	)


func _update_hand(hand_id: PlayerManager.HandID, weapon: Weapon) -> void:
	var hand_name := "左手" if hand_id == PlayerManager.HandID.LEFT else "右手"
	var status := _left_status if hand_id == PlayerManager.HandID.LEFT else _right_status
	var icon_rect := _left_icon if hand_id == PlayerManager.HandID.LEFT else _right_icon

	if weapon == null:
		status.text = "%s：武器已收回" % hand_name
		icon_rect.texture = null
		icon_rect.hide()
		return

	status.text = "%s：武器已拿出\n武器：%s\n描述：%s" % [
		hand_name,
		weapon.weapon_name,
		weapon.describe,
	]
	icon_rect.texture = weapon.icon
	icon_rect.show()
