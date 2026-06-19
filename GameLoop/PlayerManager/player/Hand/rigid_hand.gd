class_name RigidHand
extends RigidBody2D

enum GRAB_TYPE {IDLE, AIR_GRAB, WALL_GRAB}

@onready var _weapon_mounter: WeaponMounter = %WeaponMounter

var grab_type: GRAB_TYPE = GRAB_TYPE.IDLE:
	set(value):
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


func _ready() -> void:
	grab_type = grab_type


func rotate_to_input(
	input_vec: Vector2,
	deadzone: float,
	rotation_force: float,
	rotation_damping: float,
	max_torque: float
) -> void:
	if grab_type == GRAB_TYPE.WALL_GRAB or input_vec.length() < deadzone:
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
