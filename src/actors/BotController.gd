class_name BotController
extends CombatantBase

const BOT_NAMES_CT: Array[String] = ["Cliffe", "Minh", "Gooseman", "Reed", "Fergus", "Orin", "Zim", "Rock", "Valdez", "Vitaliy"]
const BOT_NAMES_T: Array[String] = ["Kahn", "Ringo", "Gabe", "Yahn", "Phoenix", "Cobra", "Viper", "Scorpion", "Wraith", "nomad"]

var bot_index: int = 0
var _path: PackedVector3Array = PackedVector3Array()
var _path_idx: int = 0
var _repath_timer: float = 0.0
var _goal_pos := Vector3.ZERO
var _target_enemy: CombatantBase = null
var _reaction_timer: float = 0.0
var _burst_hold_timer: float = 0.0
var _burst_pause_timer: float = 0.0
var _stuck_timer: float = 0.0
var _strafe_dir: float = 0.0
var _strafe_timer: float = 0.0
var _respawn_timer: float = 0.0
var _assigned_site: int = 0
var _did_buy_this_round: bool = false
var _thrown_nade_this_round: bool = false


func setup_bot(idx: int, p_team: String, world: Dust2World) -> void:
	bot_index = idx
	team = p_team
	is_local_player = false
	world_ref = world
	var names: Array[String] = BOT_NAMES_CT if team == "ct" else BOT_NAMES_T
	display_name = "BOT %s" % names[idx % names.size()]
	_assigned_site = idx % 2


func reset_for_round(spawn_pos: Vector3, spawn_yaw: float, give_c4: bool) -> void:
	super.reset_for_round(spawn_pos, spawn_yaw, give_c4)
	_path = PackedVector3Array()
	_path_idx = 0
	_repath_timer = randf_range(0.1, 0.5)
	_target_enemy = null
	_reaction_timer = _base_reaction_time()
	_burst_hold_timer = 0.0
	_burst_pause_timer = 0.0
	_stuck_timer = 0.0
	_did_buy_this_round = false
	_thrown_nade_this_round = false
	_assigned_site = (bot_index + MatchManager.round_number) % 2
	_choose_route_goal()


func _base_reaction_time() -> float:
	match SettingsManager.bot_difficulty:
		0:
			return 0.58
		1:
			return 0.38
		2:
			return 0.22
		_:
			return 0.13


func _aim_jitter_rad() -> float:
	match SettingsManager.bot_difficulty:
		0:
			return 0.075
		1:
			return 0.042
		2:
			return 0.022
		_:
			return 0.011


func _process(delta: float) -> void:
	if not alive:
		if MatchManager.mode == "deathmatch":
			_respawn_timer += delta
			if _respawn_timer >= 2.2:
				_respawn_timer = 0.0
				var sp: Vector3 = GameData.nav.get_spawn_position(team, randi())
				var sy: float = GameData.nav.get_spawn_yaw(team, randi())
				reset_for_round(sp, sy, false)
				_perform_smart_buy()
		return

	if MatchManager.is_frozen() and not _did_buy_this_round:
		_did_buy_this_round = true
		_perform_smart_buy()

	_think_tactics(delta)


func _perform_smart_buy() -> void:
	if MatchManager.mode == "deathmatch":
		var dm_pool: Array[int] = [0, 9, 1, 3, 11, 20, 30]
		try_buy_weapon(dm_pool[randi() % dm_pool.size()])
		return

	if armor < 100.0 or not has_helmet:
		try_buy_equipment("helmet")
	if team == "ct" and not has_defuse_kit and randf() < 0.65:
		try_buy_equipment("kit")

	if primary_id < 0:
		if money >= 4750 and (bot_index % 4 == 0):
			try_buy_weapon(3) # AWP
		elif money >= 3100:
			try_buy_weapon(0 if team == "t" else (9 if randf() < 0.6 else 1))
		elif money >= 2150:
			try_buy_weapon(20 if team == "t" else 19) # Galil / FAMAS
		elif money >= 1350:
			try_buy_weapon(26 if team == "t" else 11) # MAC-10 / MP9

	if secondary_id == (2 if team == "ct" else 7) and money >= 1200 and primary_id >= 0:
		try_buy_weapon(8 if randf() < 0.45 else 13)

	if money >= 600:
		try_buy_grenade("smoke")
	if money >= 400:
		try_buy_grenade("he")
	if money >= 250:
		try_buy_grenade("flash")


