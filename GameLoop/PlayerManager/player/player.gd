@tool
class_name Player
extends Node2D


# Public settings
@export_group("手臂")
static var 手臂半徑: float = 56.0
@export var 輸入死區: float = 0.12
@export var 距離約束迭代: int = 4
@export var 目標跟隨速度: float = 28.0

@export_group("手部力道")
@export var 揮手力道: float = 780.0
@export var 揮手阻尼: float = 58.0
@export var 最大力道: float = 2400.0
@export var 手部下墜力: float = 85.0
@export var 身體反作用: float = 0.75
@export var 接觸反作用倍率: float = 1.05

@export_group("抓取")
@export var 抓取力道倍率: float = 0.08
@export var 抓取阻尼: float = 34.0
@export var 抓取切線阻尼: float = 10.0

@export_group("Body Upright")
@export var body_upright_torque: float = 1600.0
@export var body_upright_damping: float = 10.0
@export var max_body_upright_torque: float = 4800.0

@export_group("Grab Vibration")
@export var wall_grab_vibration_strength: float = 2.0
@export var wall_grab_vibration_duration: float = 0.1

# Private nodes and state
@onready var _body: RigidBody2D = $RigidBody
@onready var _hand_l: RigidHand = $RigidHandL
@onready var _hand_r: RigidHand = $RigidHandR

var _hands: Array[RigidHand] = []
var _targets = [Vector2.ZERO, Vector2.ZERO]
var _smooth_targets = [Vector2.ZERO, Vector2.ZERO]
var _grabbed = [false, false]
var _grab_pos = [Vector2.ZERO, Vector2.ZERO]
var _grabbed_bodies = [null, null]
var _grab_local_pos = [Vector2.ZERO, Vector2.ZERO]
var _grab_joints = [null, null]
var _last_body_linear_velocity := Vector2.ZERO


func _ready():
	if Engine.is_editor_hint(): return

	_hands = [_hand_l, _hand_r]
	_last_body_linear_velocity = _body.linear_velocity

	for i in range(_hands.size()):
		var hand = _hands[i]
		var start_pos = _clamp_point_inside_radius(hand.global_position, _body.global_position)

		_targets[i] = start_pos
		_smooth_targets[i] = start_pos
		_grab_pos[i] = start_pos

		hand.global_position = start_pos
		hand.linear_velocity = _body.linear_velocity





func _physics_process(delta):
	if Engine.is_editor_hint(): return
	var body_velocity_delta := _body.linear_velocity - _last_body_linear_velocity
	_inherit_body_velocity(body_velocity_delta)

	var center = _body.global_position
	_apply_body_upright_torque()

	for i in range(_hands.size()):
		var hand = _hands[i]
		var input_vec = _get_hand_input(i)

		_update_grab_state(i, hand)
		_update_grab_anchor(i, hand)
		_update_target(i, hand, input_vec, center, delta)
		_move_hand(hand, _smooth_targets[i], input_vec, _grabbed[i])

	_last_body_linear_velocity = _body.linear_velocity
	


func _inherit_body_velocity(body_velocity_delta: Vector2):
	if body_velocity_delta.length_squared() <= 0.0001:
		return

	for i in range(_hands.size()):
		if _grabbed[i]:
			continue

		_hands[i].linear_velocity += body_velocity_delta


func _apply_body_upright_torque():
	var angle_error := wrapf(_body.rotation, -PI, PI)
	var torque := -angle_error * body_upright_torque
	torque -= _body.angular_velocity * body_upright_damping
	_body.apply_torque(clamp(torque, -max_body_upright_torque, max_body_upright_torque))


func _update_target(i: int, hand: RigidHand, input_vec: Vector2, center: Vector2, delta: float):
	if _grabbed[i]:
		_targets[i] = _grab_pos[i]
		_smooth_targets[i] = _grab_pos[i]
		return

	if input_vec.length() < 輸入死區:
		_targets[i] = hand.global_position
		_smooth_targets[i] = hand.global_position
		return

	var strength = clamp(input_vec.length(), 0.0, 1.0)
	_targets[i] = center + input_vec.normalized() * 手臂半徑 * strength
	_smooth_targets[i] = _smooth_targets[i].lerp(
		_targets[i],
		1.0 - exp(-目標跟隨速度 * delta)
	)


