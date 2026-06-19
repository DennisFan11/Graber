class_name Weapon
extends Node2D

signal used

@export var weapon_name: String
@export var icon: Texture2D
@export_multiline var describe: String


func use() -> void:
	used.emit()
