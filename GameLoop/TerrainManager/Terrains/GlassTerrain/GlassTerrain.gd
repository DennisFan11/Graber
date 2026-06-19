@tool
class_name GlassTerrain
extends DestructibleTerrain

@export_group("Polygon Shadow")
@export_range(0.0, 100000.0, 1.0, "or_greater") var shadow_extrusion_length := 9000.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var shadow_base_offset := 0.0

@onready var _polygon_shadow: PolygonShadow = %PolygonShadow

var _player_manager: PlayerManager


func _ready() -> void:
	super()
	_refresh_polygon_shadow()
	if Engine.is_editor_hint():
		return
	_bind_shadow_light()


func _on_injected() -> void:
	if not Engine.is_editor_hint() and is_node_ready():
		_bind_shadow_light()


func sync_polygon() -> void:
	super()
	call_deferred("_refresh_polygon_shadow")


func _decorate_shard(
	_shard: RigidBody2D,
	visual: Polygon2D,
	_shard_polygon: PackedVector2Array
) -> void:
	var polygon_shadow := PolygonShadow.new()
	polygon_shadow.name = "PolygonShadow"
	polygon_shadow.z_sort_enabled = false
	polygon_shadow.extrusion_length = shadow_extrusion_length
	polygon_shadow.base_offset = shadow_base_offset
	polygon_shadow.light_node = _find_player_body()
	visual.add_child(polygon_shadow)


func _refresh_polygon_shadow() -> void:
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(_polygon_shadow):
		return
	_polygon_shadow.z_sort_enabled = false
	_polygon_shadow.extrusion_length = shadow_extrusion_length
	_polygon_shadow.base_offset = shadow_base_offset
	_polygon_shadow.refresh_from_target()


func _bind_shadow_light() -> void:
	_polygon_shadow.light_node = _find_player_body()


func _find_player_body() -> RigidBody2D:
	if is_instance_valid(_player_manager):
		var player := _player_manager.find()
		if is_instance_valid(player):
			return player.get_body()
	return null
