class_name DamageSystem
extends RefCounted

enum TEAM {
	IDLE,
	PLAYER,
	ENEMY,
}

## 傷害系統的碰撞中間層。
## 可受傷物件的結構必須是：
##   Target (提供 get_hp_component())
##   ├── PhysicsBody2D
##   └── HpComponent


static func get_hp_component(physics_body: Node) -> HpComponent:
	if not is_instance_valid(physics_body):
		return null

	var provider := physics_body.get_parent()
	if provider == null or not provider.has_method(&"get_hp_component"):
		return null

	var component = provider.call(&"get_hp_component")
	if component is HpComponent:
		return component

	push_warning(
		"[DamageSystem] %s.get_hp_component() did not return an HpComponent" % provider.name
	)
	return null


static func apply_damage(
	physics_body: Node,
	amount: float,
	source: Node = null,
	source_team: TEAM = TEAM.IDLE,
	damage_position: Vector2 = Vector2.INF
) -> float:
	var hp_component := get_hp_component(physics_body)
	if not damage_position.is_finite() and physics_body is Node2D:
		damage_position = physics_body.global_position
	return apply_damage_to_component(hp_component, amount, source, source_team, damage_position)


static func apply_damage_to_component(
	hp_component: HpComponent,
	amount: float,
	source: Node = null,
	source_team: TEAM = TEAM.IDLE,
	damage_position: Vector2 = Vector2.INF
) -> float:
	if not is_instance_valid(hp_component):
		return 0.0

	if not damage_position.is_finite():
		damage_position = hp_component.get_damage_position()

	var applied_damage := hp_component.take_damage(
		amount,
		source,
		source_team,
		damage_position
	)
	if applied_damage > 0.0:
		_draw_damage_number(damage_position, applied_damage, hp_component.receiver_team)
	return applied_damage


static func _draw_damage_number(
	damage_position: Vector2,
	amount: float,
	receiver_team: TEAM
) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var debug_draw := tree.get_first_node_in_group(&"debug_draw") as DebugDraw
	if is_instance_valid(debug_draw):
		debug_draw.d_draw_damage_number(damage_position, amount, receiver_team)