func _think_tactics(delta: float) -> void:
	input_forward = 0.0
	input_right = 0.0
	input_jump = false
	input_walk = false
	input_crouch = false
	input_fire_held = false
	input_fire_just = false
	input_alt_just = false
	input_reload_just = false
	input_use_held = false

	if MatchManager.is_frozen():
		return

	# Recarga automática si el cargador está vacío
	var ammo_info: Vector2i = get_active_ammo()
	if (active_slot == 1 or active_slot == 2) and ammo_info.x == 0 and ammo_info.y > 0:
		input_reload_just = true

	# Buscar enemigo visible
	_target_enemy = _acquire_visible_enemy()
	if _target_enemy != null:
		_fight_enemy(delta)
		return

	_reaction_timer = _base_reaction_time()
	if active_slot == 3 and (primary_id >= 0 or secondary_id >= 0):
		switch_slot(1 if primary_id >= 0 else 2)

	# Objetivos de C4
	if team == "t" and has_c4 and not MatchManager.bomb_planted:
		var site_here: int = GameData.triggers.bomb_site_at(global_position, MovementMath.HULL_RADIUS, 1.8)
		if site_here >= 0:
			if active_slot != 5:
				switch_slot(5)
			input_fire_held = true
			input_use_held = true
			return

	if team == "ct" and MatchManager.bomb_planted:
		var dist_bomb: float = global_position.distance_to(MatchManager.bomb_position)
		if dist_bomb <= 2.1:
			_look_toward(MatchManager.bomb_position + Vector3(0, 0.2, 0), delta, 8.0)
			input_use_held = true
			return

	_repath_timer -= delta
	if _repath_timer <= 0.0 or _path_idx >= _path.size():
		_repath_timer = randf_range(1.4, 2.5)
		_choose_route_goal()
		_path = GameData.nav.find_path(global_position, _goal_pos)
		_path_idx = 0

	_follow_nav_path(delta)


func _choose_route_goal() -> void:
	if MatchManager.mode == "deathmatch":
		var areas: Array = GameData.nav.areas
		if not areas.is_empty():
			_goal_pos = GameData.nav.area_center(randi() % areas.size())
		return

	if team == "t":
		if MatchManager.bomb_planted:
			_goal_pos = MatchManager.bomb_position + Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0))
			return
		var site_pos: Vector3 = GameData.nav.get_site_position(_assigned_site)
		_goal_pos = site_pos + Vector3(randf_range(-2.2, 2.2), 0.0, randf_range(-2.2, 2.2))
	else:
		if MatchManager.bomb_planted:
			_goal_pos = MatchManager.bomb_position
			return
		var hold_places: Array[String] = ["Bombsite A", "Long A", "Mid", "Bombsite B"]
		var chosen_place: String = hold_places[bot_index % hold_places.size()]
		var area_list: Array = GameData.nav.get_areas_in_place(chosen_place)
		if not area_list.is_empty():
			var idx: int = int(area_list[randi() % area_list.size()])
			_goal_pos = GameData.nav.area_center(idx)
		else:
			_goal_pos = GameData.nav.get_site_position(_assigned_site)


func _follow_nav_path(delta: float) -> void:
	if _path.is_empty():
		return
	while _path_idx < _path.size():
		var wp: Vector3 = _path[_path_idx]
		var horiz := Vector2(wp.x - global_position.x, wp.z - global_position.z)
		if horiz.length() < 1.15 and absf(wp.y - global_position.y) < 2.2:
			_path_idx += 1
		else:
			break
	if _path_idx >= _path.size():
		return

	var target: Vector3 = _path[_path_idx]
	_look_toward(target + Vector3(0.0, 1.4, 0.0), delta, 6.5)
	input_forward = 1.0

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.5, 1.2)
		_strafe_dir = 0.0

	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	if h_speed < 0.45:
		_stuck_timer += delta
		if _stuck_timer > 0.55:
			input_jump = true
			input_right = -1.0 if randf() < 0.5 else 1.0
			if _stuck_timer > 1.4:
				_stuck_timer = 0.0
				_repath_timer = 0.0
	else:
		_stuck_timer = 0.0


