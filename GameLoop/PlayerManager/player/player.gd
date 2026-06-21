@tool
class_name Player
extends Node2D

const GRAB_ACTIONS := [&"L_GRAB", &"R_GRAB"]

@export_group("手臂")
const 手臂半徑 := 56.0
@export var 輸入死區: float = 0.12
@export var 目標跟隨速度: float = 28.0

@export_group("手部旋轉")
@export var 手部旋轉力道: float = 1200.0
@export var 手部旋轉阻尼: float = 45.0
@export var 手部最大扭力: float = 2400.0

@export_group("手部力道")
@export var 揮手力道: float = 780.0
@export var 揮手阻尼: float = 58.0
@export var 最大力道: float = 2400.0

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

# Nodes
@onready var _body: RigidBody2D = $RigidBody
@onready var _hands: Array[RigidHand] = [$RigidHandL, $RigidHandR]
@onready var _hp_component: HpComponent = $HpComponent

# Movement state
var _smooth_targets: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]

# Grab state
var _grab_joints: Array[DistanceJoint2D] = [null, null]
var _weapon_use_pressed: Array[bool] = [false, false]


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	for i in range(_hands.size()):
		var hand = _hands[i]
		_smooth_targets[i] = hand.global_position


func get_hp_component() -> HpComponent:
	return _hp_component


func get_body() -> RigidBody2D:
	return _body


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_apply_body_upright_torque()

	for i in range(_hands.size()):
		var hand = _hands[i]
		var input_vec = _get_hand_input(i)

		_update_grab_state(i, hand)
		hand.rotate_to_input(
			input_vec,
			輸入死區,
			手部旋轉力道,
			手部旋轉阻尼,
			手部最大扭力
		)
		_update_target(i, hand, input_vec, delta)
		_move_hand(i, hand, _smooth_targets[i], input_vec)


func _apply_body_upright_torque() -> void:
	var angle_error := wrapf(_body.rotation, -PI, PI)
	var torque := -angle_error * body_upright_torque
	torque -= _body.angular_velocity * body_upright_damping
	_body.apply_torque(clamp(torque, -max_body_upright_torque, max_body_upright_torque))


func _update_target(i: int, hand: RigidHand, input_vec: Vector2, delta: float) -> void:
	if _is_grabbing(i):
		return

	if input_vec.length() < 輸入死區:
		_smooth_targets[i] = hand.global_position
		return

	var strength := clampf(input_vec.length(), 0.0, 1.0)
	var target := _body.global_position + input_vec.normalized() * 手臂半徑 * strength
	_smooth_targets[i] = _smooth_targets[i].lerp(
		target,
		1.0 - exp(-目標跟隨速度 * delta)
	)


func _update_grab_state(i: int, hand: RigidHand) -> void:
	if hand.has_weapon():
		if _is_grabbing(i):
			_stop_wall_grab(i, hand)
		hand.grab_type = RigidHand.GRAB_TYPE.IDLE
		var use_pressed := Input.is_action_pressed(GRAB_ACTIONS[i])
		if use_pressed and not _weapon_use_pressed[i]:
			hand.use_weapon()
		_weapon_use_pressed[i] = use_pressed
		return

	_weapon_use_pressed[i] = false
	if Input.is_action_pressed(GRAB_ACTIONS[i]):
		if not _is_grabbing(i) and _is_touching_grab_surface(hand):
			_start_wall_grab(i, hand)
		elif not _is_grabbing(i):
			hand.grab_type = RigidHand.GRAB_TYPE.AIR_GRAB
		return

	if _is_grabbing(i):
		_stop_wall_grab(i, hand)
	else:
		hand.grab_type = RigidHand.GRAB_TYPE.IDLE


func _start_wall_grab(i: int, hand: RigidHand) -> void:
	hand.linear_velocity = Vector2.ZERO
	hand.angular_velocity = 0.0
	hand.lock_rotation = true
	hand.gravity_scale = 0.0

	_grab_joints[i] = _create_grab_joint(i, hand)
	hand.grab_type = RigidHand.GRAB_TYPE.WALL_GRAB
	hand.align_texture_to_contact_normal()
	_start_wall_grab_vibration(i)


func _stop_wall_grab(i: int, hand: RigidHand) -> void:
	_remove_grab_joint(i)

	hand.lock_rotation = false
	hand.gravity_scale = 1.0
	hand.linear_velocity = _body.linear_velocity
	hand.grab_type = RigidHand.GRAB_TYPE.IDLE


