@tool
extends Node2D
func _ready():
	if not Engine.is_editor_hint():
		queue_free()
		return
	%Line2D.points = [Vector2(Player.手臂半徑, 0), Vector2(-Player.手臂半徑, 0)]
