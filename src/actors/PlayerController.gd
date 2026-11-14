class_name PlayerController
extends CombatantBase

signal inspect_triggered

var camera_pivot: Node3D = null
var camera: Camera3D = null
var viewmodel_rig: ViewModelRig = null
var _muzzle_light: OmniLight3D = null

var input_locked: bool = false
var _mouse_delta := Vector2.ZERO
var _kick_back: float = 0.0
var _kick_pitch: float = 0.0
var _inspect_timer: float = 0.0
var _inspect_dur: float = 3.6
var _sway_offset := Vector2.ZERO
var _bob_phase: float = 0.0
var _death_respawn_timer: float = 0.0


func _ready() -> void:
	is_local_player = true
	display_name = "Player"
	super._ready()

	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0.0, MovementMath.STANDING_EYE, 0.0)
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.rotation_order = EULER_ORDER_YXZ
	camera.fov = SettingsManager.fov
	camera.near = 0.04
	camera.far = 260.0
	camera_pivot.add_child(camera)

	viewmodel_rig = ViewModelRig.new()
	viewmodel_rig.name = "ViewModelRig"
	add_child(viewmodel_rig)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.78, 0.42)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 4.5
	_muzzle_light.position = Vector3(0.14, -0.06, -0.55)
	camera.add_child(_muzzle_light)

	fired_shot.connect(_on_fired_shot)
	weapon_changed.connect(_on_weapon_changed)
	_refresh_viewmodel()


func _unhandled_input(event: InputEvent) -> void:
	if input_locked or not alive:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_mouse_delta += mm.relative


func _process(delta: float) -> void:
	if camera == null:
		return
	_apply_mouse_look()

	if not alive:
		if viewmodel_rig != null:
			viewmodel_rig.set_visible_viewmodel(false)
		if MatchManager.mode == "deathmatch":
			_death_respawn_timer += delta
			if _death_respawn_timer >= 2.5:
				_death_respawn_timer = 0.0
				var sp: Vector3 = GameData.nav.get_spawn_position(team, randi())
				var sy: float = GameData.nav.get_spawn_yaw(team, randi())
				reset_for_round(sp, sy, false)
		return

	_death_respawn_timer = 0.0
	_read_discrete_inputs()
	_update_camera_and_viewmodel(delta)


func _apply_mouse_look() -> void:
	if _mouse_delta == Vector2.ZERO:
		return
	var zoom_scale: float = 1.0
	if zoom_level == 1:
		zoom_scale = 0.55 * SettingsManager.zoom_sensitivity
	elif zoom_level == 2:
		zoom_scale = 0.25 * SettingsManager.zoom_sensitivity
	var sens_rad: float = deg_to_rad(0.022) * SettingsManager.sensitivity * zoom_scale
	yaw -= _mouse_delta.x * sens_rad
	pitch = clampf(pitch - _mouse_delta.y * sens_rad, -1.54, 1.54)
	_sway_offset.x = clampf(_sway_offset.x - _mouse_delta.x * 0.00018, -0.020, 0.020)
	_sway_offset.y = clampf(_sway_offset.y + _mouse_delta.y * 0.00018, -0.020, 0.020)
	_mouse_delta = Vector2.ZERO


func _read_discrete_inputs() -> void:
	if input_locked:
		input_forward = 0.0
		input_right = 0.0
		input_jump = false
		input_walk = false
		input_crouch = false
		input_fire_held = false
		input_fire_just = false
		input_alt_held = false
		input_alt_just = false
		input_reload_just = false
		input_use_held = false
		return

	input_forward = Input.get_axis("move_back", "move_forward")
	input_right = Input.get_axis("move_left", "move_right")
	input_jump = Input.is_action_pressed("jump")
	input_walk = Input.is_action_pressed("walk")
	input_crouch = Input.is_action_pressed("crouch")
	input_fire_held = Input.is_action_pressed("fire")
	input_fire_just = Input.is_action_just_pressed("fire")
	input_alt_held = Input.is_action_pressed("alt_fire")
	input_alt_just = Input.is_action_just_pressed("alt_fire")
	input_reload_just = Input.is_action_just_pressed("reload")
	input_use_held = Input.is_action_pressed("use")

	if Input.is_action_just_pressed("slot_primary"):
		switch_slot(1)
	elif Input.is_action_just_pressed("slot_secondary"):
		switch_slot(2)
	elif Input.is_action_just_pressed("slot_knife"):
		switch_slot(3)
	elif Input.is_action_just_pressed("slot_grenade"):
		switch_slot(4)
	elif Input.is_action_just_pressed("slot_bomb"):
		switch_slot(5)
	elif Input.is_action_just_pressed("last_weapon"):
		switch_slot(previous_slot)
	elif Input.is_action_just_pressed("drop"):
		drop_active_item()
	elif Input.is_action_just_pressed("slot_healthshot"):
		use_healthshot()
	elif Input.is_action_just_pressed("inspect"):
		_inspect_timer = _inspect_dur
		inspect_triggered.emit()


