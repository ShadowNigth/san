extends Node

const MAX_2D_PLAYERS: int = 16
const MAX_3D_PLAYERS: int = 32

var _stream_cache: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer = null
var _idx_2d: int = 0
var _idx_3d: int = 0


func _ready() -> void:
	_ensure_bus("SFX")
	_ensure_bus("Music")
	SettingsManager.apply_audio_volumes()

	for i in range(MAX_2D_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players_2d.append(p)

	for i in range(MAX_3D_PLAYERS):
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 6.0
		p3.max_distance = 48.0
		add_child(p3)
		_players_3d.append(p3)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var idx: int = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func load_clip(clip_name: String) -> AudioStream:
	if clip_name.is_empty():
		return null
	if _stream_cache.has(clip_name):
		return _stream_cache[clip_name]
	var candidates: Array[String] = [
		"res://assets/audio/%s.ogg" % clip_name,
		"res://assets/audio/source/%s.ogg" % clip_name,
	]
	for path in candidates:
		if ResourceLoader.exists(path):
			var res: Resource = ResourceLoader.load(path)
			if res is AudioStream:
				_stream_cache[clip_name] = res
				return res
		if FileAccess.file_exists(path):
			var stream := AudioStreamOggVorbis.load_from_file(path)
			if stream != null:
				_stream_cache[clip_name] = stream
				return stream
	return null


func play_ui(clip_name: String, volume_db: float = -4.0) -> void:
	play_2d(clip_name, volume_db, 1.0)


func play_2d(clip_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = load_clip(clip_name)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players_2d[_idx_2d]
	_idx_2d = (_idx_2d + 1) % MAX_2D_PLAYERS
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_3d(
	clip_name: String,
	world_pos: Vector3,
	max_dist: float = 40.0,
	volume_db: float = 0.0,
	pitch: float = 1.0
) -> void:
	var stream: AudioStream = load_clip(clip_name)
	if stream == null:
		return
	var p: AudioStreamPlayer3D = _players_3d[_idx_3d]
	_idx_3d = (_idx_3d + 1) % MAX_3D_PLAYERS
	p.stream = stream
	p.global_position = world_pos
	p.max_distance = maxf(2.0, max_dist)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_music(clip_name: String, volume_db: float = -6.0) -> void:
	var stream: AudioStream = load_clip(clip_name)
	if stream == null:
		return
	_music_player.stream = stream
	_music_player.volume_db = volume_db
	_music_player.play()


func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()


func play_weapon_shot(
	weapon_id: int, world_pos: Vector3, suppressed: bool, is_local: bool
) -> void:
	var kit: Dictionary = GameData.get_audio_kit(weapon_id)
	if kit.is_empty():
		return
	var clip: String = str(kit.get("shot", ""))
	if not suppressed and kit.has("shotUnsuppressed"):
		clip = str(kit.get("shotUnsuppressed", clip))
	var pitch: float = randf_range(0.97, 1.03)
	if is_local:
		play_2d(clip, -2.0 if suppressed else 0.0, pitch)
	else:
		var max_r: float = float(
			GameData.sound_ranges.get("suppressed" if suppressed else "fire", 48.0)
		)
		play_3d(clip, world_pos, max_r, -3.0 if suppressed else 1.5, pitch)


func play_weapon_action(weapon_id: int, role: String, world_pos: Vector3, is_local: bool) -> void:
	if EconomySystem.is_knife(weapon_id):
		if role == "draw":
			play_local_or_3d("knife-deploy", world_pos, 16.0, is_local)
		return
	var kit: Dictionary = GameData.get_audio_kit(weapon_id)
	var clip: String = str(kit.get(role, ""))
	if clip.is_empty():
		return
	var max_r: float = float(GameData.sound_ranges.get("reload", 16.0))
	play_local_or_3d(clip, world_pos, max_r, is_local, -2.0)


func play_footstep(world_pos: Vector3, is_sand: bool, is_local: bool) -> void:
	var idx: int = randi_range(1, 4)
	var clip: String = ("step-sand-%d" if is_sand else "step-concrete-%d") % idx
	var max_r: float = float(GameData.sound_ranges.get("step", 22.0))
	play_local_or_3d(clip, world_pos, max_r, is_local, -7.0 if is_local else -3.0, randf_range(0.94, 1.06))


func play_local_or_3d(
	clip_name: String,
	world_pos: Vector3,
	max_dist: float,
	is_local: bool,
	volume_db: float = 0.0,
	pitch: float = 1.0
) -> void:
	if is_local:
		play_2d(clip_name, volume_db, pitch)
	else:
		play_3d(clip_name, world_pos, max_dist, volume_db, pitch)