func _update_grab_state(i: int, hand: RigidHand):
	var action_name = "L_GRAB" if i == 0 else "R_GRAB"
	var pressing = Input.is_action_pressed(action_name)

	if pressing and not _grabbed[i]:
		var target_body = _find_grab_body(hand)

		if target_body:
			_start_grab(i, hand, target_body)
		else:
			_set_hand_grab_type(i, hand, RigidHand.GRAB_TYPE.AIR_GRAB)
	elif not pressing and _grabbed[i]:
		_stop_grab(i, hand)
		_set_hand_grab_type(i, hand, RigidHand.GRAB_TYPE.IDLE)
	elif pressing:
		var grab_type = RigidHand.GRAB_TYPE.WALL_GRAB if _grabbed[i] else RigidHand.GRAB_TYPE.AIR_GRAB
		_set_hand_grab_type(i, hand, grab_type)
	else:
		_set_hand_grab_type(i, hand, RigidHand.GRAB_TYPE.IDLE)


func _set_hand_grab_type(i: int, hand: RigidHand, grab_type: int):
	var was_wall_grab = hand.grab_type == RigidHand.GRAB_TYPE.WALL_GRAB
	hand.grab_type = grab_type

	if not was_wall_grab and grab_type == RigidHand.GRAB_TYPE.WALL_GRAB:
		_start_wall_grab_vibration(i)



func _start_wall_grab_vibration(hand_index: int):
	if wall_grab_vibration_strength <= 0.0 or wall_grab_vibration_duration <= 0.0:
		return

	var strength = clamp(wall_grab_vibration_strength, 0.0, 1.0)
	var weak_strength = strength if hand_index == 0 else 0.0
	var strong_strength = strength if hand_index == 1 else 0.0

	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(
			device,
			weak_strength,
			strong_strength,
			wall_grab_vibration_duration
		)


func _find_grab_body(hand: RigidHand):
	for collider in hand.get_colliding_bodies():
		if collider is PhysicsBody2D and collider != hand and collider != _body:
			if not collider.get_parent().has_method("can_grab"):
				continue
			if not collider.get_parent().can_grab():
				continue
			return collider
	return null


func _start_grab(i: int, hand: RigidHand, target_body: PhysicsBody2D):
	_grabbed[i] = true
	_grabbed_bodies[i] = target_body
	_grab_local_pos[i] = target_body.to_local(hand.global_position)
	_grab_pos[i] = target_body.to_global(_grab_local_pos[i])
	_smooth_targets[i] = _grab_pos[i]

	_create_grab_joint(i, hand, target_body)
	_set_hand_grab_type(i, hand, RigidHand.GRAB_TYPE.WALL_GRAB)


func _stop_grab(i: int, hand: RigidHand):
	_grabbed[i] = false
	_grabbed_bodies[i] = null
	_grab_local_pos[i] = Vector2.ZERO
	_remove_grab_joint(i)
	_unlock_hand(hand)


func _update_grab_anchor(i: int, hand: RigidHand):
	if not _grabbed[i]:
		return


	var target_body = _grabbed_bodies[i]
	if not is_instance_valid(target_body):
		_stop_grab(i, hand)
		return

	_grab_pos[i] = target_body.to_global(_grab_local_pos[i])

	var joint = _grab_joints[i]
	if is_instance_valid(joint):
		joint.global_position = _grab_pos[i]


func _create_grab_joint(i: int, hand: RigidHand, target_body: PhysicsBody2D):
	_remove_grab_joint(i)

	var joint := PinJoint2D.new()
	joint.name = "GrabJoint%d" % i
	add_child(joint)
	joint.global_position = _grab_pos[i]
	joint.node_a = joint.get_path_to(target_body)
	joint.node_b = joint.get_path_to(hand)
	joint.disable_collision = true
	joint.softness = 0.0
	_grab_joints[i] = joint


func _remove_grab_joint(i: int):
	var joint = _grab_joints[i]
	if is_instance_valid(joint):
		joint.queue_free()

	_grab_joints[i] = null


func _unlock_hand(hand: RigidHand):
	hand.freeze = false
	hand.linear_velocity = _body.linear_velocity


