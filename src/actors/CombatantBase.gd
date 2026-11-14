class_name CombatantBase
extends CharacterBody3D

signal health_changed(hp: float, armor: float)
signal weapon_changed(weapon_id: int, slot: int)
signal fired_shot(weapon_id: int)
signal damaged_enemy(amount: float, headshot: bool, killed: bool)
signal hit_taken(from_pos: Vector3, amount: float)

const HITBOX_SPEC: Array[Dictionary] = [
	{"region": "head", "y": 1.60, "crouch_y": 1.15, "radius": 0.135, "height": 0.28},
	{"region": "chest", "y": 1.24, "crouch_y": 0.88, "radius": 0.21, "height": 0.42},
	{"region": "stomach", "y": 0.94, "crouch_y": 0.66, "radius": 0.19, "height": 0.34},
	{"region": "arm", "y": 1.22, "crouch_y": 0.86, "radius": 0.32, "height": 0.32},
	{"region": "leg", "y": 0.45, "crouch_y": 0.32, "radius": 0.20, "height": 0.78},
]

var display_name: String = "Player"
var team: String = "ct"
var is_local_player: bool = false
var world_ref: Dust2World = null

var alive: bool = true
var health: float = 100.0
var armor: float = 0.0
var has_helmet: bool = false
var has_defuse_kit: bool = false
var has_healthshot: bool = false
var has_c4: bool = false

var money: int = 800
var kills: int = 0
var deaths: int = 0
var assists: int = 0
var score: int = 0
var dm_streak: int = 0
var spawn_protection: float = 0.0
var flash_amount: float = 0.0

var yaw: float = 0.0
var pitch: float = 0.0
var eye_height: float = MovementMath.STANDING_EYE
var grounded: bool = false
var _was_grounded: bool = false
var _last_vertical: float = 0.0

var aim_punch := RecoilSystem.AimPunch.new()

# Loadout & weapon state
var primary_id: int = -1
var primary_ammo: int = 0
var primary_reserve: int = 0
var primary_recoil := RecoilSystem.WeaponRecoilState.new()
var primary_accuracy := AccuracySystem.WeaponAccuracyState.new()

var secondary_id: int = 2
var secondary_ammo: int = 12
var secondary_reserve: int = 24
var secondary_recoil := RecoilSystem.WeaponRecoilState.new()
var secondary_accuracy := AccuracySystem.WeaponAccuracyState.new()

var knife_id: int = 4
var grenades: Dictionary = {"he": 0, "flash": 0, "smoke": 0, "molotov": 0, "incendiary": 0, "decoy": 0}
var active_grenade: String = ""

var active_slot: int = 2
var previous_slot: int = 3
var silencer_on: bool = true
var burst_enabled: bool = false
var zoom_level: int = 0

var fire_cooldown: float = 0.0
var deploy_cooldown: float = 0.0
var reload_timer: float = 0.0
var is_reloading: bool = false
var _burst_remaining: int = 0
var _burst_timer: float = 0.0

var plant_progress: float = 0.0
var is_planting: bool = false
var defuse_progress: float = 0.0
var is_defusing: bool = false

var _step_dist: float = 0.0
var _body_col: CollisionShape3D = null
var _capsule_shape: CapsuleShape3D = null
var _hitbox_areas: Array[Dictionary] = []
var _agent_visual: Node3D = null
var _anim_player: AnimationPlayer = null

# Entradas (llenadas por PlayerController o BotController)
var input_forward: float = 0.0
var input_right: float = 0.0
var input_jump: bool = false
var input_walk: bool = false
var input_crouch: bool = false
var input_fire_held: bool = false
var input_fire_just: bool = false
var input_alt_just: bool = false
var input_reload_just: bool = false
var input_use_held: bool = false


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 8
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.08

	_capsule_shape = CapsuleShape3D.new()
	_capsule_shape.radius = MovementMath.HULL_RADIUS
	_capsule_shape.height = MovementMath.STANDING_HEIGHT
	_body_col = CollisionShape3D.new()
	_body_col.shape = _capsule_shape
	_body_col.position = Vector3(0.0, MovementMath.STANDING_HEIGHT * 0.5, 0.0)
	add_child(_body_col)

	_build_hitboxes()
	_load_agent_visual()
	MatchManager.register_combatant(self)


func _build_hitboxes() -> void:
	for spec in HITBOX_SPEC:
		var area := StaticBody3D.new()
		area.collision_layer = 2
		area.collision_mask = 0
		area.set_meta("actor", self)
		area.set_meta("region", spec["region"])
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = float(spec["radius"])
		cap.height = float(spec["height"])
		cs.shape = cap
		area.add_child(cs)
		area.position = Vector3(0.0, float(spec["y"]), 0.0)
		add_child(area)
		_hitbox_areas.append({"node": area, "spec": spec, "shape": cap})


