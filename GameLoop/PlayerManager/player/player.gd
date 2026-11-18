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
# 手的目標位置，以「相對身體的偏移」儲存，才不會在身體移動時落後
var _smooth_offsets: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]

# Grab state
var _grab_joints: Array[DistanceJoint2D] = [null, null]


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_body.can_sleep = false
	for i in range(_hands.size()):
		var hand = _hands[i]
		hand.can_sleep = false
		_smooth_offsets[i] = hand.global_position - _body.global_position


func get_hp_component() -> HpComponent:
	return _hp_component


func get_body() -> RigidBody2D:
	return _body


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_apply_body_upright_torque()

	for i in range(_hands.size()):
		_apply_arm_constraint(i, _hands[i], delta)

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
		_move_hand(i, hand, _body.global_position + _smooth_offsets[i], input_vec)


# 手臂長度上限的繩索約束（取代原本的 DistanceJointL/R）。
# 揮手的力只施加在手上、沒有反作用力，等於是外力。只要手臂拉直時這個約束會拉動身體，
# 手的外力就會經由手臂變成身體的升力（舉雙手就往上飄）。
# 所以沒抓東西時，只把手拉回身體，身體不受手臂影響；
# 抓牆時手固定在牆上，才由手臂拉動身體（攀爬）。
func _apply_arm_constraint(i: int, hand: RigidHand, delta: float) -> void:
	var offset := hand.global_position - _body.global_position
	var distance := offset.length()
	if distance <= 0.001:
		return

	var normal := offset / distance
	var relative_speed := (hand.linear_velocity - _body.linear_velocity).dot(normal)
	# 讓下一幀的距離剛好回到手臂半徑；只拉不推（繩索）
	var velocity_change := (手臂半徑 - distance) / delta - relative_speed
	if velocity_change >= 0.0:
		return

	if _is_grabbing(i):
		_body.linear_velocity -= normal * velocity_change
	else:
		hand.linear_velocity += normal * velocity_change


func _apply_body_upright_torque() -> void:
	var angle_error := wrapf(_body.rotation, -PI, PI)
	var torque := -angle_error * body_upright_torque
	torque -= _body.angular_velocity * body_upright_damping
	_body.apply_torque(clamp(torque, -max_body_upright_torque, max_body_upright_torque))


func _update_target(i: int, hand: RigidHand, input_vec: Vector2, delta: float) -> void:
	if _is_grabbing(i):
		return

	if input_vec.length() < 輸入死區:
		_smooth_offsets[i] = hand.global_position - _body.global_position
		return

	# 在身體座標中平滑。若用世界座標平滑，身體下墜時目標會落後在身體上方，
	# 超出手臂長度，手被一直往上拉，再透過手臂把身體吊上去 → 舉手往上飄。
	var strength := clampf(input_vec.length(), 0.0, 1.0)
	var target_offset := input_vec.normalized() * 手臂半徑 * strength
	_smooth_offsets[i] = _smooth_offsets[i].lerp(
		target_offset,
		1.0 - exp(-目標跟隨速度 * delta)
	)


func _update_grab_state(i: int, hand: RigidHand) -> void:
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
	SteamInputBridge.vibrate(weak_strength, strong_strength, wall_grab_vibration_duration)


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
