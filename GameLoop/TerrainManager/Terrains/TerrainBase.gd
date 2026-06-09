@tool
class_name TerrainBase
extends Polygon2D


@export var 可抓取: bool = true
func can_grab()-> bool:
	return 可抓取
	
func _ready():
	sync_polygon()
	self_modulate = Color(0.0, 0.0, 0.0, 0.0)

# 當節點的任何屬性被改變時，Godot 會自動呼叫此函式
func _set(property: StringName, _value: Variant) -> bool:
	if property == "polygon":
		# 使用 call_deferred 確保在引擎完成 polygon 內部賦值後，才進行我們的同步
		call_deferred("sync_polygon")
	# 回傳 false 代表我們「不阻擋」預設的賦值行為，讓引擎自行更新 self.polygon
	return false

func get_body() -> StaticBody2D:
	return %StaticBody2D



func sync_polygon():
	var main = self.polygon
	%CollidePolygon2D.polygon = main
	%VisualPolygon2D.polygon = main
	%LightOccluder2D.occluder.polygon = main
	%VisualPolyLine.points = main
