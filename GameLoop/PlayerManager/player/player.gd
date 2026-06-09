extends Node2D

const RigidHand = preload("res://GameLoop/PlayerManager/player/Hand/rigid_hand.gd")

@export_group("手臂")
@export var 手臂半徑: float = 56.0
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

@onready var body: RigidBody2D = $RigidBody
@onready var hand_l: RigidHand = $RigidHandL
@onready var hand_r: RigidHand = $RigidHandR

var hands: Array[RigidHand] = []
var targets = [Vector2.ZERO, Vector2.ZERO]
var smooth_targets = [Vector2.ZERO, Vector2.ZERO]
var grabbed = [false, false]
var grab_pos = [Vector2.ZERO, Vector2.ZERO]
var grabbed_bodies = [null, null]
var grab_local_pos = [Vector2.ZERO, Vector2.ZERO]
var grab_joints = [null, null]


func _ready():
	apply_safe_defaults()
	apply_body_upright_defaults()
	hands = [hand_l, hand_r]

	for i in range(hands.size()):
		var hand = hands[i]
		var start_pos = clamp_point_inside_radius(hand.global_position, body.global_position)

		targets[i] = start_pos
		smooth_targets[i] = start_pos
		grab_pos[i] = start_pos

		hand.global_position = start_pos


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


func apply_body_upright_defaults():
	if body_upright_torque < 0.0:
		body_upright_torque = 850.0
	if body_upright_damping < 0.0:
		body_upright_damping = 70.0
	if max_body_upright_torque <= 0.0:
		max_body_upright_torque = 2400.0


func _physics_process(delta):
	var center = body.global_position
	apply_body_upright_torque()

	for i in range(hands.size()):
		var hand = hands[i]
		var input_vec = get_hand_input(i)

		update_grab_state(i, hand)
		update_grab_anchor(i, hand)
		update_target(i, hand, input_vec, center, delta)
		move_hand(hand, smooth_targets[i], input_vec, grabbed[i])

	


func apply_body_upright_torque():
	var angle_error := wrapf(body.rotation, -PI, PI)
	var torque := -angle_error * body_upright_torque
	torque -= body.angular_velocity * body_upright_damping
	body.apply_torque(clamp(torque, -max_body_upright_torque, max_body_upright_torque))


func update_target(i: int, hand: RigidHand, input_vec: Vector2, center: Vector2, delta: float):
	if grabbed[i]:
		targets[i] = grab_pos[i]
		smooth_targets[i] = grab_pos[i]
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


func update_grab_state(i: int, hand: RigidHand):
	var action_name = "L_GRAB" if i == 0 else "R_GRAB"
	var pressing = Input.is_action_pressed(action_name)

	if pressing and not grabbed[i]:
		var target_body = find_grab_body(hand)

		if target_body:
			start_grab(i, hand, target_body)
		else:
			set_hand_grab_type(i, hand, RigidHand.GRAB_TYPE.AIR_GRAB)
	elif not pressing and grabbed[i]:
		stop_grab(i, hand)
		set_hand_grab_type(i, hand, RigidHand.GRAB_TYPE.IDLE)
	elif pressing:
		var grab_type = RigidHand.GRAB_TYPE.WALL_GRAB if grabbed[i] else RigidHand.GRAB_TYPE.AIR_GRAB
		set_hand_grab_type(i, hand, grab_type)
	else:
		set_hand_grab_type(i, hand, RigidHand.GRAB_TYPE.IDLE)


func set_hand_grab_type(i: int, hand: RigidHand, grab_type: int):
	var was_wall_grab = hand.grab_type == RigidHand.GRAB_TYPE.WALL_GRAB
	hand.grab_type = grab_type

	if not was_wall_grab and grab_type == RigidHand.GRAB_TYPE.WALL_GRAB:
		start_wall_grab_vibration(i)



func start_wall_grab_vibration(hand_index: int):
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


func find_grab_body(hand: RigidHand):
	for collider in hand.get_colliding_bodies():
		if collider is PhysicsBody2D and collider != hand and collider != body:
			if collider.get_parent() is not TerrainBase:
				continue
			if not (collider.get_parent() as TerrainBase).can_grab():
				continue
			return collider
	return null


func start_grab(i: int, hand: RigidHand, target_body: PhysicsBody2D):
	grabbed[i] = true
	grabbed_bodies[i] = target_body
	grab_local_pos[i] = target_body.to_local(hand.global_position)
	grab_pos[i] = target_body.to_global(grab_local_pos[i])
	smooth_targets[i] = grab_pos[i]

	create_grab_joint(i, hand, target_body)
	set_hand_grab_type(i, hand, RigidHand.GRAB_TYPE.WALL_GRAB)


