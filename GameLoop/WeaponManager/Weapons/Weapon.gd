class_name Weapon
extends Node2D

signal used

@export var weapon_name: String
@export var icon: Texture2D
@export_multiline var describe: String
@export var source_team: DamageSystem.TEAM = DamageSystem.TEAM.IDLE


func use() -> void:
	used.emit()