func _load_agent_visual() -> void:
	if _agent_visual != null and is_instance_valid(_agent_visual):
		_agent_visual.queue_free()
	_agent_visual = null
	_anim_player = null
	if is_local_player:
		return
	var path: String = (
		"res://assets/models/agents/ctm-sas.glb"
		if team == "ct"
		else "res://assets/models/agents/ground-rebel.glb"
	)
	if ResourceLoader.exists(path):
		var packed: Resource = ResourceLoader.load(path)
		if packed is PackedScene:
			var inst := (packed as PackedScene).instantiate() as Node3D
			if inst != null:
				inst.rotation.y = PI
				add_child(inst)
				_agent_visual = inst
				_anim_player = _find_animation_player(inst)
				return
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.34
	cap.height = 1.78
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.42, 0.68) if team == "ct" else Color(0.68, 0.45, 0.24)
	mi.mesh = cap
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.9, 0.0)
	add_child(mi)
	_agent_visual = mi


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found: AnimationPlayer = _find_animation_player(c)
		if found != null:
			return found
	return null


func swap_team_halftime() -> void:
	team = "t" if team == "ct" else "ct"
	var rules: Dictionary = MatchManager.get_rules()
	money = int(rules.get("start_money", 800))
	primary_id = -1
	primary_ammo = 0
	primary_reserve = 0
	secondary_id = 2 if team == "ct" else 7
	_reset_slot_ammo(2)
	has_defuse_kit = false
	has_c4 = false
	armor = 0.0
	has_helmet = false
	for k in grenades.keys():
		grenades[k] = 0
	_load_agent_visual()


func reset_for_round(spawn_pos: Vector3, spawn_yaw: float, give_c4: bool) -> void:
	global_position = spawn_pos
	velocity = Vector3.ZERO
	yaw = spawn_yaw
	pitch = 0.0
	rotation.y = yaw
	alive = true
	health = 100.0
	flash_amount = 0.0
	spawn_protection = 2.0 if MatchManager.mode == "deathmatch" else 0.0
	eye_height = MovementMath.STANDING_EYE
	aim_punch.reset()
	primary_recoil.reset()
	secondary_recoil.reset()
	primary_accuracy.reset()
	secondary_accuracy.reset()
	is_reloading = false
	reload_timer = 0.0
	is_planting = false
	plant_progress = 0.0
	is_defusing = false
	defuse_progress = 0.0
	zoom_level = 0
	_burst_remaining = 0

	var rules: Dictionary = MatchManager.get_rules()
	if bool(rules.get("free_armor", false)):
		armor = 100.0
		has_helmet = true
	if bool(rules.get("free_kit", false)) and team == "ct":
		has_defuse_kit = true

	if secondary_id < 0:
		secondary_id = 2 if team == "ct" else 7
		_reset_slot_ammo(2)
	else:
		_reset_slot_ammo(2)
	if primary_id >= 0:
		_reset_slot_ammo(1)

	has_c4 = give_c4 and team == "t"
	active_slot = 1 if primary_id >= 0 else 2
	deploy_cooldown = 0.4
	_set_alive_visuals(true)
	health_changed.emit(health, armor)
	weapon_changed.emit(get_active_weapon_id(), active_slot)


func _reset_slot_ammo(slot: int) -> void:
	var wid: int = primary_id if slot == 1 else secondary_id
	if wid < 0:
		return
	var w: Dictionary = GameData.get_weapon(wid)
	if slot == 1:
		primary_ammo = int(w.get("mag", 30))
		primary_reserve = int(w.get("reserve", 90))
	else:
		secondary_ammo = int(w.get("mag", 12))
		secondary_reserve = int(w.get("reserve", 24))


func _set_alive_visuals(is_alive: bool) -> void:
	visible = is_alive
	collision_layer = 8 if is_alive else 0
	for hb in _hitbox_areas:
		var node: StaticBody3D = hb["node"]
		node.collision_layer = 2 if is_alive else 0


func get_active_weapon_id() -> int:
	if active_slot == 1 and primary_id >= 0:
		return primary_id
	if active_slot == 2 and secondary_id >= 0:
		return secondary_id
	return knife_id


func get_active_ammo() -> Vector2i:
	if active_slot == 1 and primary_id >= 0:
		return Vector2i(primary_ammo, primary_reserve)
	if active_slot == 2 and secondary_id >= 0:
		return Vector2i(secondary_ammo, secondary_reserve)
	return Vector2i(-1, -1)


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, eye_height, 0.0)


func get_look_direction() -> Vector3:
	var p: float = clampf(pitch + aim_punch.pitch * RecoilSystem.RECOIL_VIEW_SCALE, -1.55, 1.55)
	var y: float = yaw + aim_punch.yaw * RecoilSystem.RECOIL_VIEW_SCALE
	var cp: float = cos(p)
	return Vector3(-sin(y) * cp, sin(p), -cos(y) * cp).normalized()


func get_move_speed() -> float:
	if active_slot == 4 or active_slot == 5:
		return 245.0 * MovementMath.SOURCE_UNIT
	var wid: int = get_active_weapon_id()
	var w: Dictionary = GameData.get_weapon(wid)
	var base: float = float(w.get("scopedSpeed" if zoom_level > 0 else "speed", 250.0 * MovementMath.SOURCE_UNIT))
	if input_crouch:
		return base * MovementMath.CROUCH_MODIFIER
	if input_walk:
		return base * MovementMath.WALK_MODIFIER
	return base


