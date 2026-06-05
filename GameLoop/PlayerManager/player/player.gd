extends Node2D

@export_group("手臂")
@export var 手臂半徑: float = 56.0
@export var 輸入死區: float = 0.12
@export var 距離約束迭代: int = 4
@export var 目標跟隨速度: float = 14.0

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

@onready var body: RigidBody2D = $RigidBody
@onready var hand_l: RigidBody2D = $RigidHandL
@onready var hand_r: RigidBody2D = $RigidHandR

var hands: Array[RigidBody2D] = []
var targets = [Vector2.ZERO, Vector2.ZERO]
var smooth_targets = [Vector2.ZERO, Vector2.ZERO]
var grabbed = [false, false]
var grab_pos = [Vector2.ZERO, Vector2.ZERO]


func _ready():
	apply_safe_defaults()
	hands = [hand_l, hand_r]

	for i in range(hands.size()):
		var hand = hands[i]
		var start_pos = clamp_point_inside_radius(hand.global_position, body.global_position)

		targets[i] = start_pos
		smooth_targets[i] = start_pos
		grab_pos[i] = start_pos

		hand.global_position = start_pos
		hand.set_meta("gravity_scale", hand.gravity_scale)


func apply_safe_defaults():
	if 手臂半徑 <= 0.0:
		手臂半徑 = 56.0
	if 最大力道 <= 0.0:
		最大力道 = 2400.0
	if 距離約束迭代 <= 0:
		距離約束迭代 = 4
	if 目標跟隨速度 <= 0.0:
		目標跟隨速度 = 14.0
	if 抓取切線阻尼 < 0.0:
		抓取切線阻尼 = 10.0


func _physics_process(delta):
	var center = body.global_position

	for i in range(hands.size()):
		var hand = hands[i]
		var input_vec = get_hand_input(i)

		update_grab_state(i, hand)
		update_target(i, hand, input_vec, center, delta)
		move_hand(hand, smooth_targets[i], input_vec, grabbed[i])

	for j in range(距離約束迭代):
		for i in range(hands.size()):
			limit_arm_distance_hard(hands[i], grabbed[i])


func update_target(i: int, hand: RigidBody2D, input_vec: Vector2, center: Vector2, delta: float):
	if grabbed[i]:
		targets[i] = grab_pos[i]
		smooth_targets[i] = grab_pos[i]
		lock_hand_position(hand, grab_pos[i])
		return

	if input_vec.length() < 輸入死區:
		targets[i] = hand.global_position
		smooth_targets[i] = hand.global_position
		return

	var strength = clamp(input_vec.length(), 0.0, 1.0)
	targets[i] = center + input_vec.normalized() * 手臂半徑 * strength
	smooth_targets[i] = smooth_targets[i].lerp(
		targets[i],
		1.0 - exp(-目標跟隨速度 * delta)
	)


func update_grab_state(i: int, hand: RigidBody2D):
	var action_name = "L_GRAB" if i == 0 else "R_GRAB"
	var pressing = Input.is_action_pressed(action_name)

	if pressing and not grabbed[i] and hand.get_contact_count() > 0:
		grabbed[i] = true
		grab_pos[i] = hand.global_position
		smooth_targets[i] = grab_pos[i]
		lock_hand(hand, grab_pos[i])
	elif not pressing and grabbed[i]:
		grabbed[i] = false
		unlock_hand(hand)


func lock_hand(hand: RigidBody2D, pos: Vector2):
	lock_hand_position(hand, pos)
	hand.gravity_scale = 0.0
	hand.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	hand.freeze = true


func lock_hand_position(hand: RigidBody2D, pos: Vector2):
	hand.global_position = pos
	hand.linear_velocity = Vector2.ZERO
	hand.angular_velocity = 0.0


func unlock_hand(hand: RigidBody2D):
	hand.freeze = false
	hand.gravity_scale = hand.get_meta("gravity_scale", 1.0)
	hand.linear_velocity = body.linear_velocity


func move_hand(
	hand: RigidBody2D,
	target: Vector2,
	input_vec: Vector2,
	is_grabbed: bool
):
	if is_grabbed:
		apply_grab_body_drive(hand, input_vec)
		apply_grab_tangent_damping(hand, input_vec)
		limit_arm_distance_hard(hand, true)
		return

	var force = Vector2.DOWN * 手部下墜力 * hand.mass

	if input_vec.length() >= 輸入死區:
		var relative_velocity = hand.linear_velocity - body.linear_velocity
		var spring_force = (target - hand.global_position) * 揮手力道
		var damping_force = -relative_velocity * 揮手阻尼
		force += (spring_force + damping_force) * hand.mass

	force = force.limit_length(最大力道)
	hand.apply_central_force(force)

	if input_vec.length() >= 輸入死區 and hand.get_contact_count() > 0:
		body.apply_central_force(-force * 身體反作用 * 接觸反作用倍率)

	limit_arm_distance_hard(hand, false)


func apply_grab_body_drive(hand: RigidBody2D, input_vec: Vector2):
	var from_body = hand.global_position - body.global_position
	var dist = from_body.length()

	if dist <= 1.0:
		return

	var hand_dir = from_body.normalized()

	if input_vec.length() < 輸入死區:
		apply_grab_support(hand_dir)
		return

	var strength = clamp(input_vec.length(), 0.0, 1.0)
	var desired_body_pos = hand.global_position + input_vec.normalized() * 手臂半徑 * strength
	var body_error = desired_body_pos - body.global_position
	var relative_velocity = body.linear_velocity - hand.linear_velocity
	var drive_force = body_error * 最大力道 * 抓取力道倍率
	var damping_force = -relative_velocity * 抓取阻尼

	body.apply_central_force((drive_force + damping_force).limit_length(最大力道))


func apply_grab_support(hand_dir: Vector2):
	var gravity_dir: Vector2 = ProjectSettings.get_setting("physics/2d/default_gravity_vector")
	var gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity"))
	var gravity_force = gravity_dir * gravity * body.gravity_scale * body.mass
	var support_amount = max(-gravity_force.dot(hand_dir), 0.0)

	body.apply_central_force((hand_dir * support_amount).limit_length(最大力道))


func apply_grab_tangent_damping(hand: RigidBody2D, input_vec: Vector2):
	if input_vec.length() >= 輸入死區:
		return

	var from_body = hand.global_position - body.global_position

	if from_body.length() <= 1.0:
		return

	var hand_dir = from_body.normalized()
	var relative_velocity = body.linear_velocity - hand.linear_velocity
	var tangent_velocity = relative_velocity - hand_dir * relative_velocity.dot(hand_dir)

	body.apply_central_force((-tangent_velocity * 抓取切線阻尼).limit_length(最大力道))


func limit_arm_distance_hard(hand: RigidBody2D, hand_is_locked: bool):
	var offset = hand.global_position - body.global_position
	var dist = offset.length()

	if dist <= 手臂半徑:
		return

	var dir = offset.normalized()
	var outward_speed = (hand.linear_velocity - body.linear_velocity).dot(dir)

	if hand_is_locked:
		body.linear_velocity += dir * outward_speed
	elif outward_speed > 0.0:
		hand.linear_velocity -= dir * outward_speed

	var correction = dir * (dist - 手臂半徑)

	if hand_is_locked:
		body.global_position += correction
	else:
		hand.global_position -= correction


func clamp_point_inside_radius(point: Vector2, center: Vector2) -> Vector2:
	var offset = point - center
	var dist = offset.length()

	if dist <= 手臂半徑 or dist <= 0.001:
		return point

	return center + offset.normalized() * 手臂半徑


func get_hand_input(i: int) -> Vector2:
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
