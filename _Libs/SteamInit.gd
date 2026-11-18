extends Node

## 初始化 Steamworks，讓 Steam 把這個程序視為遊戲，
## Steam Controller / Steam Input 才會從 Desktop Configuration 切換成遊戲手把設定。
## 480 = Valve 測試用 App ID (Spacewar)，上架後改成正式 App ID。
const STEAM_APP_ID: int = 480


func _ready() -> void:
	var result: Dictionary = Steam.steamInitEx(STEAM_APP_ID, true)
	print("[SteamInit] ", result)