func switch_slot(slot: int) -> void:
	if not alive:
		return
	if slot == 1 and primary_id < 0:
		return
	if slot == 2 and secondary_id < 0:
		return
	if slot == 4:
		var next_g: String = _pick_next_grenade()
		if next_g.is_empty():
			return
		active_grenade = next_g
	if slot == 5 and not has_c4:
		return
	if slot != active_slot:
		previous_slot = active_slot
	active_slot = slot
	zoom_level = 0
	is_reloading = false
	reload_timer = 0.0
	is_planting = false
	plant_progress = 0.0
	_burst_remaining = 0
	var wid: int = get_active_weapon_id()
	deploy_cooldown = float(GameData.get_weapon_actions(wid).get("deploy", 0.9)) * 0.65
	if slot == 4:
		AudioManager.play_local_or_3d("utility-%s-draw" % active_grenade, global_position, 14.0, is_local_player, -3.0)
	elif slot == 5:
		AudioManager.play_local_or_3d("bomb-draw", global_position, 14.0, is_local_player, -3.0)
	else:
		AudioManager.play_weapon_action(wid, "draw", global_position, is_local_player)
	weapon_changed.emit(wid, active_slot)


func _pick_next_grenade() -> String:
	var order: PackedStringArray = GrenadeMath.GRENADE_TYPES
	var start_idx: int = order.find(active_grenade)
	for offset in range(1, order.size() + 1):
		var k: String = order[(start_idx + offset) % order.size()]
		if int(grenades.get(k, 0)) > 0:
			return k
	return ""


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if spawn_protection > 0.0:
		spawn_protection = maxf(0.0, spawn_protection - delta)
	if flash_amount > 0.0:
		flash_amount = maxf(0.0, flash_amount - delta)

	_step_movement(delta)
	_step_weapon_timers(delta)
	_step_combat_actions(delta)
	_sync_crouch_hitboxes(delta)
	_update_agent_animation()

	if world_ref != null and not is_local_player:
		var picked: Dictionary = world_ref.try_pickup_nearby(self, true)
		if picked.get("picked", "") == "c4":
			has_c4 = true
	elif world_ref != null and is_local_player:
		var picked2: Dictionary = world_ref.try_pickup_nearby(self, false)
		if picked2.get("picked", "") == "c4":
			has_c4 = true
		elif picked2.get("picked", "") == "weapon":
			_equip_picked_weapon(picked2)


func _equip_picked_weapon(info: Dictionary) -> void:
	var wid: int = int(info["weapon_id"])
	var slot: int = EconomySystem.weapon_slot(wid)
	if slot == 1:
		primary_id = wid
		primary_ammo = int(info["ammo"])
		primary_reserve = int(info["reserve"])
		switch_slot(1)
	elif slot == 2:
		secondary_id = wid
		secondary_ammo = int(info["ammo"])
		secondary_reserve = int(info["reserve"])
		switch_slot(2)


func _step_movement(delta: float) -> void:
	rotation.y = yaw
	var frozen: bool = MatchManager.is_frozen()
	if frozen or is_planting:
		velocity.x = 0.0
		velocity.z = 0.0
		input_jump = false
	else:
		var speed: float = get_move_speed()
		var wish: Vector2 = MovementMath.compute_wish_vector(input_forward, input_right, yaw)
		var h_vel := Vector2(velocity.x, velocity.z)
		if grounded and input_jump:
			h_vel = MovementMath.limit_jump_speed(h_vel, speed)
			velocity.y = MovementMath.JUMP_IMPULSE
			grounded = false
			AudioManager.play_local_or_3d("jump", global_position, 18.0, is_local_player, -6.0)
		h_vel = MovementMath.accelerate(h_vel, wish, speed, delta, grounded)
		velocity.x = h_vel.x
		velocity.z = h_vel.y

	var fall_res: Dictionary = MovementMath.fall_step(velocity.y, delta)
	velocity.y = float(fall_res["vertical"])
	_last_vertical = velocity.y

	move_and_slide()
	_was_grounded = grounded
	grounded = is_on_floor()

	if grounded and not _was_grounded and _last_vertical < -2.0:
		AudioManager.play_local_or_3d("land", global_position, 18.0, is_local_player, -5.0)
		var wid: int = get_active_weapon_id()
		if active_slot == 1 and primary_id >= 0:
			GameData.accuracy_sys.apply_landing_inaccuracy(primary_accuracy, wid, 0, absf(_last_vertical))
		elif active_slot == 2 and secondary_id >= 0:
			GameData.accuracy_sys.apply_landing_inaccuracy(secondary_accuracy, wid, 0, absf(_last_vertical))

	# Pasos por superficie cuando no está agachado ni en shift-walk
	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	if grounded and h_speed > 2.3 and not input_walk and not input_crouch:
		_step_dist += h_speed * delta
		if _step_dist >= 1.75:
			_step_dist = 0.0
			var is_sand: bool = _check_floor_is_sand()
			AudioManager.play_footstep(global_position, is_sand, is_local_player)
	else:
		_step_dist = 0.4


