extends Node2D

@onready
var ani = %AnimationPlayer
func _ready():
	ani.play("DIVE")
