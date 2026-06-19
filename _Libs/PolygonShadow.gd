class_name PolygonShadow
extends VisibleOnScreenEnabler2D

## 抽離版：
## - 取代 PolygonShadowComponent.gd
## - 取代 ShadowSorter.gd
## - 取代 ShadowSorterManager.gd
##
## 用法：
## 1. 新增一個 VisibleOnScreenEnabler2D 節點，掛這支腳本。
## 2. target_polygon 指向要被拉成陰影的 Polygon2D。
## 3. light_node 指向玩家 / 光源；不填時會嘗試讀 /root/Player.get_player_position()。
## 4. 需要時呼叫 start()。auto_start=true 時 _ready() 會自動 start。

@export var target_polygon: Polygon2D
@export var light_node: Node2D
@export_node_path("Node") var light_path: NodePath = ^"/root/Player"
@export var light_position_method: StringName = &"get_player_position"

@export var shadow_enabled: bool = true
@export var auto_start: bool = true
@export var restore_when_offscreen: bool = true

@export var extrusion_length: float = 9000.0
@export var base_offset: float = 0.0

@export_group("Z Sort")
@export var z_sort_enabled: bool = true
@export var z_index_base: int = 0

static var _active_shadows: Dictionary = {}
static var _last_sort_frame: int = -1

var _base_polygon: PackedVector2Array = PackedVector2Array()
var _started: bool = false
var _active: bool = false


func _ready() -> void:
	if target_polygon == null:
		target_polygon = get_parent() as Polygon2D

	# 如果 PolygonShadow 是 target_polygon 的子節點，不要用 enable_node_path 去控制父節點，
	# 否則離開畫面時可能連自己一起被停用。
	# 如果是原本那種「ShadowSorter 與 MainPolygon 同層」的結構，會保留原本的螢幕外停用行為。
	if target_polygon != null and target_polygon != get_parent():
		enable_node_path = get_path_to(target_polygon)

	screen_entered.connect(_on_screen_entered)
	screen_exited.connect(_on_screen_exited)
	tree_exiting.connect(_on_tree_exiting)

	if auto_start and target_polygon != null:
		start()


func start() -> void:
	assert(target_polygon != null, "PolygonShadow 需要 target_polygon，或直接放在 Polygon2D 底下。")

	_base_polygon = target_polygon.polygon
	_started = true
	_rebuild_rect_from_base_polygon()
	set_process(true)

	if is_on_screen():
		_on_screen_entered()


func stop(restore: bool = true) -> void:
	_started = false
	_unregister_active(restore)
	set_process(false)


func reset() -> void:
	if target_polygon == null:
		return
	target_polygon.polygon = _base_polygon


func refresh_from_target() -> void:
	if target_polygon == null:
		return
	_base_polygon = target_polygon.polygon
	_rebuild_rect_from_base_polygon()


func _process(_delta: float) -> void:
	if not _started:
		return

	if not shadow_enabled:
		reset()
		return

	if not _active:
		return

	_update_shadow_polygon()

	if z_sort_enabled:
		_sort_active_shadows_once_per_frame()


func _update_shadow_polygon() -> void:
	if target_polygon == null:
		return

	if _base_polygon.is_empty():
		target_polygon.polygon = PackedVector2Array()
		return

	var light_local_pos := target_polygon.to_local(_get_light_global_position())
	var all_points := PackedVector2Array()

	for pt in _base_polygon:
		var raw_dir := pt - light_local_pos
		var light_dir := Vector2.RIGHT
		if raw_dir.length_squared() > 0.000001:
			light_dir = raw_dir.normalized()

		var offset_pt := pt + light_dir * base_offset
		all_points.append(offset_pt)
		all_points.append(offset_pt + light_dir * extrusion_length)

	var shadow_hull := Geometry2D.convex_hull(all_points)

	if shadow_hull.size() > 1 and shadow_hull[0] == shadow_hull[shadow_hull.size() - 1]:
		shadow_hull.remove_at(shadow_hull.size() - 1)

	target_polygon.polygon = shadow_hull


func _get_light_global_position() -> Vector2:
	if light_node != null:
		return light_node.global_position

	var provider := get_node_or_null(light_path)
	if provider != null:
		if provider.has_method(light_position_method):
			var result = provider.call(light_position_method)
			if result is Vector2:
				return result

		var node2d := provider as Node2D
		if node2d != null:
			return node2d.global_position

	return global_position


func _rebuild_rect_from_base_polygon() -> void:
	if target_polygon == null or _base_polygon.is_empty():
		return

	var first_point_local := to_local(target_polygon.to_global(_base_polygon[0]))
	var min_pos := first_point_local
	var max_pos := first_point_local

	for i in range(1, _base_polygon.size()):
		var p_local := to_local(target_polygon.to_global(_base_polygon[i]))
		min_pos.x = min(min_pos.x, p_local.x)
		min_pos.y = min(min_pos.y, p_local.y)
		max_pos.x = max(max_pos.x, p_local.x)
		max_pos.y = max(max_pos.y, p_local.y)

	rect = Rect2(min_pos, max_pos - min_pos)


func _on_screen_entered() -> void:
	if not _started:
		return
	_active = true
	_active_shadows[self] = true


func _on_screen_exited() -> void:
	_unregister_active(restore_when_offscreen)


func _on_tree_exiting() -> void:
	_unregister_active(false)


func _unregister_active(restore: bool) -> void:
	_active = false
	_active_shadows.erase(self)
	if restore:
		reset()


static func _sort_active_shadows_once_per_frame() -> void:
	var frame := Engine.get_process_frames()
	if _last_sort_frame == frame:
		return
	_last_sort_frame = frame

	var shadows: Array = []
	for shadow in _active_shadows.keys():
		if not is_instance_valid(shadow):
			_active_shadows.erase(shadow)
			continue
		if not shadow.z_sort_enabled:
			continue
		if shadow.target_polygon == null:
			continue
		shadows.append(shadow)

	shadows.sort_custom(func(a, b) -> bool:
		var dist_a: float = a.target_polygon.global_position.distance_squared_to(a._get_light_global_position())
		var dist_b: float = b.target_polygon.global_position.distance_squared_to(b._get_light_global_position())
		return dist_a > dist_b
	)

	for i in range(shadows.size()):
		var shadow: PolygonShadow = shadows[i]
		shadow.target_polygon.z_index = shadow.z_index_base + i
