class_name Grass
extends Node2D

@export_group("抓取")
@export var 半徑: float = 12.0:
	set(value):
		半徑 = maxf(value, 0.0)
		if is_node_ready():
			_apply_grab_radius()
@export var 消失所需抓取時間: float = 3.0
@export var 重生時間: float = 15.0

@export_group("彎曲")
@export_range(0.0, 180.0, 1.0, "degrees") var 最大彎曲角度: float = 85.0
@export var 彎曲速度: float = 12.0
@export var 回復速度: float = 8.0

@onready var _line: Line2D = $Line2D
@onready var _fall_particles: GPUParticles2D = %FallParticles
@onready var _grab_area: Area2D = %GrabArea
@onready var _grab_shape: CollisionShape2D = %GrabShape

var _original_points := PackedVector2Array()
var _grabbed_hands: Array[RigidHand] = []
var _constrained_hands: Array[RigidHand] = []
var _grab_elapsed := 0.0
var _respawn_remaining := 0.0
var _bend_angle := 0.0
var _available := true


func _ready() -> void:
	_original_points = _line.points.duplicate()
	_apply_grab_radius()


func _physics_process(delta: float) -> void:
	if not _available:
		_respawn_remaining -= delta
		if _respawn_remaining <= 0.0:
			_respawn()
		return

	_refresh_grabbed_hands()
	var hand := _get_nearest_grabbing_hand()
	var target_angle := 0.0
	var smoothing_speed := 回復速度

	if hand != null:
		_grab_elapsed += delta
		target_angle = _get_bend_target(hand)
		smoothing_speed = 彎曲速度

		if _grab_elapsed >= maxf(消失所需抓取時間, 0.0):
			_disappear()
			return

	var previous_bend_angle := _bend_angle
	_bend_angle = lerp_angle(
		_bend_angle,
		target_angle,
		1.0 - exp(-maxf(smoothing_speed, 0.0) * delta)
	)
	if not is_equal_approx(previous_bend_angle, _bend_angle):
		_update_line_points()


func can_grab() -> bool:
	return _available


func get_grab_anchor_global_position(_hand: RigidHand) -> Vector2:
	return global_position


func get_grab_max_distance(_hand: RigidHand) -> float:
	var length := 0.0
	for i in range(1, _original_points.size()):
		length += to_global(_original_points[i - 1]).distance_to(to_global(_original_points[i]))
	return length


func _apply_grab_radius() -> void:
	var circle := _grab_shape.shape as CircleShape2D
	circle.radius = 半徑


func _refresh_grabbed_hands() -> void:
	for area in _grab_area.get_overlapping_areas():
		var owner := area.get_parent()
		if not owner is RigidHand:
			continue

		var hand := owner as RigidHand
		if hand.grab_type != RigidHand.GRAB_TYPE.WALL_GRAB:
			continue
		if not _grabbed_hands.has(hand):
			_grabbed_hands.append(hand)
			if _is_nearest_flexible_surface(hand):
				if hand.configure_grab_constraint(
					self,
					get_grab_anchor_global_position(hand),
					get_grab_max_distance(hand)
				):
					_constrained_hands.append(hand)

	for hand in _grabbed_hands.duplicate():
		if not is_instance_valid(hand) or hand.grab_type != RigidHand.GRAB_TYPE.WALL_GRAB:
			_grabbed_hands.erase(hand)
			_constrained_hands.erase(hand)


func _is_nearest_flexible_surface(hand: RigidHand) -> bool:
	var own_distance := hand.global_position.distance_squared_to(global_position)
	for surface in hand.get_grab_surfaces():
		if surface == self or not surface.has_method(&"get_grab_max_distance"):
			continue
		if surface.get_grab_max_distance(hand) <= 0.0:
			continue
		var anchor: Vector2 = surface.get_grab_anchor_global_position(hand)
		if hand.global_position.distance_squared_to(anchor) < own_distance:
			return false
	return true


func _get_nearest_grabbing_hand() -> RigidHand:
	var nearest_hand: RigidHand
	var nearest_distance_squared := INF

	for hand in _grabbed_hands:
		var distance_squared := global_position.distance_squared_to(hand.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_hand = hand

	return nearest_hand


func _get_bend_target(hand: RigidHand) -> float:
	var local_hand_position := to_local(hand.global_position)
	var max_angle := deg_to_rad(absf(最大彎曲角度))
	return clampf(
		wrapf(local_hand_position.angle(), -PI, PI),
		-max_angle,
		max_angle
	)


func _update_line_points() -> void:
	if _original_points.size() < 2:
		return

	var bent_points := PackedVector2Array()
	bent_points.resize(_original_points.size())
	bent_points[0] = _original_points[0]

	for i in range(1, _original_points.size()):
		var original_segment := _original_points[i] - _original_points[i - 1]
		var progress := float(i) / float(_original_points.size() - 1)
		var segment_angle := original_segment.angle() + _bend_angle * progress * 2.0
		bent_points[i] = (
			bent_points[i - 1]
			+ Vector2.RIGHT.rotated(segment_angle) * original_segment.length()
		)

	_line.points = bent_points


func _disappear() -> void:
	_available = false
	_fall_particles.global_position = _line.to_global(_line.points[-1])
	_fall_particles.global_rotation = 0.0
	_fall_particles.restart()
	for hand in _constrained_hands:
		if is_instance_valid(hand):
			hand.release_grab_constraint(self)
	_grabbed_hands.clear()
	_constrained_hands.clear()
	_respawn_remaining = maxf(重生時間, 0.0)
	_line.visible = false
	_grab_shape.set_deferred("disabled", true)


func _respawn() -> void:
	_available = true
	_grab_elapsed = 0.0
	_respawn_remaining = 0.0
	_bend_angle = 0.0
	_line.points = _original_points
	_line.visible = true
	_grab_shape.set_deferred("disabled", false)
