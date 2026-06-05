@tool
class_name TerrainBase
extends Polygon2D




func _ready():
	sync_polygon()
func _process(delta):
	if not Engine.is_editor_hint(): return 
	sync_polygon()
	



func sync_polygon():
	var main = self.polygon
	%CollidePolygon2D.polygon = main
	%VisualPolygon2D.polygon = main
	%VisualPolyLine.points = main
