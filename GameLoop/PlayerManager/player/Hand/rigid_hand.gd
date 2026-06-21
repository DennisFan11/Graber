class_name RigidHand
extends RigidBody2D

enum GRAB_TYPE {IDLE, AIR_GRAB, WALL_GRAB}

@export var 柔性抓取反向力道: float = 1400.0

@onready var _weapon_mounter: WeaponMounter = %WeaponMounter
@onready var _grab_sensor: Area2D = %GrabSensor

var grab_type: GRAB_TYPE = GRAB_TYPE.IDLE:
	set(value):
		if value != GRAB_TYPE.WALL_GRAB:
			_clear_grab_constraint_provider()

		%HandClose.visible = false
		%Hand.visible = false
		%AirGrab.visible = false

		match value:
			GRAB_TYPE.IDLE:
				%Hand.visible = true
			GRAB_TYPE.AIR_GRAB:
				%AirGrab.visible = true
			GRAB_TYPE.WALL_GRAB:
				%HandClose.visible = true

				if grab_type != value:
					%WallGrabAudio.play()

		grab_type = value

var _grab_constraint_provider: Node


func _ready() -> void:
	grab_type = grab_type


func rotate_to_input(
	input_vec: Vector2,
	deadzone: float,
	rotation_force: float,
	rotation_damping: float,
	max_torque: float
) -> void:
	if grab_type == GRAB_TYPE.WALL_GRAB:
		if _grab_constraint_provider != null and input_vec.length() >= deadzone:
			apply_central_force(
				-input_vec.limit_length(1.0) * maxf(柔性抓取反向力道, 0.0)
			)
		return

	if input_vec.length() < deadzone:
		return

	var angle_error := wrapf(input_vec.angle() - rotation, -PI, PI)
	var torque := angle_error * rotation_force
	torque -= angular_velocity * rotation_damping
	apply_torque(
		clampf(torque, -maxf(max_torque, 0.0), maxf(max_torque, 0.0))
	)


func align_texture_to_contact_normal() -> void:
	var state := PhysicsServer2D.body_get_direct_state(get_rid())
	if state == null:
		return

	var normal := Vector2.ZERO
	for i in range(state.get_contact_count()):
		normal += state.get_contact_local_normal(i)

	if not normal.is_zero_approx():
		var close_parent := %HandClose.get_parent() as Node2D
		var local_normal := close_parent.global_transform.basis_xform_inv(normal.normalized())
		%HandClose.rotation = local_normal.angle() + PI / 2.0


func get_grab_surfaces() -> Array[Node]:
	var surfaces: Array[Node] = []

	for collider in get_colliding_bodies():
		var surface := collider.get_parent()
		if not surfaces.has(surface):
			surfaces.append(surface)

	for area in _grab_sensor.get_overlapping_areas():
		var surface := area.get_parent()
		if not surfaces.has(surface):
			surfaces.append(surface)

	return surfaces


func configure_grab_constraint(
	provider: Node,
	anchor_global_position: Vector2,
	max_distance: float
) -> bool:
	if _grab_constraint_provider != null and _grab_constraint_provider != provider:
		return false

	for child in get_parent().get_children():
		if (
			child is DistanceJoint2D
			and child.links.size() == 1
			and child.links.has(self)
			and child.pivot != NodePath("")
		):
			var anchor := child.get_node(child.pivot) as Node2D
			anchor.global_position = anchor_global_position
			child.total_distance = maxf(max_distance, 0.0)
			child.fixed_distance = true
			_grab_constraint_provider = provider
			%HandClose.visible = false
			%Hand.visible = false
			%AirGrab.visible = true
			return true

	return false


func release_grab_constraint(provider: Node) -> void:
	if _grab_constraint_provider != provider:
		return

	for child in get_parent().get_children():
		if (
			child is DistanceJoint2D
			and child.links.size() == 1
			and child.links.has(self)
			and child.pivot != NodePath("")
		):
			child.process_mode = Node.PROCESS_MODE_DISABLED
			child.queue_free()
			break

	_clear_grab_constraint_provider()
	grab_type = GRAB_TYPE.IDLE


func _clear_grab_constraint_provider() -> void:
	_grab_constraint_provider = null


func mount_weapon(weapon: Weapon) -> bool:
	return _weapon_mounter.mount_weapon(weapon)


func unmount_weapon() -> void:
	_weapon_mounter.unmount_weapon()


func has_weapon() -> bool:
	return _weapon_mounter.has_weapon()


func use_weapon() -> bool:
	return _weapon_mounter.use_weapon()


func get_mounted_weapon() -> Weapon:
	return _weapon_mounter.get_mounted_weapon()
