extends Node

signal settings_changed

const SETTINGS_PATH: String = "user://cs2go_settings.cfg"

var sensitivity: float = 1.6
var zoom_sensitivity: float = 1.0
var fov: float = 90.0
var viewmodel_fov: float = 60.0
var viewmodel_offset := Vector3(1.0, 1.0, -1.0)

var crosshair_dynamic: bool = true
var crosshair_color := Color(0.22, 1.0, 0.35, 0.95)
var crosshair_size: float = 5.0
var crosshair_gap: float = 3.0
var crosshair_thickness: float = 1.6
var crosshair_dot: bool = false

var master_volume: float = 0.85
var sfx_volume: float = 0.90
var music_volume: float = 0.45

var bot_difficulty: int = 1
var team_size_override: int = 5
var chosen_mode: String = "competitive"
var chosen_team: String = "ct"
var show_fps: bool = true


func _ready() -> void:
	load_settings()
	apply_audio_volumes()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	sensitivity = float(cfg.get_value("controls", "sensitivity", sensitivity))
	zoom_sensitivity = float(cfg.get_value("controls", "zoom_sensitivity", zoom_sensitivity))
	fov = float(cfg.get_value("video", "fov", fov))
	viewmodel_fov = float(cfg.get_value("video", "viewmodel_fov", viewmodel_fov))
	crosshair_dynamic = bool(cfg.get_value("crosshair", "dynamic", crosshair_dynamic))
	crosshair_color = cfg.get_value("crosshair", "color", crosshair_color)
	crosshair_size = float(cfg.get_value("crosshair", "size", crosshair_size))
	crosshair_gap = float(cfg.get_value("crosshair", "gap", crosshair_gap))
	crosshair_thickness = float(cfg.get_value("crosshair", "thickness", crosshair_thickness))
	crosshair_dot = bool(cfg.get_value("crosshair", "dot", crosshair_dot))
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	bot_difficulty = int(cfg.get_value("game", "bot_difficulty", bot_difficulty))
	team_size_override = int(cfg.get_value("game", "team_size", team_size_override))
	chosen_mode = str(cfg.get_value("game", "mode", chosen_mode))
	chosen_team = str(cfg.get_value("game", "team", chosen_team))
	show_fps = bool(cfg.get_value("video", "show_fps", show_fps))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "sensitivity", sensitivity)
	cfg.set_value("controls", "zoom_sensitivity", zoom_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "viewmodel_fov", viewmodel_fov)
	cfg.set_value("crosshair", "dynamic", crosshair_dynamic)
	cfg.set_value("crosshair", "color", crosshair_color)
	cfg.set_value("crosshair", "size", crosshair_size)
	cfg.set_value("crosshair", "gap", crosshair_gap)
	cfg.set_value("crosshair", "thickness", crosshair_thickness)
	cfg.set_value("crosshair", "dot", crosshair_dot)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("game", "bot_difficulty", bot_difficulty)
	cfg.set_value("game", "team_size", team_size_override)
	cfg.set_value("game", "mode", chosen_mode)
	cfg.set_value("game", "team", chosen_team)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.save(SETTINGS_PATH)
	apply_audio_volumes()
	settings_changed.emit()


func apply_audio_volumes() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(0.0001, master_volume)))
	var sfx_idx: int = AudioServer.get_bus_index("SFX")
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(0.0001, sfx_volume)))
	var music_idx: int = AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(maxf(0.0001, music_volume)))
