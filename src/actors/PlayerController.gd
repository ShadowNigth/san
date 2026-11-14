class_name PlayerController
extends CombatantBase

signal inspect_triggered

var camera_pivot: Node3D = null
var camera: Camera3D = null
var viewmodel_holder: Node3D = null
var _viewmodel_model: Node3D = null
var _muzzle_light: OmniLight3D = null

var input_locked: bool = false
var _mouse_delta := Vector2.ZERO
var _kick_back: float = 0.0
var _kick_pitch: float = 0.0
var _inspect_timer: float = 0.0
var _sway_offset := Vector2.ZERO
var _bob_phase: float = 0.0
var _death_respawn_timer: float = 0.0
var _last_vm_key: String = ""


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

	viewmodel_holder = Node3D.new()
	viewmodel_holder.name = "ViewmodelHolder"
	camera.add_child(viewmodel_holder)

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
	_sway_offset.x = clampf(_sway_offset.x - _mouse_delta.x * 0.00018, -0.022, 0.022)
	_sway_offset.y = clampf(_sway_offset.y + _mouse_delta.y * 0.00018, -0.022, 0.022)
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
		_inspect_timer = 1.8
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

	viewmodel_holder.visible = zoom_level == 0

	# Bobbing + kickback + inspect + sway
	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	if grounded and h_speed > 0.5:
		_bob_phase += delta * (4.0 + h_speed * 1.45)
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
	_kick_back = lerpf(_kick_back, 0.0, clampf(delta * 18.0, 0.0, 1.0))
	_kick_pitch = lerpf(_kick_pitch, 0.0, clampf(delta * 16.0, 0.0, 1.0))
	if _inspect_timer > 0.0:
		_inspect_timer = maxf(0.0, _inspect_timer - delta)
	_muzzle_light.light_energy = lerpf(_muzzle_light.light_energy, 0.0, clampf(delta * 38.0, 0.0, 1.0))

	var off: Vector3 = SettingsManager.viewmodel_offset * MovementMath.SOURCE_UNIT
	var bob_x: float = cos(_bob_phase) * 0.004 * minf(1.0, h_speed / 5.0)
	var bob_y: float = absf(sin(_bob_phase)) * 0.005 * minf(1.0, h_speed / 5.0)
	var reload_dip: float = -0.14 * sin(clampf(reload_timer * 2.0, 0.0, PI)) if is_reloading else 0.0
	var deploy_dip: float = -0.12 * clampf(deploy_cooldown * 2.2, 0.0, 1.0)
	viewmodel_holder.position = Vector3(
		-off.x + _sway_offset.x + bob_x,
		-off.z + _sway_offset.y - bob_y + reload_dip + deploy_dip,
		off.y + _kick_back
	)
	var inspect_yaw: float = sin(_inspect_timer * PI / 1.8) * 0.55 if _inspect_timer > 0.0 else 0.0
	var inspect_roll: float = sin(_inspect_timer * PI / 1.8) * 0.35 if _inspect_timer > 0.0 else 0.0
	viewmodel_holder.rotation = Vector3(_kick_pitch, inspect_yaw, inspect_roll)


func _on_fired_shot(_wid: int) -> void:
	_kick_back = 0.042
	_kick_pitch = 0.055
	if _muzzle_light != null:
		_muzzle_light.light_energy = 1.6 if silencer_on else 3.2


func _on_weapon_changed(_wid: int, _slot: int) -> void:
	_inspect_timer = 0.0
	_refresh_viewmodel()


func _refresh_viewmodel() -> void:
	if viewmodel_holder == null:
		return
	var key: String = "%d:%d:%s" % [active_slot, get_active_weapon_id(), active_grenade]
	if key == _last_vm_key:
		return
	_last_vm_key = key

	if _viewmodel_model != null and is_instance_valid(_viewmodel_model):
		_viewmodel_model.queue_free()
		_viewmodel_model = null

	var path: String = ""
	var yaw_offset: float = PI
	var local_pos := Vector3(0.10, -0.12, -0.22)
	var model_scale: Vector3 = Vector3.ONE

	if active_slot == 4 and not active_grenade.is_empty():
		path = "res://assets/models/grenades/%s.glb" % active_grenade
		yaw_offset = 0.0
		local_pos = Vector3(0.16, -0.15, -0.34)
		model_scale = Vector3.ONE * 1.15
	elif active_slot == 5:
		path = "res://assets/models/c4.glb"
		yaw_offset = PI * 0.35
		local_pos = Vector3(0.14, -0.16, -0.36)
		model_scale = Vector3.ONE * 0.65
	elif active_slot == 3:
		path = "res://assets/models/bayonet.glb"
		yaw_offset = 0.0
		local_pos = Vector3(0.16, -0.16, -0.34)
		model_scale = Vector3.ONE * 0.9
	else:
		path = GameData.get_viewmodel_path(get_active_weapon_id())
		yaw_offset = PI
		local_pos = Vector3(0.08, -0.10, -0.18)

	if not path.is_empty() and ResourceLoader.exists(path):
		var packed: Resource = ResourceLoader.load(path)
		if packed is PackedScene:
			var inst := (packed as PackedScene).instantiate() as Node3D
			if inst != null:
				inst.rotation.y = yaw_offset
				inst.position = local_pos
				inst.scale = model_scale
				viewmodel_holder.add_child(inst)
				_viewmodel_model = inst
