class_name HpComponent
extends Node

signal hp_changed(current_hp: float, max_hp: float)
signal damaged(
	amount: float,
	source: Node,
	source_team: DamageSystem.TEAM,
	receiver_team: DamageSystem.TEAM,
	damage_position: Vector2
)
signal died(
	source: Node,
	source_team: DamageSystem.TEAM,
	receiver_team: DamageSystem.TEAM,
	damage_position: Vector2
)

@export var receiver_team: DamageSystem.TEAM = DamageSystem.TEAM.IDLE
@export_range(0.0, 1000000.0, 1.0, "or_greater") var max_hp: float = 100.0
@export var start_with_max_hp: bool = true
@export_range(0.0, 1000000.0, 1.0, "or_greater") var initial_hp: float = 100.0

var current_hp: float


func _ready() -> void:
	current_hp = max_hp if start_with_max_hp else clampf(initial_hp, 0.0, max_hp)
	hp_changed.emit(current_hp, max_hp)


func take_damage(
	amount: float,
	source: Node = null,
	source_team: DamageSystem.TEAM = DamageSystem.TEAM.IDLE,
	damage_position: Vector2 = Vector2.INF
) -> float:
	if amount <= 0.0 or current_hp <= 0.0:
		return 0.0

	var applied_damage := minf(amount, current_hp)
	current_hp -= applied_damage
	if not damage_position.is_finite():
		damage_position = get_damage_position()
	damaged.emit(applied_damage, source, source_team, receiver_team, damage_position)
	hp_changed.emit(current_hp, max_hp)

	if current_hp <= 0.0:
		died.emit(source, source_team, receiver_team, damage_position)

	return applied_damage


func heal(amount: float) -> float:
	if amount <= 0.0 or current_hp <= 0.0:
		return 0.0

	var applied_healing := minf(amount, max_hp - current_hp)
	current_hp += applied_healing
	hp_changed.emit(current_hp, max_hp)
	return applied_healing


func is_dead() -> bool:
	return current_hp <= 0.0


func get_damage_position() -> Vector2:
	var receiver := get_parent() as Node2D
	if receiver != null:
		return receiver.global_position
	return Vector2.ZERO