func _check_floor_is_sand() -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.2, 0),
		global_position + Vector3(0, -0.5, 0),
		1
	)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return true
	var col: Object = hit.get("collider", null)
	if col != null and col.has_meta("surface"):
		var s: String = str(col.get_meta("surface", "concrete"))
		return s == "sand" or s == "dirt"
	return false


func _sync_crouch_hitboxes(delta: float) -> void:
	eye_height = MovementMath.smooth_eye_height(eye_height, input_crouch, delta)
	var h: float = MovementMath.hull_height_for_eye(eye_height)
	_capsule_shape.height = h
	_body_col.position.y = h * 0.5
	var crouch_t: float = clampf(
		(MovementMath.STANDING_EYE - eye_height) / (MovementMath.STANDING_EYE - MovementMath.DUCK_EYE),
		0.0,
		1.0
	)
	for hb in _hitbox_areas:
		var node: StaticBody3D = hb["node"]
		var spec: Dictionary = hb["spec"]
		node.position.y = lerpf(float(spec["y"]), float(spec["crouch_y"]), crouch_t)


func _update_agent_animation() -> void:
	if _anim_player == null:
		return
	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	var target_anim: String = ""
	for anim_name in _anim_player.get_animation_list():
		var low: String = anim_name.to_lower()
		if input_crouch and low.contains("crouch") and (h_speed < 0.2 or low.contains("walk")):
			target_anim = anim_name
			break
		if h_speed > 1.2 and (low.contains("run") or low.contains("walk")):
			target_anim = anim_name
			break
		if h_speed <= 1.2 and low.contains("idle"):
			target_anim = anim_name
			break
	if not target_anim.is_empty() and _anim_player.current_animation != target_anim:
		_anim_player.play(target_anim, 0.15)


