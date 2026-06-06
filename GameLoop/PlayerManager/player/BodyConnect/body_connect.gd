@tool
extends Node2D

@export var body: Node2D
@export var Lhand: Node2D
@export var Rhand: Node2D

func _ready() -> void:
	process_priority = 1

func _process(_delta):
	_update()

func _update():
	var mat = %Metaball.material as ShaderMaterial
	if not body or not Lhand or not Rhand:
		return
	if mat:
		# 將三個物件的 global_position (世界座標) 即時塞進 Shader 裡
		mat.set_shader_parameter("pos_circle1", Lhand.global_position)
		mat.set_shader_parameter("pos_circle2", Rhand.global_position)
		mat.set_shader_parameter("pos_box", body.global_position)
		mat.set_shader_parameter("box_rotation", body.global_rotation)
