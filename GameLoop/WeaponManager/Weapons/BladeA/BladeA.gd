class_name BladeA
extends Weapon

signal hit(target: HpComponent, damage: float)

@export_group("Damage")
@export_range(0.0, 1000000.0, 1.0, "or_greater") var damage: float = 25.0
@export_range(0.0, 100000.0, 10.0, "or_greater") var activation_speed: float = 450.0

@onready var _hit_area: Area2D = $Area2D
@onready var _blade_tip: Marker2D = $BladeTip
@onready var _trail: Trail2D = $Trail2D

var _previous_tip_position := Vector2.ZERO
var _has_previous_tip_position := false
var _is_damage_active := false
var _damaged_targets: Dictionary = {}


func _ready() -> void:
	_trail.emit = false


func _physics_process(delta: float) -> void:
	
	var tip_position := _blade_tip.global_position
	if not _has_previous_tip_position:
		_previous_tip_position = tip_position
		_has_previous_tip_position = true
		return

	var speed := tip_position.distance_to(_previous_tip_position) / maxf(delta, 0.000001)
	#print(speed)
	_previous_tip_position = tip_position
	_set_damage_active(speed >= activation_speed)

	if _is_damage_active:
		_damage_overlapping_bodies()


func _set_damage_active(value: bool) -> void:
	if _is_damage_active == value:
		return

	_is_damage_active = value
	_trail.emit = value

	if value:
		_trail.restart()
	else:
		_damaged_targets.clear()


func _damage_overlapping_bodies() -> void:
	var overlapping_targets: Dictionary = {}
	for body in _hit_area.get_overlapping_bodies():
		var hp_component := DamageSystem.get_hp_component(body)
		if hp_component == null:
			continue

		var target_id := hp_component.get_instance_id()
		overlapping_targets[target_id] = true
		if _damaged_targets.has(target_id):
			continue

		_damaged_targets[target_id] = true
		var applied_damage := DamageSystem.apply_damage_to_component(
			hp_component,
			damage,
			self,
			source_team,
			_blade_tip.global_position
		)
		if applied_damage > 0.0:
			hit.emit(hp_component, applied_damage)

	for target_id in _damaged_targets.keys():
		if not overlapping_targets.has(target_id):
			_damaged_targets.erase(target_id)