func _update_camera_and_viewmodel(delta: float) -> void:
	camera_pivot.position.y = eye_height
	var eff_pitch: float = clampf(pitch + aim_punch.pitch * RecoilSystem.RECOIL_VIEW_SCALE, -1.55, 1.55)
	var eff_yaw: float = aim_punch.yaw * RecoilSystem.RECOIL_VIEW_SCALE
	camera.rotation = Vector3(eff_pitch, eff_yaw, 0.0)

	var target_fov: float = SettingsManager.fov
	if zoom_level > 0 and (active_slot == 1 or active_slot == 2):
		var w: Dictionary = GameData.get_weapon(get_active_weapon_id())
		target_fov = float(w.get("zoomFov1" if zoom_level == 1 else "zoomFov2", 40.0))
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 20.0, 0.0, 1.0))

	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	if grounded and h_speed > 0.5:
		_bob_phase += delta * (4.2 + h_speed * 1.45)
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
	_kick_back = lerpf(_kick_back, 0.0, clampf(delta * 18.0, 0.0, 1.0))
	_kick_pitch = lerpf(_kick_pitch, 0.0, clampf(delta * 16.0, 0.0, 1.0))
	if is_reloading or input_fire_held or deploy_cooldown > 0.0:
		_inspect_timer = 0.0
	elif _inspect_timer > 0.0:
		_inspect_timer = maxf(0.0, _inspect_timer - delta)
	_muzzle_light.light_energy = lerpf(_muzzle_light.light_energy, 0.0, clampf(delta * 38.0, 0.0, 1.0))

	var bob_x: float = cos(_bob_phase) * 0.0045 * minf(1.0, h_speed / 5.0)
	var bob_y: float = absf(sin(_bob_phase)) * 0.0055 * minf(1.0, h_speed / 5.0)

	if viewmodel_rig != null:
		viewmodel_rig.set_visible_viewmodel(alive and zoom_level == 0)
		if alive and zoom_level == 0:
			var wid: int = get_active_weapon_id()
			var w: Dictionary = GameData.get_weapon(wid)
			var ammo_v: Vector2i = get_active_ammo()
			var shoot_dur: float = clampf(float(w.get("delay", 0.12)) * 1.4, 0.24, 1.35)
			if wid == 3:
				shoot_dur = 1.15
			var sil_prog: float = 0.0
			if not vm_silencer_action.is_empty():
				sil_prog = clampf(1.0 - vm_silencer_timer / maxf(0.05, vm_silencer_dur), 0.0, 1.0)
			viewmodel_rig.update_rig(delta, {
				"team": team,
				"sway": _sway_offset,
				"bob": Vector2(bob_x, -bob_y),
				"kick_back": _kick_back,
				"kick_pitch": _kick_pitch,
				"deploy_cd": deploy_cooldown,
				"deploy_dur": maxf(0.15, vm_deploy_dur),
				"is_reloading": is_reloading,
				"reload_timer": reload_timer,
				"reload_dur": maxf(0.2, vm_reload_dur),
				"ammo": ammo_v.x,
				"shot_elapsed": vm_shot_elapsed,
				"shot_seq": vm_shot_seq,
				"shoot_anim_dur": shoot_dur,
				"inspect_timer": _inspect_timer,
				"inspect_dur": _inspect_dur,
				"silencer_on": silencer_on,
				"silencer_action": vm_silencer_action,
				"silencer_progress": sil_prog,
				"knife_elapsed": vm_knife_elapsed,
				"knife_stab": vm_knife_stab,
				"grenade_holding": vm_grenade_holding,
				"grenade_hold_elapsed": vm_grenade_hold_elapsed,
				"grenade_underhand": vm_grenade_underhand,
				"grenade_throw_elapsed": vm_grenade_throw_elapsed,
				"is_planting": is_planting,
				"plant_progress": plant_progress,
			})


func _on_fired_shot(wid: int) -> void:
	_kick_back = 0.036
	_kick_pitch = 0.045
	_inspect_timer = 0.0
	var w: Dictionary = GameData.get_weapon(wid)
	var is_silenced: bool = bool(w.get("suppressed", false)) and (silencer_on or wid == 28)
	if _muzzle_light != null:
		_muzzle_light.light_energy = 1.4 if is_silenced else 3.2
	if viewmodel_rig != null:
		viewmodel_rig.trigger_muzzle_flash(is_silenced)


func _on_weapon_changed(_wid: int, _slot: int) -> void:
	_inspect_timer = 0.0
	_refresh_viewmodel()


func _refresh_viewmodel() -> void:
	if viewmodel_rig == null:
		return
	viewmodel_rig.load_weapon(active_slot, get_active_weapon_id(), active_grenade, team)
