extends Node2D
# 舉雙手是否會浮空的 headless 測試
const PLAYER := preload("res://GameLoop/PlayerManager/player/Player.tscn")

var _player: Player
var _t := 0.0
var _next_log := 0.0
var _scenario := ""

func _ready() -> void:
	_scenario = OS.get_environment("FLOAT_SCENARIO")
	if _scenario == "":
		_scenario = "floor"
	if _scenario == "floor":
		var floor_body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(4000, 100)
		shape.shape = rect
		floor_body.position = Vector2(0, 100)
		floor_body.add_child(shape)
		add_child(floor_body)
	_player = PLAYER.instantiate()
	add_child(_player)

func _physics_process(delta: float) -> void:
	_t += delta
	var up := _t >= 1.0
	for a in [&"L_HAND_UP", &"R_HAND_UP"]:
		if up:
			Input.action_press(a, 1.0)
		else:
			Input.action_release(a)
	if _t >= _next_log:
		_next_log += 0.25
		var b := _player.get_body()
		print("[%s] t=%.2f up=%s body_y=%.1f vy=%.1f handL_y=%.1f handR_y=%.1f" % [
			_scenario, _t, up, b.global_position.y, b.linear_velocity.y,
			_player.get_node("RigidHandL").global_position.y,
			_player.get_node("RigidHandR").global_position.y])
	if _t > 5.0:
		get_tree().quit()
