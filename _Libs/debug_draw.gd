class_name DebugDraw
extends Node2D



const DEBUG = true

func _ready() -> void:
	DI.register("_debug_draw", self)




func d_draw_line(from:Vector2, to:Vector2, color:Color=Color.WHITE, width:float=1.0, time:float=0.1):
	_add_draw(func():
		self.draw_line(from, to, color * Color(1,1,1,0.03), width),
		time
	)

func d_draw_sector(center: Vector2, radius: float, angle_from: float, angle_to: float, color: Color=Color.WHITE, time: float=0.1, sides: int = 24):
	_add_draw(func():
		_draw_sector_internal(
			center,
			radius,
			angle_from,
			angle_to, 
			color, 
			sides
			),
		time
	)

## [新增] 繪製圓形 (半透明填充 + 外框)
func d_draw_circle(center: Vector2, radius: float, color: Color = Color.WHITE, time: float = 0.1, width: float = 2, filled:bool=false):
	if not filled:
		_add_draw(func():
			self.draw_circle(
				center,
				radius,
				color,
				filled,
				width,
			),
			time
		)
		return 
	_add_draw(func():
		self.draw_circle(
			center,
			radius,
			color,
			filled
		),
		time
	)

## 繪製圓形邊匡
func d_draw_circle_edge(center: Vector2, radius: float, color: Color, width: float, time:float=0.01):
	_add_draw(func():
		self.draw_arc(
			center, radius, 0, TAU, 32, color, width, true
	),time)
	# 使用 draw_arc 繪製 0 到 360 度 (TAU) 的弧線
	# 參數：圓心, 半徑, 起始角, 結束角, 解析度(點數), 顏色, 線寬, 抗鋸齒
	
	





func _draw_sector_internal(center: Vector2, radius: float, angle_from: float, angle_to: float, color: Color, sides: int):
	var points: Array[Vector2] = []
	points.append(center)

	var step = (angle_to - angle_from) / sides
	for i in range(sides + 1):
		var rad = (angle_from + step * i)
		points.append(center + Vector2(cos(rad), sin(rad)) * radius)

	# 建立透明填色
	var fill_color := Color(color.r, color.g, color.b, color.a * 0.2)

	# 填充扇形
	self.draw_colored_polygon(points, fill_color)

	# 外圈弧線
	self.draw_arc(center, radius, (angle_from), (angle_to), sides, color, 3.0)




## add_draw 用於暫時註冊一個繪製指令（Callable），可在指定時間內於 _draw() 階段持續顯示除錯圖形並自動移除。
func _add_draw(callable: Callable, time: float=1.0):
	_draw_id += 1
	_draw_map[_draw_id] = callable
	
	## 時間到後自動釋放
	var timer := get_tree().create_timer(time)
	timer.timeout.connect(
		_free_draw.bind(_draw_id)
	)










signal draw_finish


## NOTE 內部邏輯

func _free_draw(draw_id: int):
	await draw_finish
	_draw_map.erase(draw_id)

func _process(delta: float) -> void:
	queue_redraw()

var _draw_id:int = 0
var _draw_map: Dictionary[int, Callable] = {}
func _draw() -> void:
	if not DEBUG: 
		draw_finish.emit()
		return
	#print("Debug draw start")
	for i: Callable in _draw_map.values():
		i.call()
	draw_finish.emit()
		#print("Draw")