func _step_weapon_timers(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	deploy_cooldown = maxf(0.0, deploy_cooldown - delta)
	GameData.recoil_sys.advance_aim_punch(aim_punch, delta)

	var pose: Dictionary = _build_pose_dict()
	if primary_id >= 0:
		GameData.recoil_sys.advance_weapon_recoil(primary_recoil, primary_id, delta)
		GameData.accuracy_sys.advance_weapon_accuracy(
			primary_accuracy, primary_id, primary_recoil.index, input_crouch, delta, pose
		)
	if secondary_id >= 0:
		GameData.recoil_sys.advance_weapon_recoil(secondary_recoil, secondary_id, delta)
		GameData.accuracy_sys.advance_weapon_accuracy(
			secondary_accuracy, secondary_id, secondary_recoil.index, input_crouch, delta, pose
		)

	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()


func _build_pose_dict() -> Dictionary:
	var wid: int = get_active_weapon_id()
	var w: Dictionary = GameData.get_weapon(wid)
	var mode_idx: int = 1 if (zoom_level > 0 or (bool(w.get("canToggleSilencer", false)) and not silencer_on) or burst_enabled) else 0
	return {
		"mode": mode_idx,
		"crouch": clampf((MovementMath.STANDING_EYE - eye_height) / (MovementMath.STANDING_EYE - MovementMath.DUCK_EYE), 0.0, 1.0),
		"grounded": grounded,
		"ladder": false,
		"reloading": is_reloading,
		"walking": input_walk,
		"speed": Vector2(velocity.x, velocity.z).length(),
		"verticalSpeed": velocity.y,
	}


func _step_combat_actions(delta: float) -> void:
	if MatchManager.is_frozen():
		return

	# Plantar o desactivar C4
	if active_slot == 5 and has_c4 and team == "t":
		var site: int = GameData.triggers.bomb_site_at(global_position, MovementMath.HULL_RADIUS, _capsule_shape.height)
		if (input_fire_held or input_use_held) and site >= 0 and grounded and not MatchManager.bomb_planted:
			if not is_planting:
				is_planting = true
				plant_progress = 0.0
				AudioManager.play_local_or_3d("bomb-initiate", global_position, 18.0, is_local_player)
			plant_progress += delta
			if plant_progress >= 3.2:
				is_planting = false
				has_c4 = false
				MatchManager.notify_bomb_planted(site, global_position, self)
				if world_ref != null:
					world_ref.spawn_planted_c4(global_position)
				AudioManager.play_3d("bomb-plant", global_position, 32.0, 1.0)
				switch_slot(1 if primary_id >= 0 else 2)
			return
		else:
			is_planting = false
			plant_progress = 0.0

	if team == "ct" and MatchManager.bomb_planted and input_use_held:
		var dist_bomb: float = global_position.distance_to(MatchManager.bomb_position)
		if dist_bomb <= 2.35:
			var dur: float = 5.0 if has_defuse_kit else 10.0
			if not is_defusing:
				is_defusing = true
				defuse_progress = 0.0
				AudioManager.play_local_or_3d("bomb-defuse-start", global_position, 22.0, is_local_player)
			MatchManager.bomb_defusing = true
			MatchManager.bomb_defuse_duration = dur
			defuse_progress += delta
			MatchManager.bomb_defuse_progress = defuse_progress
			if defuse_progress >= dur:
				is_defusing = false
				AudioManager.play_3d("bomb-defuse", MatchManager.bomb_position, 36.0, 1.0)
				MatchManager.notify_bomb_defused(self)
			return
		else:
			is_defusing = false
			defuse_progress = 0.0
	elif is_defusing:
		is_defusing = false
		defuse_progress = 0.0
		MatchManager.bomb_defusing = false

	# Disparo en ráfaga (Glock / FAMAS)
	if _burst_remaining > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_remaining -= 1
			_burst_timer = 0.065
			_fire_gun_bullet(get_active_weapon_id())

	if input_reload_just and not is_reloading and (active_slot == 1 or active_slot == 2):
		try_start_reload()

	if input_alt_just:
		_handle_alt_fire()

	if active_slot == 4:
		if (input_fire_just or input_alt_just) and not active_grenade.is_empty():
			_throw_grenade(1.0 if input_fire_just else 0.48)
		return

	if active_slot == 3:
		if input_fire_just and fire_cooldown <= 0.0 and deploy_cooldown <= 0.0:
			_swing_knife(false)
		elif input_alt_just and fire_cooldown <= 0.0 and deploy_cooldown <= 0.0:
			_swing_knife(true)
		return

	if active_slot == 1 or active_slot == 2:
		var wid: int = get_active_weapon_id()
		var w: Dictionary = GameData.get_weapon(wid)
		var auto_fire: bool = bool(w.get("fullAuto", false))
		var wants_shot: bool = input_fire_held if auto_fire else input_fire_just
		if wants_shot and fire_cooldown <= 0.0 and deploy_cooldown <= 0.0 and not is_reloading:
			var cur_ammo: int = primary_ammo if active_slot == 1 else secondary_ammo
			if cur_ammo <= 0:
				try_start_reload()
				return
			_shoot_active_weapon()


func _handle_alt_fire() -> void:
	if active_slot != 1 and active_slot != 2:
		return
	var wid: int = get_active_weapon_id()
	var w: Dictionary = GameData.get_weapon(wid)
	var zoom_levels: int = int(w.get("zoomLevels", 0))
	if zoom_levels > 0:
		zoom_level = (zoom_level + 1) % (zoom_levels + 1)
		var kit: Dictionary = GameData.get_audio_kit(wid)
		var scope_clip: String = str(kit.get("scope", "zoom"))
		AudioManager.play_local_or_3d(scope_clip, global_position, 14.0, is_local_player, -3.0)
	elif bool(w.get("canToggleSilencer", false)):
		silencer_on = not silencer_on
		AudioManager.play_local_or_3d("click", global_position, 8.0, is_local_player, -4.0)
	elif bool(w.get("burstMode", false)):
		burst_enabled = not burst_enabled
		AudioManager.play_local_or_3d("click", global_position, 8.0, is_local_player, -4.0)


func try_start_reload() -> void:
	var wid: int = get_active_weapon_id()
	var w: Dictionary = GameData.get_weapon(wid)
	var mag: int = int(w.get("mag", 30))
	var cur: int = primary_ammo if active_slot == 1 else secondary_ammo
	var res: int = primary_reserve if active_slot == 1 else secondary_reserve
	if cur >= mag or res <= 0 or is_reloading:
		return
	is_reloading = true
	zoom_level = 0
	var is_shell: bool = str(w.get("reloadStyle", "magazine")) == "shell"
	reload_timer = 0.52 if is_shell else float(w.get("reload", 2.2))
	AudioManager.play_weapon_action(wid, "reload", global_position, is_local_player)


func _finish_reload() -> void:
	is_reloading = false
	var wid: int = get_active_weapon_id()
	var w: Dictionary = GameData.get_weapon(wid)
	if str(w.get("reloadStyle", "magazine")) == "shell":
		if active_slot == 1 and primary_reserve > 0 and primary_ammo < int(w.get("mag", 8)):
			primary_ammo += 1
			primary_reserve -= 1
			AudioManager.play_weapon_action(wid, "reloadIn", global_position, is_local_player)
			if primary_ammo < int(w.get("mag", 8)) and primary_reserve > 0:
				is_reloading = true
				reload_timer = 0.45
		return
	var res_dict: Dictionary = GameData.reload_magazine(
		wid,
		primary_ammo if active_slot == 1 else secondary_ammo,
		primary_reserve if active_slot == 1 else secondary_reserve
	)
	if active_slot == 1:
		primary_ammo = int(res_dict["ammo"])
		primary_reserve = int(res_dict["reserve"])
	else:
		secondary_ammo = int(res_dict["ammo"])
		secondary_reserve = int(res_dict["reserve"])
	AudioManager.play_weapon_action(wid, "reloadIn", global_position, is_local_player)


func _shoot_active_weapon() -> void:
	var wid: int = get_active_weapon_id()
	var w: Dictionary = GameData.get_weapon(wid)
	var use_burst: bool = burst_enabled and bool(w.get("burstMode", false))
	fire_cooldown = float(w.get("alternateDelay", 0.35)) if use_burst else float(w.get("delay", 0.1))

	if use_burst:
		_burst_remaining = 2
		_burst_timer = 0.065

	_fire_gun_bullet(wid)
	if int(w.get("zoomLevels", 0)) > 0 and zoom_level > 0:
		zoom_level = 0


func _fire_gun_bullet(wid: int) -> void:
	var cur: int = primary_ammo if active_slot == 1 else secondary_ammo
	if cur <= 0:
		return
	if active_slot == 1:
		primary_ammo -= 1
	else:
		secondary_ammo -= 1

	var w: Dictionary = GameData.get_weapon(wid)
	var is_silenced: bool = bool(w.get("suppressed", false)) and (silencer_on or wid == 28)
	AudioManager.play_weapon_shot(wid, get_eye_position(), is_silenced, is_local_player)
	fired_shot.emit(wid)

	var pose: Dictionary = _build_pose_dict()
	var acc_state: AccuracySystem.WeaponAccuracyState = primary_accuracy if active_slot == 1 else secondary_accuracy
	var rec_state: RecoilSystem.WeaponRecoilState = primary_recoil if active_slot == 1 else secondary_recoil
	var total_spread: float = GameData.accuracy_sys.weapon_shot_spread(wid, acc_state, pose)

	var eye: Vector3 = get_eye_position()
	var base_dir: Vector3 = get_look_direction()
	var right_vec: Vector3 = base_dir.cross(Vector3.UP).normalized()
	if right_vec.length_squared() < 1e-6:
		right_vec = Vector3.RIGHT
	var up_vec: Vector3 = right_vec.cross(base_dir).normalized()

	var pellets: int = int(w.get("pellets", 1))
	var max_dist: float = float(w.get("range", 8192.0)) * MovementMath.SOURCE_UNIT
	var base_dmg: float = float(w.get("damage", 30.0))
	var head_mult: float = float(w.get("head", 4.0))
	var range_mod: float = float(w.get("rangeModifier", 0.98))
	var armor_ratio: float = float(w.get("armorRatio", 1.4))
	var pen_power: float = float(w.get("penetration", 2.0))

	for _p in range(pellets):
		var offset: Vector2 = AccuracySystem.spread_offset(total_spread, randf(), randf())
		var ray_dir: Vector3 = (base_dir + right_vec * offset.x + up_vec * offset.y).normalized()
		_trace_bullet_ray(
			eye,
			ray_dir,
			max_dist,
			base_dmg,
			head_mult,
			range_mod,
			armor_ratio,
			pen_power,
			wid
		)

	var mode_idx: int = int(pose["mode"])
	GameData.accuracy_sys.apply_firing_inaccuracy(acc_state, wid, mode_idx, pose)
	GameData.recoil_sys.apply_weapon_recoil(aim_punch, rec_state, wid, mode_idx)


func _trace_bullet_ray(
	origin: Vector3,
	dir: Vector3,
	max_dist: float,
	base_damage: float,
	head_mult: float,
	range_mod: float,
	armor_ratio: float,
	pen_power: float,
	wid: int
) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var current_pos: Vector3 = origin
	var remaining_dist: float = max_dist
	var dmg: float = base_damage
	var traveled: float = 0.0
	var penetrations: int = 0
	var penetrated: bool = false
	var exclude_rids: Array[RID] = []
	for hb in _hitbox_areas:
		exclude_rids.append((hb["node"] as CollisionObject3D).get_rid())

	var last_point: Vector3 = origin + dir * minf(max_dist, 65.0)
	var rules: Dictionary = MatchManager.get_rules()
	var ff_enabled: bool = bool(rules.get("friendly_fire", false))

	while remaining_dist > 0.05 and dmg >= 1.0 and penetrations <= BallisticsSystem.MAX_BARRIER_PENETRATIONS:
		var end_pos: Vector3 = current_pos + dir * remaining_dist
		var q := PhysicsRayQueryParameters3D.create(current_pos, end_pos, 2 | 4, exclude_rids)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			break

		var hit_pos: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var collider: Object = hit["collider"]
		var seg_dist: float = current_pos.distance_to(hit_pos)
		traveled += seg_dist
		remaining_dist -= seg_dist
		last_point = hit_pos

		if collider != null and collider.has_meta("actor"):
			var victim: Node = collider.get_meta("actor")
			if victim != null and is_instance_valid(victim) and victim.alive:
				if victim.team == team and not ff_enabled:
					exclude_rids.append((collider as CollisionObject3D).get_rid())
					current_pos = hit_pos + dir * 0.04
					continue
				var region: String = str(collider.get_meta("region", "chest"))
				var r_dmg: float = BallisticsSystem.range_damage(dmg, traveled, range_mod)
				r_dmg *= BallisticsSystem.hit_region_multiplier(region, head_mult)
				if victim.team == team and ff_enabled:
					r_dmg *= 0.33
				var armored: Dictionary = BallisticsSystem.apply_armor_damage(
					r_dmg, region, victim.armor, victim.has_helmet, armor_ratio
				)
				victim.armor = float(armored["armor"])
				var final_hp_dmg: float = float(armored["health_damage"])
				var was_alive: bool = victim.alive
				victim.take_damage(final_hp_dmg, self, wid, region, region == "head", penetrated)
				damaged_enemy.emit(final_hp_dmg, region == "head", was_alive and not victim.alive)
				if world_ref != null:
					world_ref.spawn_impact_spark(hit_pos, normal, "flesh")
				dmg *= 0.65
				exclude_rids.append((collider as CollisionObject3D).get_rid())
				current_pos = hit_pos + dir * 0.05
				continue

		# Superficie del mundo -> penetración
		var mat_name: String = str(collider.get_meta("bullet_material", "concrete")) if collider != null else "concrete"
		if world_ref != null:
			world_ref.spawn_impact_spark(hit_pos, normal, mat_name)

		penetrations += 1
		if penetrations > BallisticsSystem.MAX_BARRIER_PENETRATIONS or pen_power <= 0.0:
			break

		# Raycast inverso para medir espesor
		var probe_end: Vector3 = hit_pos + dir * 1.6
		var exit_q := PhysicsRayQueryParameters3D.create(probe_end, hit_pos + dir * 0.02, 4)
		var exit_hit: Dictionary = space.intersect_ray(exit_q)
		if exit_hit.is_empty():
			break
		var exit_pos: Vector3 = exit_hit["position"]
		var thickness: float = hit_pos.distance_to(exit_pos)
		dmg = BallisticsSystem.penetrate(dmg, pen_power, thickness, mat_name)
		if dmg < 1.0:
			break
		penetrated = true
		if world_ref != null:
			world_ref.spawn_impact_spark(exit_pos, Vector3(exit_hit["normal"]), mat_name)
		current_pos = exit_pos + dir * 0.03
		remaining_dist -= thickness + 0.03

	if world_ref != null and randf() < 0.45:
		world_ref.spawn_tracer(origin + Vector3(0.0, -0.06, 0.0) + dir * 0.6, last_point)


func _swing_knife(stab: bool) -> void:
	fire_cooldown = 0.85 if stab else 0.45
	AudioManager.play_local_or_3d("knife-swing2" if stab else "knife-swing1", global_position, 14.0, is_local_player, -3.0)
	var range_m: float = BallisticsSystem.knife_range(stab)
	var eye: Vector3 = get_eye_position()
	var dir: Vector3 = get_look_direction()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var exclude_rids: Array[RID] = []
	for hb in _hitbox_areas:
		exclude_rids.append((hb["node"] as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * range_m, 2 | 4, exclude_rids)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	if col != null and col.has_meta("actor"):
		var victim: Node = col.get_meta("actor")
		if victim != null and is_instance_valid(victim) and victim.alive and victim.team != team:
			var v_fwd: Vector3 = -victim.global_transform.basis.z
			var back: bool = BallisticsSystem.knife_backstab(global_position, victim.global_position, v_fwd)
			var dmg: float = float(BallisticsSystem.knife_damage(stab, true, back))
			var armored: Dictionary = BallisticsSystem.apply_armor_damage(dmg, "chest", victim.armor, victim.has_helmet, 0.85)
			victim.armor = float(armored["armor"])
			victim.take_damage(float(armored["health_damage"]), self, knife_id, "chest", false, false)
			AudioManager.play_local_or_3d("knife-stab" if stab else "knife-hit", hit["position"], 18.0, is_local_player)
			return
	AudioManager.play_local_or_3d("knife-wall", hit["position"], 18.0, is_local_player)
	if world_ref != null:
		world_ref.spawn_impact_spark(hit["position"], hit["normal"], "concrete")


func _throw_grenade(strength: float) -> void:
	if active_grenade.is_empty() or int(grenades.get(active_grenade, 0)) <= 0:
		return
	var kind: String = active_grenade
	grenades[kind] = int(grenades[kind]) - 1
	var params: Dictionary = GrenadeMath.launch_params(
		GameData.utility_data, kind, strength, get_eye_position(), get_look_direction(), velocity
	)
	AudioManager.play_local_or_3d("utility-%s-throw" % kind, global_position, 22.0, is_local_player)
	if world_ref != null:
		world_ref.spawn_grenade_projectile(kind, params["position"], params["velocity"], self)
	active_grenade = _pick_next_grenade()
	if active_grenade.is_empty():
		switch_slot(1 if primary_id >= 0 else 2)


func use_healthshot() -> void:
	if not alive or not has_healthshot or health >= 100.0:
		return
	has_healthshot = false
	health = minf(100.0, health + 50.0)
	AudioManager.play_local_or_3d("healthshot-success", global_position, 14.0, is_local_player)
	health_changed.emit(health, armor)


func drop_active_item() -> void:
	if not alive or world_ref == null:
		return
	var throw_vel: Vector3 = get_look_direction() * 7.5 + Vector3(0.0, 2.0, 0.0)
	if active_slot == 5 and has_c4:
		has_c4 = false
		world_ref.spawn_dropped_item("c4", 0, 0, 0, get_eye_position(), throw_vel)
		switch_slot(1 if primary_id >= 0 else 2)
	elif active_slot == 1 and primary_id >= 0:
		var wid: int = primary_id
		world_ref.spawn_dropped_item("weapon", wid, primary_ammo, primary_reserve, get_eye_position(), throw_vel)
		primary_id = -1
		primary_ammo = 0
		primary_reserve = 0
		switch_slot(2 if secondary_id >= 0 else 3)
	elif active_slot == 2 and secondary_id >= 0:
		var wid2: int = secondary_id
		world_ref.spawn_dropped_item("weapon", wid2, secondary_ammo, secondary_reserve, get_eye_position(), throw_vel)
		secondary_id = -1
		secondary_ammo = 0
		secondary_reserve = 0
		switch_slot(1 if primary_id >= 0 else 3)


func take_damage(
	amount: float,
	attacker: Node,
	weapon_id: int,
	_region: String,
	headshot: bool,
	penetrated: bool
) -> void:
	if not alive or spawn_protection > 0.0 or amount <= 0.0:
		return
	health -= amount
	if attacker != null and attacker != self:
		MatchManager.register_damage(attacker, amount)
		hit_taken.emit(attacker.global_position, amount)
	if headshot:
		AudioManager.play_local_or_3d("head", global_position, 22.0, is_local_player)
	else:
		AudioManager.play_local_or_3d("damage-%d" % randi_range(1, 3), global_position, 16.0, is_local_player, -3.0)

	if health <= 0.0:
		health = 0.0
		_die(attacker, weapon_id, headshot, penetrated)
	health_changed.emit(health, armor)


func apply_flash(duration: float) -> void:
	flash_amount = maxf(flash_amount, minf(duration, 4.5))


func _die(attacker: Node, weapon_id: int, headshot: bool, penetrated: bool) -> void:
	alive = false
	_set_alive_visuals(false)
	AudioManager.play_3d("death-%d" % randi_range(1, 3), global_position, 26.0, 0.0)
	if world_ref != null:
		if has_c4:
			has_c4 = false
			world_ref.spawn_dropped_item("c4", 0, 0, 0, global_position + Vector3(0, 0.7, 0), Vector3.ZERO)
		if primary_id >= 0:
			world_ref.spawn_dropped_item("weapon", primary_id, primary_ammo, primary_reserve, global_position + Vector3(0, 0.7, 0), Vector3.ZERO)
	var blind: bool = attacker != null and attacker.flash_amount > 1.2
	MatchManager.register_kill(attacker, self, weapon_id, headshot, penetrated, blind)


func try_buy_weapon(weapon_id: int) -> bool:
	var w: Dictionary = GameData.get_weapon(weapon_id)
	if not EconomySystem.weapon_available(w, team):
		return false
	var in_zone: bool = GameData.triggers.in_buy_zone(global_position, team, MovementMath.HULL_RADIUS, _capsule_shape.height)
	if not MatchManager.is_buy_allowed(in_zone):
		return false
	var price: int = 0 if MatchManager.mode == "deathmatch" else int(w.get("price", 0))
	if money < price:
		return false
	money -= price
	var slot: int = EconomySystem.weapon_slot(weapon_id)
	if slot == 1:
		if primary_id >= 0 and world_ref != null and MatchManager.mode != "deathmatch":
			world_ref.spawn_dropped_item("weapon", primary_id, primary_ammo, primary_reserve, get_eye_position(), get_look_direction() * 4.0)
		primary_id = weapon_id
		_reset_slot_ammo(1)
		switch_slot(1)
	elif slot == 2:
		secondary_id = weapon_id
		_reset_slot_ammo(2)
		switch_slot(2)
	AudioManager.play_local_or_3d("buy", global_position, 12.0, is_local_player, -3.0)
	return true


func try_buy_equipment(kind: String) -> bool:
	var in_zone: bool = GameData.triggers.in_buy_zone(global_position, team, MovementMath.HULL_RADIUS, _capsule_shape.height)
	if not MatchManager.is_buy_allowed(in_zone):
		return false
	if kind == "kit" and (team != "ct" or has_defuse_kit):
		return false
	var price: int = EconomySystem.equipment_price(kind, armor, has_helmet)
	if price <= 0 or money < price:
		return false
	money -= price
	if kind == "kit":
		has_defuse_kit = true
	elif kind == "vest":
		armor = 100.0
	else:
		armor = 100.0
		has_helmet = true
	AudioManager.play_local_or_3d("gear-%d" % randi_range(1, 3), global_position, 12.0, is_local_player, -3.0)
	health_changed.emit(health, armor)
	return true


func try_buy_grenade(kind: String) -> bool:
	if not GrenadeMath.grenade_available(kind, team):
		return false
	var in_zone: bool = GameData.triggers.in_buy_zone(global_position, team, MovementMath.HULL_RADIUS, _capsule_shape.height)
	if not MatchManager.is_buy_allowed(in_zone):
		return false
	var is_comp: bool = MatchManager.mode != "casual"
	if not GrenadeMath.can_carry_grenade(grenades, kind, is_comp):
		return false
	var entry: Dictionary = GameData.utility_data.get("weapons", {}).get(kind, {})
	var price: int = int(entry.get("m_nPrice", 300))
	if money < price:
		return false
	money -= price
	grenades[kind] = int(grenades.get(kind, 0)) + 1
	if active_grenade.is_empty():
		active_grenade = kind
	AudioManager.play_local_or_3d("buy", global_position, 12.0, is_local_player, -4.0)
	return true