func _move_hand(
	hand: RigidHand,
	target: Vector2,
	input_vec: Vector2,
	is_grabbed: bool
):
	if is_grabbed:
		_apply_grab_body_drive(hand, input_vec)
		_apply_grab_tangent_damping(hand, input_vec)
		_apply_arm_distance_force(hand, true)
		return

	var force = Vector2.DOWN * 手部下墜力 * hand.mass

	if input_vec.length() >= 輸入死區:
		var relative_velocity = hand.linear_velocity - _body.linear_velocity
		var spring_force = (target - hand.global_position) * 揮手力道
		var damping_force = -relative_velocity * 揮手阻尼
		force += (spring_force + damping_force) * hand.mass

	force = force.limit_length(最大力道)
	hand.apply_central_force(force)

	if input_vec.length() >= 輸入死區 and hand.get_contact_count() > 0:
		_body.apply_central_force(-force * 身體反作用 * 接觸反作用倍率)

	_apply_arm_distance_force(hand, false)


func _apply_grab_body_drive(hand: RigidHand, input_vec: Vector2):
	var from_body = hand.global_position - _body.global_position
	var dist = from_body.length()

	if dist <= 1.0:
		return

	var hand_dir = from_body.normalized()

	if input_vec.length() < 輸入死區:
		_apply_grab_support(hand_dir)
		return

	var strength = clamp(input_vec.length(), 0.0, 1.0)
	var desired_body_pos = hand.global_position + input_vec.normalized() * 手臂半徑 * strength
	var body_error = desired_body_pos - _body.global_position
	var relative_velocity = _body.linear_velocity - hand.linear_velocity
	var drive_force = body_error * 最大力道 * 抓取力道倍率
	var damping_force = -relative_velocity * 抓取阻尼

	_body.apply_central_force((drive_force + damping_force).limit_length(最大力道))





func _apply_grab_support(hand_dir: Vector2):
	var gravity_dir: Vector2 = ProjectSettings.get_setting("physics/2d/default_gravity_vector")
	var gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity"))
	var gravity_force = gravity_dir * gravity * _body.gravity_scale * _body.mass
	var support_amount = max(-gravity_force.dot(hand_dir), 0.0)

	_body.apply_central_force((hand_dir * support_amount).limit_length(最大力道))


func _apply_grab_tangent_damping(hand: RigidHand, input_vec: Vector2):
	if input_vec.length() >= 輸入死區:
		return

	var from_body = hand.global_position - _body.global_position

	if from_body.length() <= 1.0:
		return

	var hand_dir = from_body.normalized()
	var relative_velocity = _body.linear_velocity - hand.linear_velocity
	var tangent_velocity = relative_velocity - hand_dir * relative_velocity.dot(hand_dir)

	_body.apply_central_force((-tangent_velocity * 抓取切線阻尼).limit_length(最大力道))


func _apply_arm_distance_force(hand: RigidHand, hand_is_grabbed: bool):
	var offset = hand.global_position - _body.global_position
	var dist = offset.length()

	if dist <= 手臂半徑 or dist <= 0.001:
		return

	var dir = offset / dist
	var stretch = dist - 手臂半徑
	var outward_speed = (hand.linear_velocity - _body.linear_velocity).dot(dir)
	var spring_force = stretch * 最大力道
	var damping_force = max(outward_speed, 0.0) * 揮手阻尼
	var force = dir * (spring_force + damping_force)

	if hand_is_grabbed:
		_body.apply_central_force(force.limit_length(最大力道))
	else:
		hand.apply_central_force((-force).limit_length(最大力道))


func _clamp_point_inside_radius(point: Vector2, center: Vector2) -> Vector2:
	var offset = point - center
	var dist = offset.length()

	if dist <= 手臂半徑 or dist <= 0.001:
		return point

	return center + offset.normalized() * 手臂半徑


func _get_hand_input(i: int) -> Vector2:
	if i == 0:
		return Input.get_vector(
			"L_HAND_LEFT",
			"L_HAND_RIGHT",
			"L_HAND_UP",
			"L_HAND_DOWN"
		)

	return Input.get_vector(
		"R_HAND_LEFT",
		"R_HAND_RIGHT",
		"R_HAND_UP",
		"R_HAND_DOWN"
	)
