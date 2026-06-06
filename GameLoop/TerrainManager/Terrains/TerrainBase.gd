@tool
class_name TerrainBase
extends Polygon2D




func _ready():
	sync_polygon()
	self_modulate = Color(0.0, 0.0, 0.0 , 0.0)
func _process(delta):
	if not Engine.is_editor_hint(): return 
	sync_polygon()
	

func get_body()-> StaticBody2D:
	return %StaticBody2D

func sync_polygon():
	var main = self.polygon
	%CollidePolygon2D.polygon = main
	%VisualPolygon2D.polygon = main
	%VisualPolyLine.points = main
