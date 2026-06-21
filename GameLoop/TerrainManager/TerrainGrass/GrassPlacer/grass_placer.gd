@tool
class_name GrassPlacer
extends Line2D

@export var search_r: float = 70.0:
	set(v):
		search_r = max(v, 0.0)
		_changed()

@export var step: float = 7.0:
	set(v):
		step = max(v, 0.1)
		_changed()

@export_range(4, 128, 1) var ray_count: int = 32:
	set(v):
		ray_count = max(v, 4)
		_changed()

@export_flags_2d_physics var query_mask: int = 0xFFFFFFFF:
	set(v):
		query_mask = v
		_changed()

@export var grass_rotation_offset: float = 0.0:
	set(v):
		grass_rotation_offset = v
		_changed()

@export var auto_regenerate: bool = true
@export var generate_on_ready: bool = false

@export var show_search_polygon: bool = true:
	set(v):
		show_search_polygon = v
		queue_redraw()

@export var polygon_color: Color = Color(0.2, 0.7, 1.0, 0.16):
	set(v):
		polygon_color = v
		queue_redraw()

@export var polygon_outline_color: Color = Color(0.2, 0.7, 1.0, 0.7):
	set(v):
		polygon_outline_color = v
		queue_redraw()

@export var regenerate: bool = false:
	set(_v):
		regenerate = false
		_request_regenerate()

const GRASS_SCENE = preload("uid://b55ygag54j81w")
const GENERATED_META := "generated_by_grass_placer"
const REGEN_INTERVAL_MS := 1000

var _dirty := false
var _last_regen_ms := -1000000
var _last_signature := 0


func _ready():
	set_notify_transform(true)
	_last_signature = _make_signature()

	if Engine.is_editor_hint():
		set_process(true)
	else:
		self_modulate = Color.TRANSPARENT
	if generate_on_ready:
		_request_regenerate()

	queue_redraw()


func _process(_delta):
	if Engine.is_editor_hint():
		_check_points_changed()

	if not _dirty:
		return

	var now := Time.get_ticks_msec()
	if now - _last_regen_ms < REGEN_INTERVAL_MS:
		return

	_dirty = false
	_last_regen_ms = now
	_last_signature = _make_signature()
	place_grass()


func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()
		if auto_regenerate:
			_request_regenerate()


func _changed():
	queue_redraw()

	if not auto_regenerate:
		return

	_last_signature = _make_signature()
	_request_regenerate()


func _check_points_changed():
	var sig := _make_signature()

	if sig == _last_signature:
		return

	_last_signature = sig

	if auto_regenerate:
		_request_regenerate()

	queue_redraw()


func _request_regenerate():
	_dirty = true

	if is_inside_tree():
		set_process(true)
		queue_redraw()


func place_grass():
	clear_grass()

	if points.size() < 2:
		return

	var world := get_world_2d()
	if world == null:
		return

	var space := world.direct_space_state
	var count := 0

	for i in range(points.size() - 1):
		var p0 := points[i]
		var p1 := points[i + 1]
		var length := p0.distance_to(p1)

		if length <= 0.001:
			continue

		var line_dir := (p1 - p0).normalized()
		var d := 0.0

		while d <= length:
			var sample_local := p0 + line_dir * d
			var sample_global := to_global(sample_local)

			var hit = find_nearest_terrain_360(space, sample_global)

			if hit != null:
				var grass = GRASS_SCENE.instantiate()
				grass.name = "GeneratedGrass_%04d" % count
				grass.set_meta(GENERATED_META, true)

				add_child(grass, true)

				if Engine.is_editor_hint():
					var root := get_tree().edited_scene_root
					if root != null:
						grass.owner = root

				grass.global_position = hit.position
				grass.global_rotation = hit.normal.angle() + grass_rotation_offset

				count += 1

			d += step

	queue_redraw()


func clear_grass():
	for child in get_children():
		if child.get_meta(GENERATED_META, false) or child.name.begins_with("GeneratedGrass_"):
			remove_child(child)
			child.queue_free()


func find_nearest_terrain_360(space: PhysicsDirectSpaceState2D, pos: Vector2):
	var nearest_dist := INF
	var nearest = null

	for i in range(ray_count):
		var angle := TAU * float(i) / float(ray_count)
		var dir := Vector2.RIGHT.rotated(angle)

		var query := PhysicsRayQueryParameters2D.create(
			pos,
			pos + dir * search_r
		)

		query.collision_mask = query_mask
		query.collide_with_bodies = true
		query.collide_with_areas = false

		var hit := space.intersect_ray(query)

		if hit.is_empty():
			continue

		var collider = hit.collider

		if not collider is Node:
			continue

		var terrain = find_terrain_base(collider)

		# 第一個撞到的不是 TerrainBase，就代表被牆擋住
		if terrain == null:
			continue

		var dist := pos.distance_to(hit.position)

		if dist < nearest_dist:
			nearest_dist = dist
			nearest = {
				"terrain": terrain,
				"position": hit.position,
				"normal": hit.normal
			}

	return nearest


func find_terrain_base(node: Node):
	var current := node

	while current != null:
		if current is TerrainBase:
			return current

		current = current.get_parent()

	return null


func _draw():
	if not Engine.is_editor_hint():
		return

	if not show_search_polygon:
		return

	var poly := make_search_polygon()

	if poly.size() < 3:
		return

	draw_polygon(poly, _colors(poly.size(), polygon_color))

	var closed := PackedVector2Array(poly)
	closed.append(poly[0])
	draw_polyline(closed, polygon_outline_color, 1.0, true)


func make_search_polygon() -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()

	if points.size() < 2:
		return PackedVector2Array()

	for i in range(points.size()):
		var tangent := Vector2.ZERO

		if i > 0:
			tangent += (points[i] - points[i - 1]).normalized()

		if i < points.size() - 1:
			tangent += (points[i + 1] - points[i]).normalized()

		if tangent.length_squared() < 0.001:
			continue

		tangent = tangent.normalized()
		var normal := Vector2(-tangent.y, tangent.x)

		left.append(points[i] + normal * search_r)
		right.insert(0, points[i] - normal * search_r)

	var poly := PackedVector2Array()

	for p in left:
		poly.append(p)

	for p in right:
		poly.append(p)

	return poly


func _colors(count: int, color: Color) -> PackedColorArray:
	var arr := PackedColorArray()

	for i in range(count):
		arr.append(color)

	return arr


func _make_signature() -> int:
	return hash([
		points,
		search_r,
		step,
		ray_count,
		query_mask,
		grass_rotation_offset,
		global_transform
	])