func _create_grab_joint(i: int, hand: RigidHand) -> DistanceJoint2D:
	var joint := DistanceJoint2D.new()
	joint.name = "GrabJoint%d" % i
	joint.pivot = NodePath("Anchor")
	joint.links = [hand]
	joint.total_distance = 0.0

	var anchor := Marker2D.new()
	anchor.name = "Anchor"
	anchor.position = to_local(hand.global_position)
	joint.add_child(anchor)

	add_child(joint)
	return joint


func _remove_grab_joint(i: int) -> void:
	var joint := _grab_joints[i]
	if is_instance_valid(joint):
		joint.process_mode = Node.PROCESS_MODE_DISABLED
		joint.queue_free()

	_grab_joints[i] = null


func _is_grabbing(i: int) -> bool:
	return is_instance_valid(_grab_joints[i])


func equip_weapon(hand_index: int, weapon: Weapon) -> bool:
	var hand := _get_hand(hand_index)
	if hand == null:
		return false

	if _is_grabbing(hand_index):
		_stop_wall_grab(hand_index, hand)

	var mounted := hand.mount_weapon(weapon)
	if mounted:
		_weapon_use_pressed[hand_index] = Input.is_action_pressed(GRAB_ACTIONS[hand_index])
	return mounted


func unequip_weapon(hand_index: int) -> void:
	var hand := _get_hand(hand_index)
	if hand != null:
		hand.unmount_weapon()
		_weapon_use_pressed[hand_index] = false


func get_mounted_weapon(hand_index: int) -> Weapon:
	var hand := _get_hand(hand_index)
	return hand.get_mounted_weapon() if hand != null else null


func _get_hand(hand_index: int) -> RigidHand:
	if hand_index < 0 or hand_index >= _hands.size():
		push_error("[Player] Invalid hand index: %s" % hand_index)
		return null
	return _hands[hand_index]


func _start_wall_grab_vibration(hand_index: int) -> void:
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


func _is_touching_grab_surface(hand: RigidHand) -> bool:
	for surface in hand.get_grab_surfaces():
		if surface.has_method(&"can_grab") and surface.can_grab():
			return true
	return false


func _move_hand(
	i: int,
	hand: RigidHand,
	target: Vector2,
	input_vec: Vector2
) -> void:
	if _is_grabbing(i):
		if input_vec.length() < 輸入死區:
			_apply_grab_idle_forces(hand)
		else:
			_apply_grab_body_drive(hand, input_vec)
		return

	if input_vec.length() < 輸入死區:
		return

	var relative_velocity = hand.linear_velocity - _body.linear_velocity
	var spring_force = (target - hand.global_position) * 揮手力道
	var damping_force = -relative_velocity * 揮手阻尼
	var force = ((spring_force + damping_force) * hand.mass).limit_length(最大力道)
	hand.apply_central_force(force)


func _apply_grab_body_drive(hand: RigidHand, input_vec: Vector2) -> void:
	var from_body = hand.global_position - _body.global_position
	if from_body.length() <= 1.0:
		return

	var strength := clampf(input_vec.length(), 0.0, 1.0)
	var desired_body_pos = hand.global_position + input_vec.normalized() * 手臂半徑 * strength
	var body_error = desired_body_pos - _body.global_position
	var relative_velocity = _body.linear_velocity - hand.linear_velocity
	var drive_force = body_error * 最大力道 * 抓取力道倍率
	var damping_force = -relative_velocity * 抓取阻尼

	_body.apply_central_force((drive_force + damping_force).limit_length(最大力道))


func _apply_grab_idle_forces(hand: RigidHand) -> void:
	var from_body := hand.global_position - _body.global_position
	if from_body.length() <= 1.0:
		return

	var hand_dir := from_body.normalized()
	var gravity_dir: Vector2 = ProjectSettings.get_setting("physics/2d/default_gravity_vector")
	var gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity"))
	var gravity_force = gravity_dir * gravity * _body.gravity_scale * _body.mass
	var support_amount = max(-gravity_force.dot(hand_dir), 0.0)
	_body.apply_central_force((hand_dir * support_amount).limit_length(最大力道))

	var relative_velocity = _body.linear_velocity - hand.linear_velocity
	var tangent_velocity = relative_velocity - hand_dir * relative_velocity.dot(hand_dir)
	_body.apply_central_force((-tangent_velocity * 抓取切線阻尼).limit_length(最大力道))


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
