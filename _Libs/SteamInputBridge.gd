extends Node

## 把 Steam Input API 的動作轉成 Godot Input Map 的 action。
## 遊戲其他地方照常用 Input.get_vector / is_action_pressed，不需要知道 Steam 的存在。
## 動作定義在 res://steam_input/game_actions.vdf。

const MANIFEST_DIR := "res://steam_input/"
const MANIFEST_FILES: Array[String] = ["game_actions.vdf", "controller_xboxone.vdf"]
const ACTION_SET := "InGameControls"

## Steam 動作名稱 -> Godot Input Map action (左, 右, 上, 下)
const STICK_ACTIONS := {
	"L_HAND": [&"L_HAND_LEFT", &"L_HAND_RIGHT", &"L_HAND_UP", &"L_HAND_DOWN"],
	"R_HAND": [&"R_HAND_LEFT", &"R_HAND_RIGHT", &"R_HAND_UP", &"R_HAND_DOWN"],
}
const TRIGGER_ACTIONS: Array[StringName] = [&"L_GRAB", &"R_GRAB"]

var _action_set_handle: int = 0
var _analog_handles: Dictionary = {}
var _last_strength: Dictionary = {}
var _vibration_time_left: float = 0.0
## getConnectedControllers 每次呼叫都會印 log，所以快取起來每秒更新一次。
var _controllers: Array = []
var _controller_refresh_left: float = 0.0


func _ready() -> void:
	if not Steam.inputInit(false):
		push_warning("[SteamInputBridge] Steam Input 初始化失敗")
		return
	var manifest_path := _export_manifest()
	if not Steam.setInputActionManifestFilePath(manifest_path):
		push_warning("[SteamInputBridge] 無法載入動作清單: %s" % manifest_path)
	print("[SteamInputBridge] manifest: ", manifest_path)


func _process(delta: float) -> void:
	_update_vibration(delta)

	if not _resolve_handles():
		return

	_controller_refresh_left -= delta
	if _controller_refresh_left <= 0.0:
		_controller_refresh_left = 1.0
		_controllers = Steam.getConnectedControllers()

	var strengths: Dictionary = {}
	for input_handle: int in _controllers:
		Steam.activateActionSet(input_handle, _action_set_handle)
		_read_controller(input_handle, strengths)

	for action: StringName in strengths:
		_set_action(action, strengths[action])


## 左右手的震動，weak = 左馬達、strong = 右馬達，0~1。
func vibrate(weak: float, strong: float, duration: float) -> void:
	var left := int(clampf(weak, 0.0, 1.0) * 65535.0)
	var right := int(clampf(strong, 0.0, 1.0) * 65535.0)
	for input_handle: int in _controllers:
		Steam.triggerVibration(input_handle, left, right)
	_vibration_time_left = duration


func _update_vibration(delta: float) -> void:
	if _vibration_time_left <= 0.0:
		return
	_vibration_time_left -= delta
	if _vibration_time_left <= 0.0:
		for input_handle: int in _controllers:
			Steam.triggerVibration(input_handle, 0, 0)


func _read_controller(input_handle: int, strengths: Dictionary) -> void:
	for steam_name: String in STICK_ACTIONS:
		var data: Dictionary = Steam.getAnalogActionData(input_handle, _analog_handles[steam_name])
		var x: float = data.get("x", 0.0)
		var y: float = data.get("y", 0.0)  # Steam: 上為正
		var targets: Array = STICK_ACTIONS[steam_name]
		_merge(strengths, targets[0], maxf(-x, 0.0))
		_merge(strengths, targets[1], maxf(x, 0.0))
		_merge(strengths, targets[2], maxf(y, 0.0))
		_merge(strengths, targets[3], maxf(-y, 0.0))

	for action: StringName in TRIGGER_ACTIONS:
		var data: Dictionary = Steam.getAnalogActionData(input_handle, _analog_handles[String(action)])
		_merge(strengths, action, data.get("x", 0.0))


func _merge(strengths: Dictionary, action: StringName, value: float) -> void:
	strengths[action] = maxf(strengths.get(action, 0.0), value)


## 只在數值改變時才呼叫 press/release，避免蓋掉其他手把（例如 Xbox）的輸入。
func _set_action(action: StringName, strength: float) -> void:
	if strength < 0.01:
		strength = 0.0
	if is_equal_approx(_last_strength.get(action, 0.0), strength):
		return
	_last_strength[action] = strength
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


## Steam 載入動作清單是非同步的，handle 可能要等幾個 frame 才拿得到。
func _resolve_handles() -> bool:
	if _action_set_handle != 0:
		return true
	_action_set_handle = Steam.getActionSetHandle(ACTION_SET)
	if _action_set_handle == 0:
		return false
	for steam_name: String in STICK_ACTIONS:
		_analog_handles[steam_name] = Steam.getAnalogActionHandle(steam_name)
	for action: StringName in TRIGGER_ACTIONS:
		_analog_handles[String(action)] = Steam.getAnalogActionHandle(String(action))
	print("[SteamInputBridge] handles: set=", _action_set_handle, " analog=", _analog_handles)
	return true


## Steam 需要實體檔案路徑；匯出後 res:// 在 .pck 裡，所以複製到 user://。
func _export_manifest() -> String:
	var out_dir := "user://steam_input/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	for file_name: String in MANIFEST_FILES:
		var src := FileAccess.open(MANIFEST_DIR + file_name, FileAccess.READ)
		var dst := FileAccess.open(out_dir + file_name, FileAccess.WRITE)
		dst.store_buffer(src.get_buffer(src.get_length()))
	return ProjectSettings.globalize_path(out_dir + MANIFEST_FILES[0])
