@tool
class_name DestructibleTerrain
extends TerrainBase

@export_group("Destruction")
@export_range(1.0, 1000000.0, 1.0, "or_greater") var durability: float = 100.0
@export_range(1, 32, 1) var fracture_points: int = 8
@export_range(0.0, 1000000.0, 1.0, "or_greater") var minimum_shard_area: float = 30.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var fracture_impulse: float = 180.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var fracture_torque: float = 25.0
@export_range(0.0, 2.0, 0.05, "or_greater") var impact_direction_weight: float = 1.0
@export_range(0.0, 2.0, 0.05, "or_greater") var radial_spread_weight: float = 0.65
@export_range(0.05, 10.0, 0.05, "or_greater") var shard_disappear_duration: float = 2.0

@onready var _hp_component: HpComponent = $HpComponent

var _is_fracturing := false


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_hp_component.max_hp = durability
	_hp_component.current_hp = durability
	_hp_component.died.connect(_on_hp_depleted)


func get_hp_component() -> HpComponent:
	if _is_fracturing:
		return null
	return _hp_component


func destroy(source: Node = null, damage_position: Vector2 = Vector2.INF) -> void:
	if _is_fracturing:
		return
	_is_fracturing = true
	call_deferred("_fracture", source, damage_position)


func _on_hp_depleted(
	source: Node,
	_source_team: DamageSystem.TEAM,
	_receiver_team: DamageSystem.TEAM,
	damage_position: Vector2
) -> void:
	destroy(source, damage_position)


func _fracture(source: Node, damage_position: Vector2) -> void:
	if polygon.size() < 3 or not is_inside_tree():
		queue_free()
		return

	var body_transform: Transform2D = %StaticBody2D.global_transform
	var fracture := PolygonFracture.new()
	var shard_infos := fracture.fractureDelaunay(
		polygon,
		body_transform,
		fracture_points,
		minimum_shard_area
	)

	var parent := get_parent()
	if parent == null:
		queue_free()
		return

	var impact_position := damage_position
	if not impact_position.is_finite():
		impact_position = body_transform.origin

	var impact_direction := Vector2.ZERO
	if is_instance_valid(source) and source is Node2D:
		impact_direction = source.global_position.direction_to(impact_position)

	for shard_info in shard_infos:
		_spawn_shard(parent, shard_info, impact_position, impact_direction)

	queue_free()


func _spawn_shard(
	parent: Node,
	shard_info: Dictionary,
	impact_position: Vector2,
	impact_direction: Vector2
) -> void:
	var shard := RigidBody2D.new()
	shard.name = "%sShard" % name
	#shard.collision_layer = %StaticBody2D.collision_layer
	shard.collision_mask = %StaticBody2D.collision_mask
	parent.add_child(shard)
	_exclude_player_collisions(shard)

	var shard_transform: Transform2D = shard_info.source_global_trans
	shard_transform.origin = shard_info.spawn_pos
	shard.global_transform = shard_transform

	var shard_polygon: PackedVector2Array = shard_info.centered_shape
	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionPolygon2D"
	collision.polygon = shard_polygon
	shard.add_child(collision)

	var visual := Polygon2D.new()
	visual.name = "VisualPolygon2D"
	visual.polygon = shard_polygon
	_copy_polygon_display(%VisualPolygon2D, visual, shard_info.centroid)
	shard.add_child(visual)
	_decorate_shard(shard, visual, shard_polygon)

	var outline := Line2D.new()
	outline.points = shard_polygon
	outline.closed = true
	outline.width = %VisualPolyLine.width
	outline.default_color = %VisualPolyLine.default_color
	outline.visible = %VisualPolyLine.visible
	shard.add_child(outline)

	var radial_direction := impact_position.direction_to(shard.global_position)
	if radial_direction.is_zero_approx():
		radial_direction = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	var direction := (
		impact_direction * impact_direction_weight
		+ radial_direction * radial_spread_weight
	).normalized()
	if direction.is_zero_approx():
		direction = radial_direction
	direction = direction.rotated(randf_range(-0.35, 0.35))
	shard.call_deferred(
		"apply_central_impulse",
		direction * fracture_impulse
	)
	shard.call_deferred(
		"apply_torque_impulse",
		randf_range(-fracture_torque, fracture_torque)
	)

	_start_shard_disappear(shard, visual, outline)


func _decorate_shard(
	_shard: RigidBody2D,
	_visual: Polygon2D,
	_shard_polygon: PackedVector2Array
) -> void:
	pass


func _copy_polygon_display(
	source_polygon: Polygon2D,
	target_polygon: Polygon2D,
	centroid: Vector2
) -> void:
	target_polygon.visible = source_polygon.visible
	target_polygon.modulate = source_polygon.modulate
	target_polygon.self_modulate = source_polygon.self_modulate
	target_polygon.material = source_polygon.material
	target_polygon.use_parent_material = source_polygon.use_parent_material
	target_polygon.show_behind_parent = source_polygon.show_behind_parent
	target_polygon.y_sort_enabled = source_polygon.y_sort_enabled
	target_polygon.light_mask = source_polygon.light_mask
	target_polygon.visibility_layer = source_polygon.visibility_layer
	target_polygon.texture_filter = source_polygon.texture_filter
	target_polygon.texture_repeat = source_polygon.texture_repeat
	target_polygon.clip_children = source_polygon.clip_children

	target_polygon.color = source_polygon.color
	target_polygon.texture = source_polygon.texture
	target_polygon.texture_offset = source_polygon.texture_offset - centroid
	target_polygon.texture_rotation = source_polygon.texture_rotation
	target_polygon.texture_scale = source_polygon.texture_scale
	target_polygon.antialiased = source_polygon.antialiased
	target_polygon.invert_enabled = source_polygon.invert_enabled
	target_polygon.invert_border = source_polygon.invert_border
	target_polygon.offset = source_polygon.offset


func _start_shard_disappear(
	shard: RigidBody2D,
	visual: Polygon2D,
	outline: Line2D
) -> void:
	var tween := get_tree().create_tween()
	tween.bind_node(shard)
	tween.tween_property(visual, "scale", Vector2.ZERO, shard_disappear_duration)
	tween.parallel().tween_property(outline, "scale", Vector2.ZERO, shard_disappear_duration)
	tween.tween_callback(func() -> void: shard.queue_free())


func _exclude_player_collisions(shard: RigidBody2D) -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root

	var players: Array[Node] = []
	if root is Player:
		players.append(root)
	players.append_array(root.find_children("*", "Player", true, false))

	for player in players:
		for node in player.find_children("*", "PhysicsBody2D", true, false):
			var player_body := node as PhysicsBody2D
			if player_body != null:
				shard.add_collision_exception_with(player_body)
