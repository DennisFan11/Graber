extends RigidBody2D


var collision_normal := Vector2.ZERO









enum GRAB_TYPE {IDLE, AIR_GRAB, WALL_GRAB}
var grab_type: GRAB_TYPE = GRAB_TYPE.IDLE:
	set(new):
		%HandClose.visible = false
		%Hand.visible = false
		%AirGrab.visible = false
		match new:
			GRAB_TYPE.IDLE:
				%Hand.visible = true
			GRAB_TYPE.AIR_GRAB:
				%AirGrab.visible = true
			GRAB_TYPE.WALL_GRAB:
				%HandClose.visible = true
				if grab_type != new:
					%WallGrabAudio.play()
		grab_type = new


func _ready():
	grab_type = grab_type





func _integrate_forces(state: PhysicsDirectBodyState2D):
	var normal := get_collision_normal(state)

	if normal == Vector2.ZERO:
		return

	collision_normal = normal
	%Close.global_rotation = collision_normal.angle()+PI/2.0


func get_collision_normal(state: PhysicsDirectBodyState2D) -> Vector2:
	var contact_count := state.get_contact_count()

	if contact_count <= 0:
		return Vector2.ZERO

	var normal_sum := Vector2.ZERO

	for i in range(contact_count):
		normal_sum += global_transform.basis_xform(state.get_contact_local_normal(i))

	if normal_sum.length_squared() <= 0.0001:
		return Vector2.ZERO

	return normal_sum.normalized()
