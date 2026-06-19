@tool
class_name Trail2D
extends Line2D

## Godot 4.7 Trail2D
## 單檔 class_name 版本，不需要 plugin.gd。
##
## 預設結構：
##   FollowSpace(Node2D)  <- 舊尾跡會跟著這個座標系一起被拖走
##   └── Target(Node2D)   <- Trail 追蹤這個節點的移動
##       └── Trail2D
##
## 不設定 target_path 時，target = parent。
## 不設定 follow_space_path 時，follow_space = target 的 parent。

@export var emit: bool = true
@export var run_in_editor: bool = false

## 要追蹤的 Node2D。
## 空值時自動使用 parent。
@export var target_path: NodePath = NodePath("")

## 舊尾跡要跟著哪個 Node2D 的座標系一起移動。
## 空值時自動使用 target 的 parent。
@export var follow_space_path: NodePath = NodePath("")

## 每個點的存活時間，單位：秒。
@export_range(0.01, 60.0, 0.01, "or_greater") var lifetime: float = 0.5

## target 移動超過這個距離才新增一個點。
## 0 = 每幀新增。
@export_range(0.0, 4096.0, 0.5, "or_greater") var distance: float = 20.0

## 最多保留幾個點。
@export_range(2, 4096, 1, "or_greater") var segments: int = 20

## 追蹤點相對於 target 的本地偏移。
@export var local_offset: Vector2 = Vector2.ZERO

## true 時，_ready() 會把 Trail2D 節點自己的 position 當成 local_offset。
## 這樣你可以直接在編輯器裡把 Trail2D 放到武器尖端 / 角色腳底。
@export var use_initial_position_as_offset: bool = true

## true 時，最後一個點會貼著 target 目前位置。
## target 移動還沒超過 distance 時，尾跡頭部不會斷開。
@export var attach_head_to_target: bool = true

## true：emit = false 時完全暫停，不新增、不老化、不消失。
## 這是原版 Trail 的殘影保留特性。
@export var freeze_when_emit_stops: bool = true

class TrailPoint:
	var position: Vector2
	var age: float

	func _init(p_position: Vector2, p_age: float) -> void:
		position = p_position
		age = p_age


var _target: Node2D = null
var _follow_space: Node2D = null
var _trail_points: Array[TrailPoint] = []


func _ready() -> void:
	if use_initial_position_as_offset and local_offset == Vector2.ZERO:
		local_offset = position

	closed = false

	_resolve_target()
	_resolve_follow_space()
	_sync_to_follow_space()
	clear_trail()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not run_in_editor:
		return

	if not is_instance_valid(_target):
		_resolve_target()
		_resolve_follow_space()

	if not is_instance_valid(_follow_space):
		_resolve_follow_space()

	_sync_to_follow_space()

	if not emit:
		if freeze_when_emit_stops:
			return

		_update_point_lifetimes(delta)
		_trim_old_points()
		_rebuild_line()
		return

	if _target == null:
		return

	_emit_point_if_needed()
	_update_point_lifetimes(delta)
	_trim_old_points()
	_rebuild_line()


func clear_trail() -> void:
	_trail_points.clear()
	points = PackedVector2Array()


func restart() -> void:
	clear_trail()
	force_add_point()


func force_add_point() -> void:
	if not is_instance_valid(_target):
		_resolve_target()
		_resolve_follow_space()

	if _target == null:
		return

	_trail_points.append(
		TrailPoint.new(
			_get_target_position_in_follow_space(),
			maxf(lifetime, 0.001)
		)
	)

	_trim_old_points()
	_rebuild_line()


func _resolve_target() -> void:
	_target = null

	if not target_path.is_empty():
		var node := get_node_or_null(target_path)
		if node is Node2D:
			_target = node
			return

	var parent := get_parent()
	if parent is Node2D:
		_target = parent


func _resolve_follow_space() -> void:
	_follow_space = null

	if not follow_space_path.is_empty():
		var node := get_node_or_null(follow_space_path)
		if node is Node2D:
			_follow_space = node
			return

	if _target != null:
		var target_parent := _target.get_parent()
		if target_parent is Node2D:
			_follow_space = target_parent


func _sync_to_follow_space() -> void:
	# Line2D 的 points 是本地座標。
	# 所以這裡讓 Trail2D 自己的 transform 等於 follow_space，
	# points 就會被解讀成 follow_space 座標。
	# follow_space 移動 / 旋轉 / 縮放時，舊尾跡會一起被拖走。
	if _follow_space != null:
		global_transform = _follow_space.global_transform
	else:
		global_transform = Transform2D.IDENTITY


func _get_target_position_in_follow_space() -> Vector2:
	var target_global_position := _target.to_global(local_offset)

	if _follow_space != null:
		return _follow_space.to_local(target_global_position)

	return target_global_position


func _emit_point_if_needed() -> void:
	var current_position := _get_target_position_in_follow_space()
	var point_lifetime := maxf(lifetime, 0.001)

	if _trail_points.is_empty():
		_trail_points.append(TrailPoint.new(current_position, point_lifetime))
		return

	var last_point := _trail_points[_trail_points.size() - 1]
	var min_distance_sq := distance * distance

	if distance <= 0.0 or last_point.position.distance_squared_to(current_position) >= min_distance_sq:
		_trail_points.append(TrailPoint.new(current_position, point_lifetime))
	elif attach_head_to_target:
		last_point.position = current_position
		last_point.age = point_lifetime


func _update_point_lifetimes(delta: float) -> void:
	for i in range(_trail_points.size() - 1, -1, -1):
		var point := _trail_points[i]
		point.age -= delta

		if point.age <= 0.0:
			_trail_points.remove_at(i)


func _trim_old_points() -> void:
	var max_points = max(2, segments)

	while _trail_points.size() > max_points:
		_trail_points.remove_at(0)


func _rebuild_line() -> void:
	var line_points := PackedVector2Array()
	line_points.resize(_trail_points.size())

	for i in range(_trail_points.size()):
		line_points[i] = _trail_points[i].position

	points = line_points





"""
MIT License

Copyright (c) 2020 Oussama

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

"""
