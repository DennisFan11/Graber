class_name RayAudioListener
extends AudioListener2D

const SPEED_OF_SOUND: float =  150.0

## 音訊匯流排常數設定 (取代原本的 ProjectSettings)
const REVERB_BUS: StringName = &"RaytracedReverb"
const AMBIENT_BUS: StringName = &"RaytracedAmbient"

## bus setting
static func _static_init() -> void:
	print("[INFO] Raytraced Audio: Runtime setting up audio buses")
	
	# 1. 設定 Reverb Bus
	# 檢查是否已經存在，避免在 Runtime 重複建立（例如場景重新載入時）
	if AudioServer.get_bus_index(REVERB_BUS) == -1:
		var i: int = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(i, REVERB_BUS)
		AudioServer.set_bus_send(i, &"Master")
		
		var reverb: AudioEffectReverb = AudioEffectReverb.new()
		reverb.hipass = 1.0
		reverb.resource_name = "reverb"
		AudioServer.add_bus_effect(i, reverb)

	# 2. 設定 Ambient Bus
	if AudioServer.get_bus_index(AMBIENT_BUS) == -1:
		var i: int = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(i, AMBIENT_BUS)
		AudioServer.set_bus_send(i, &"Master")
		
		var panner: AudioEffectPanner = AudioEffectPanner.new()
		panner.resource_name = "pan"
		AudioServer.add_bus_effect(i, panner)


@export var is_enabled: bool = true:
	set(v):
		if is_enabled == v:
			return
		is_enabled = v
		if is_enabled:
			set_process(auto_update)
		else:
			set_process(false)

@export var auto_update: bool = true:
	set(v):
		auto_update = v
		set_process(auto_update and is_enabled)

@export var rays_count: int = 32:
	set(v):
		rays_count = maxi(v, 1)

@export_category("Echo (回音)")
@export var echo_enabled: bool = true
@export var echo_room_size_multiplier: float = 4.0
@export_range(0.0, 1.0, 0.01) var echo_interpolation: float = 0.01
const REVERB := 0.7 #0.7



@export_category("Ambient (環境音)")
@export var ambient_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var ambient_pan_interpolation: float = 0.02
@export_range(0.0, 1.0, 0.01) var ambient_pan_strength: float = 1.0
@export var ambient_volume_interpolation: float = 0.01
@export_range(0.0, 1.0, 0.001) var ambient_volume_attenuation: float = 0.998

@export_category("Muffle (遮擋)")
@export var muffle_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var muffle_interpolation: float = 0.01


var room_size: float = 0.0
var ambience: float = 0.0
var ambient_dir: Vector2 = Vector2.ZERO

var _reverb_effect: AudioEffectReverb
var _pan_effect: AudioEffectPanner

## 單一 Raycaster 負責所有射線的物理運算
var raycaster: AudioRaycaster2D

func _ready() -> void:
	var reverb_idx: int = AudioServer.get_bus_index(REVERB_BUS)
	if reverb_idx == -1:
		push_error("無法獲取 raytraced audio 的 reverb bus。已停用 echo 功能...")
		echo_enabled = false
	else:
		_reverb_effect = AudioServer.get_bus_effect(reverb_idx, 0)

	var ambient_idx: int = AudioServer.get_bus_index(AMBIENT_BUS)
	if ambient_idx == -1:
		push_error("無法獲取 raytraced audio 的 ambient bus。已停用 ambient 功能...")
		ambient_enabled = false
	else:
		_pan_effect = AudioServer.get_bus_effect(ambient_idx, 0)

	# 初始化並掛載 AudioRaycaster2D
	raycaster = AudioRaycaster2D.new()
	# 若你的 AudioRaycaster2D 內的 listener 類型限制為 RayAudioListener，
	# 這裡請確保該變數能接受 RayAudioListener，或是繼承自相同的基礎類別
	raycaster.listener = self 
	add_child(raycaster, INTERNAL_MODE_BACK)

	set_process(auto_update and is_enabled)
	if is_enabled:
		make_current()

func _process(_delta: float) -> void:
	update()

