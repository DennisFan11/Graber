class_name RayAudioPlayer
extends AudioStreamPlayer2D

static var INSTANCE_LIST: Array[RayAudioPlayer] = []

const REVERB_BUS: StringName = &"RaytracedReverb"
const LOWPASS_MIN_HZ: float = 250.0
const LOWPASS_MAX_HZ: float = 20000.0

const LOG2: float = 0.69314718056 # log(2.0)
const LOG_MIN_HZ: float = 7.96578428466 # log(LOWPASS_MIN_HZ) / log(2)
const LOG_MAX_HZ: float = 14.2877123795 # log(LOWPASS_MAX_HZ) / log(2)

var _lowpass_rays_count: int = 0
var _is_enabled: bool = false

func _ready() -> void:
	INSTANCE_LIST.append(self)
	bus = REVERB_BUS 
	
	if max_distance == 0.0:
		max_distance = 4000.0 
	

func _exit_tree() -> void:
	INSTANCE_LIST.erase(self)
	if _is_enabled and bus != REVERB_BUS:
		var idx: int = AudioServer.get_bus_index(bus)
		if idx != -1:
			AudioServer.remove_bus(idx)

func enable():
	if _is_enabled:
		return
	_is_enabled = true
	var i: int = _create_bus()
	bus = AudioServer.get_bus_name(i)

func disable():
	if not _is_enabled:
		return
	if bus == REVERB_BUS:
		_disable()
		return
	var idx: int = AudioServer.get_bus_index(bus)
	if idx != -1:
		AudioServer.remove_bus(idx)
	_disable()

func _disable():
	_is_enabled = false
	bus = REVERB_BUS
	_lowpass_rays_count = 0

func _create_bus() -> int:
	var i: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(i, StringName("RTAudioPlayer2D_" + name + "_" + str(randi() % 10000)))
	AudioServer.set_bus_send(i, REVERB_BUS)
	AudioServer.add_bus_effect(i, AudioEffectLowPassFilter.new())
	return i

func is_enabled() -> bool:
	return _is_enabled

## 與原始 3D 邏輯完全一致的更新函數
func update(listener: RayAudioListener) -> void:
	if _is_enabled:
		_update_lowpass(listener.rays_count, listener.muffle_interpolation)

	# 結算完畢，將計數器歸零以供下一幀使用
	_lowpass_rays_count = 0
	
	# Enable based on position (原始邏輯)
	var dist_sq: float = global_position.distance_squared_to(listener.global_position)
	if dist_sq > max_distance * max_distance or not playing:
		disable()
	else:
		enable()

## 與原始 3D 邏輯完全一致的 lowpass 計算
func _update_lowpass(rays_count: int, interpolation: float):
	if bus == REVERB_BUS:
		_disable()
		return

	var idx: int = AudioServer.get_bus_index(bus)
	if idx == -1:
		push_error("audio bus ", bus, " not found")
		_disable()
	else:
		#var max_hits := float(rays_count * AudioRaycaster2D.MAX_BOUNCES)
		#var ratio: float = clampf(float(_lowpass_rays_count) / max_hits, 0.0, 1.0)
		var ratio: float = clampf(float(_lowpass_rays_count) / float(rays_count), 0.0, 1.0)
		var lowpass: AudioEffectLowPassFilter = AudioServer.get_bus_effect(idx, 0)
		
		
		# 頻率在對數空間中進行平滑插值 (Lerp)
		var log_t: float = lerpf(LOG_MIN_HZ, LOG_MAX_HZ, ratio)
		var log_hz: float = log(lowpass.cutoff_hz) / LOG2 
		log_hz = lerpf(log_hz, log_t, interpolation)
		var target_hz: float = pow(2, log_hz)
		lowpass.cutoff_hz = clampf(target_hz, 10.0, 20000.0)
		
		
