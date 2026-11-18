class_name PlayerManager
extends Node2D

@onready var _player: Player = $Player

func _ready() -> void:
	DI.register("_player_manager", self)


func find() -> Player:
	return _player