func _acquire_visible_enemy() -> CombatantBase:
	if flash_amount > 1.3:
		return null
	var eye: Vector3 = get_eye_position()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var best: CombatantBase = null
	var best_dist: float = 75.0
	for c in MatchManager.combatants:
		if c == null or not is_instance_valid(c) or not c.alive or c.team == team:
			continue
		var enemy_eye: Vector3 = c.get_eye_position()
		var d: float = eye.distance_to(enemy_eye)
		if d > best_dist:
			continue
		if world_ref != null and world_ref.is_line_blocked_by_smoke(eye, enemy_eye):
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, enemy_eye, 4)
		if space.intersect_ray(q).is_empty():
			best_dist = d
			best = c as CombatantBase
	return best


func _fight_enemy(delta: float) -> void:
	if active_slot > 2 or (active_slot == 1 and primary_ammo <= 0 and secondary_id >= 0 and secondary_ammo > 0):
		if primary_id >= 0 and primary_ammo > 0:
			switch_slot(1)
		elif secondary_id >= 0:
			switch_slot(2)

	var aim_target: Vector3 = _target_enemy.global_position + Vector3(0.0, 1.32, 0.0)
	if SettingsManager.bot_difficulty >= 2:
		aim_target = _target_enemy.global_position + Vector3(0.0, 1.54, 0.0)
	var jitter: float = _aim_jitter_rad()
	aim_target += Vector3(randf_range(-jitter, jitter), randf_range(-jitter, jitter), randf_range(-jitter, jitter)) * 2.5
	_look_toward(aim_target, delta, 12.0 if SettingsManager.bot_difficulty >= 2 else 7.5)

	# Lanzar granada HE ocasional si está a distancia media
	var dist: float = global_position.distance_to(_target_enemy.global_position)
	if not _thrown_nade_this_round and dist > 11.0 and dist < 24.0 and int(grenades.get("he", 0)) > 0 and randf() < 0.015:
		_thrown_nade_this_round = true
		active_grenade = "he"
		grenades["he"] = int(grenades["he"]) - 1
		var params: Dictionary = GrenadeMath.launch_params(
			GameData.utility_data, "he", 1.0, get_eye_position(), get_look_direction(), velocity
		)
		if world_ref != null:
			world_ref.spawn_grenade_projectile("he", params["position"], params["velocity"], self)
		return

	# Acompañar con strafe o crouch
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.35, 0.9)
		_strafe_dir = [-1.0, 0.0, 1.0][randi() % 3]
	input_right = _strafe_dir
	input_crouch = dist < 14.0 and SettingsManager.bot_difficulty >= 1 and randf() < 0.25

	if _reaction_timer > 0.0:
		_reaction_timer -= delta
		return

	var wid: int = get_active_weapon_id()
	var w: Dictionary = GameData.get_weapon(wid)
	var is_auto: bool = bool(w.get("fullAuto", false))
	if _burst_pause_timer > 0.0:
		_burst_pause_timer -= delta
		return

	if is_auto:
		_burst_hold_timer += delta
		input_fire_held = true
		if _burst_hold_timer > 0.42:
			_burst_hold_timer = 0.0
			_burst_pause_timer = randf_range(0.14, 0.30)
	else:
		input_fire_just = fire_cooldown <= 0.0


func _look_toward(target: Vector3, delta: float, turn_speed: float) -> void:
	var eye: Vector3 = get_eye_position()
	var dir: Vector3 = (target - eye)
	var horiz_len: float = Vector2(dir.x, dir.z).length()
	if horiz_len < 1e-4:
		return
	var desired_yaw: float = atan2(-dir.x, -dir.z)
	var desired_pitch: float = atan2(dir.y, horiz_len)
	yaw = lerp_angle(yaw, desired_yaw, clampf(delta * turn_speed, 0.0, 1.0))
	pitch = lerpf(pitch, clampf(desired_pitch, -1.4, 1.4), clampf(delta * turn_speed, 0.0, 1.0))
