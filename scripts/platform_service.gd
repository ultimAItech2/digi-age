class_name DAPlatformService
extends RefCounted
## Steam is optional at runtime. This fallback keeps the game fully offline.
signal ready_changed(available: bool)
signal achievement_requested(achievement_id: String)
var available: bool = false
var user_id: String = "local"
var achievements: Dictionary = {}

func initialize() -> void:
	# GodotSteam can be enabled later without changing gameplay callers.
	available = Engine.has_singleton("Steam") and OS.has_feature("steam")
	if available:
		var steam = Engine.get_singleton("Steam")
		user_id = str(steam.call("getSteamID"))
	ready_changed.emit(available)

func unlock(achievement_id: String) -> void:
	achievements[achievement_id] = true
	if available:
		var steam = Engine.get_singleton("Steam")
		steam.call("setAchievement", achievement_id)
		steam.call("storeStats")
	achievement_requested.emit(achievement_id)

func cloud_save_directory() -> String:
	return "user://saves"
