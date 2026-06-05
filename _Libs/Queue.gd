class_name Queue
extends RefCounted

var _data: Array = []
var _front: int = 0

func push(item: Variant) -> void:
	_data.append(item)

func pop() -> Variant:
	if _front >= _data.size():
		return null
	var item = _data[_front]
	_front += 1
	return item

func is_empty() -> bool:
	return _front >= _data.size()

func size() -> int:
	return _data.size() - _front

func clear() -> void:
	_data.clear()
	_front = 0