func update():
	if !is_enabled or not is_inside_tree():
		return

	# 每幀更新物理空間狀態
	raycaster.space = get_world_2d().direct_space_state

	var echo: float = 0.0 
	var echo_count: int = 0 
	var bounces_this_tick: int = 0
	var escaped_count: int = 0
	var escaped_dir: Vector2 = Vector2.ZERO
	var escaped_strength: float = 0.0

	# 均勻發射射線並收集數據
	for i in rays_count:
		var angle = (TAU / rays_count) * i
		var result: AudioRaycaster2D.SoundRaycastResult = raycaster.main_raycast(global_position, angle)

		echo += result.echo_dist
		echo_count += result.echo_count
		bounces_this_tick += result.bounce_count

		if result.escaped:
			escaped_count += 1
			# 避免除以 0 的保護機制
			var safe_bounce = maxi(result.bounce_count, 1)
			escaped_strength += 1.0 / float(safe_bounce)
			escaped_dir += result.escape_dir
	
	echo = 0.0 if echo_count == 0 else (echo / float(echo_count))
	escaped_dir = Vector2.ZERO if escaped_count == 0 else (escaped_dir / float(escaped_count))

	# ✨ 確保先計算 Ambient，才能拿到最新的 ambience 值給 Echo 判斷
	if ambient_enabled:
		_update_ambient(escaped_strength, escaped_dir)
	if echo_enabled:
		_update_echo(echo, echo_count, bounces_this_tick)
		
	# 通知所有 Player 進行遮擋結算並重置計數器
	for player in RayAudioPlayer.INSTANCE_LIST:
		player.update(self)


func _update_echo(echo: float, echo_count: int, bounces: int) -> void:
	room_size = lerpf(room_size, echo, echo_interpolation)
	
	# 稍微調降 multiplier，或者加入保護機制避免 e 破表
	var e: float = (room_size * echo_room_size_multiplier) / SPEED_OF_SOUND
	
	if _reverb_effect:
		_reverb_effect.room_size = lerpf(_reverb_effect.room_size, clampf(e, 0.0, 1.0), echo_interpolation)
		_reverb_effect.predelay_msec = lerpf(_reverb_effect.predelay_msec, e * 1000, echo_interpolation)
		
		# 將最大 feedback 限制在 0.6，防止聲音無限迴圈
		_reverb_effect.predelay_feedback = lerpf(_reverb_effect.predelay_feedback, clampf(e, 0.0, 0.6), echo_interpolation)
		
		var return_ratio: float = 0.0 if bounces == 0 else float(echo_count) / float(bounces)
		_reverb_effect.hipass = lerpf(_reverb_effect.hipass, 1.0 - return_ratio, echo_interpolation)
		
		# ✨【修正核心】根據室外程度 (ambience) 動態關閉回音的混響比例 (wet)
		# 預設 wet 是 0.5。當完全走到戶外 (ambience = 1.0) 時，wet 就會被壓到 0.0 徹底消音。
		var target_wet: float = REVERB * (1.0 - ambience)
		_reverb_effect.wet = lerpf(_reverb_effect.wet, target_wet, echo_interpolation)

func _update_ambient(escaped_strength: float, escaped_dir: Vector2) -> void:
	var ambience_ratio: float = float(escaped_strength) / float(rays_count)

	if escaped_strength > 0:
		ambience = lerpf(ambience, 1.0, ambience_ratio)
	else:
		ambience *= ambient_volume_attenuation
		
	var ambient_bus_idx: int = AudioServer.get_bus_index(AMBIENT_BUS)
	if ambient_bus_idx != -1:
		var volume: float = AudioServer.get_bus_volume_linear(ambient_bus_idx)
		AudioServer.set_bus_volume_linear(ambient_bus_idx, lerpf(volume, ambience, ambient_volume_interpolation))
	
	ambient_dir = ambient_dir.lerp(escaped_dir, ambient_pan_interpolation)
	var target_pan: float = 0.0 if ambient_dir.is_zero_approx() else global_transform.x.dot(ambient_dir.normalized())
	if _pan_effect:
		_pan_effect.pan = target_pan * ambient_pan_strength
