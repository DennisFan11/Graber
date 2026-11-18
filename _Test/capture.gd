extends Node
# 渲染實際遊戲畫面並截圖（非 headless），輸出到 res://Design/Screenshots/
const LEVEL := preload("res://Scene/Levels/level_1.tscn")
var _t := 0.0
var _shots := [[1.5, 1.0, "play_view"], [2.5, 0.4, "zoom_out"], [3.5, 0.15, "overview"]]

func _ready() -> void:
	add_child(LEVEL.instantiate())

func _process(delta: float) -> void:
	_t += delta
	if _shots.is_empty():
		get_tree().quit()
		return
	var s = _shots[0]
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.zoom = Vector2.ONE * s[1]
	if _t >= s[0]:
		_shots.pop_front()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://Design/Screenshots/%s.png" % s[2]))
		print("saved ", s[2], " ", img.get_size())
