extends Node2D
# 移除武器系統後，確認抓牆仍正常的 headless 測試
const PLAYER := preload("res://GameLoop/PlayerManager/player/Player.tscn")
const TERRAIN := preload("res://GameLoop/TerrainManager/Terrains/TerrainBase.tscn")

var _player: Player
var _t := 0.0
var _next_log := 0.0

func _ready() -> void:
	var wall := TERRAIN.instantiate()
	wall.polygon = PackedVector2Array([Vector2(40, -600), Vector2(400, -600), Vector2(400, 600), Vector2(40, 600)])
	add_child(wall)
	_player = PLAYER.instantiate()
	add_child(_player)

func _physics_process(delta: float) -> void:
	_t += delta
	# 右手推向右邊的牆，0.3 秒後按住右手抓取；3 秒後放開
	Input.action_press(&"R_HAND_RIGHT", 1.0)
	if _t >= 0.3 and _t < 3.0:
		Input.action_press(&"R_GRAB", 1.0)
	else:
		Input.action_release(&"R_GRAB")
	if _t >= _next_log:
		_next_log += 0.5
		var b := _player.get_body()
		var hand: RigidHand = _player.get_node("RigidHandR")
		print("t=%.1f grab=%s body_y=%.1f vy=%.1f" % [
			_t, RigidHand.GRAB_TYPE.keys()[hand.grab_type], b.global_position.y, b.linear_velocity.y])
	if _t > 4.0:
		get_tree().quit()
