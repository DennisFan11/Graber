class_name CooldownTimer
extends RefCounted

var _next_time := 0.0
var _cd_time := 0.0  ## 冷卻總長度

func get_ticks_sec() -> float:
	return Time.get_ticks_msec()/1000.0

func is_ready() -> bool:
	return get_ticks_sec() >= _next_time

func trigger(cd: float) -> void:
	_cd_time = cd
	_next_time = get_ticks_sec() + cd

## 獲取剩餘時間 單位: 秒
func get_left_time()-> float:
	return max(_next_time - get_ticks_sec(), 0.0)

## 獲取(0~1)的進度 (0 = 剛開始冷卻, 1 = 已結束)
func get_progress()-> float:
	if _cd_time <= 0.0:
		return 1.0 if is_ready() else 0.0
	var used_time = _cd_time - get_left_time()
	return clamp(used_time / _cd_time, 0.0, 1.0)