func stop_grab(i: int, hand: RigidHand):
	grabbed[i] = false
	grabbed_bodies[i] = null
	grab_local_pos[i] = Vector2.ZERO
	remove_grab_joint(i)
	unlock_hand(hand)


func update_grab_anchor(i: int, hand: RigidHand):
	if not grabbed[i]:
		return


	var target_body = grabbed_bodies[i]
	if not is_instance_valid(target_body):
		stop_grab(i, hand)
		return

	grab_pos[i] = target_body.to_global(grab_local_pos[i])

	var joint = grab_joints[i]
	if is_instance_valid(joint):
		joint.global_position = grab_pos[i]


func create_grab_joint(i: int, hand: RigidHand, target_body: PhysicsBody2D):
	remove_grab_joint(i)

	var joint := PinJoint2D.new()
	joint.name = "GrabJoint%d" % i
	add_child(joint)
	joint.global_position = grab_pos[i]
	joint.node_a = joint.get_path_to(target_body)
	joint.node_b = joint.get_path_to(hand)
	joint.disable_collision = true
	joint.softness = 0.0
	grab_joints[i] = joint


func remove_grab_joint(i: int):
	var joint = grab_joints[i]
	if is_instance_valid(joint):
		joint.queue_free()

	grab_joints[i] = null


func unlock_hand(hand: RigidHand):
	hand.freeze = false
	hand.linear_velocity = body.linear_velocity


func move_hand(
	hand: RigidHand,
	target: Vector2,
	input_vec: Vector2,
	is_grabbed: bool
):
	if is_grabbed:
		apply_grab_body_drive(hand, input_vec)
		apply_grab_tangent_damping(hand, input_vec)
		apply_arm_distance_force(hand, true)
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

	apply_arm_distance_force(hand, false)


func apply_grab_body_drive(hand: RigidHand, input_vec: Vector2):
	var from_body = hand.global_position - body.global_position
	var dist = from_body.length()

	if dist <= 1.0:
		return

	var hand_dir = from_body.normalized()
	var safe_input_vec = get_wall_grab_safe_input(hand, input_vec)
	input_vec = safe_input_vec

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


func get_wall_grab_safe_input(hand: RigidHand, input_vec: Vector2) -> Vector2:
	return input_vec
	#if input_vec.is_zero_approx() or hand.collision_normal == Vector2.ZERO:
		#return input_vec
#
	#var wall_normal = hand.collision_normal.normalized()
	#var body_side = body.global_position - hand.global_position
#
	#if body_side.length_squared() > 0.0001 and wall_normal.dot(body_side) < 0.0:
		#wall_normal = -wall_normal
#
	#var normal_amount = input_vec.dot(wall_normal)
#
	#if normal_amount >= 0.0:
		#return input_vec
#
	#return input_vec - wall_normal * normal_amount


func apply_grab_support(hand_dir: Vector2):
	var gravity_dir: Vector2 = ProjectSettings.get_setting("physics/2d/default_gravity_vector")
	var gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity"))
	var gravity_force = gravity_dir * gravity * body.gravity_scale * body.mass
	var support_amount = max(-gravity_force.dot(hand_dir), 0.0)

	body.apply_central_force((hand_dir * support_amount).limit_length(最大力道))


func apply_grab_tangent_damping(hand: RigidHand, input_vec: Vector2):
	if input_vec.length() >= 輸入死區:
		return

	var from_body = hand.global_position - body.global_position

	if from_body.length() <= 1.0:
		return

	var hand_dir = from_body.normalized()
	var relative_velocity = body.linear_velocity - hand.linear_velocity
	var tangent_velocity = relative_velocity - hand_dir * relative_velocity.dot(hand_dir)

	body.apply_central_force((-tangent_velocity * 抓取切線阻尼).limit_length(最大力道))


func apply_arm_distance_force(hand: RigidHand, hand_is_grabbed: bool):
	var offset = hand.global_position - body.global_position
	var dist = offset.length()

	if dist <= 手臂半徑 or dist <= 0.001:
		return

	var dir = offset / dist
	var stretch = dist - 手臂半徑
	var outward_speed = (hand.linear_velocity - body.linear_velocity).dot(dir)
	var spring_force = stretch * 最大力道
	var damping_force = max(outward_speed, 0.0) * 揮手阻尼
	var force = dir * (spring_force + damping_force)

	if hand_is_grabbed:
		body.apply_central_force(force.limit_length(最大力道))
	else:
		hand.apply_central_force((-force).limit_length(最大力道))


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
