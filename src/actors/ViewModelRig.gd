class_name ViewModelRig
extends Node3D

# Source viewmodel axes: +X fwd, +Y left, +Z up (inches) -> Godot camera: -Z fwd, -X left, +Y up (meters)
const CAMERA_BASIS := Transform3D(
	Basis(
		Vector3(0.0, 0.0, -0.0254),
		Vector3(-0.0254, 0.0, 0.0),
		Vector3(0.0, 0.0254, 0.0)
	),
	Vector3.ZERO
)
const ROT_Y_PI := Transform3D(
	Basis(
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -1.0)
	),
	Vector3.ZERO
)
# Column-major Three.js Matrix4.fromArray from bayonet.glb node extras.meshToSource
const BAYONET_MESH_TO_SOURCE := Transform3D(
	Basis(
		Vector3(0.0, 46.831012, 0.0),
		Vector3(46.831012, 0.0, 0.0),
		Vector3(0.0, 0.0, -46.831012)
	),
	Vector3(0.0, 0.0, -1.15)
)

const BLEND_DURATION := 0.08
const MUZZLE_FLASH_DUR := 0.055

var _layer: CanvasLayer = null
var _svc: SubViewportContainer = null
var _viewport: SubViewport = null
var _vm_cam: Camera3D = null
var _vm_group: Node3D = null
var _key_light: DirectionalLight3D = null
var _fill_light: DirectionalLight3D = null

var _arms_by_team: Dictionary = {} # "ct"/"t" -> {"root": Node3D, "skel": Skeleton3D, "bones": Dictionary, "twists": Array}
var _active_team: String = ""

var _current_key: String = ""
var _family: String = "" # "firearm", "bayonet", "grenade", "c4"
var _weapon_model: Node3D = null
var _weapon_skel: Skeleton3D = null
var _weapon_skel_inv := Transform3D.IDENTITY
var _grenade_model_basis_inv := Transform3D.IDENTITY
var _silencer_node: Node3D = null
var _silencer_bone_idx: int = -1
var _muzzle_node: Node3D = null
var _muzzle_bone_idx: int = -1

var _source_root: Node3D = null
var _source_anim_player: AnimationPlayer = null
var _source_nodes: Dictionary = {} # node_name -> Node3D
var _source_arms_bindings: Array[Dictionary] = []
var _source_weapon_bindings: Array[Dictionary] = []
var _source_wpn: Node3D = null
var _source_wpn_offset: Node3D = null
var _source_c4_weapon: Node3D = null

var _last_clip: String = ""
var _prev_clip: String = ""
var _prev_time: float = 0.0
var _blend_start: float = -10.0
var _clock: float = 0.0

var _muzzle_fx_root: Node3D = null
var _muzzle_fire_quad: MeshInstance3D = null
var _muzzle_smoke_quad: MeshInstance3D = null
var _muzzle_light: OmniLight3D = null
var _muzzle_flash_timer: float = 0.0

var _cache_scenes: Dictionary = {}


func _ready() -> void:
	_build_viewport()
	_load_arms_pair()


func _build_viewport() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ViewModelLayer"
	_layer.layer = 1
	add_child(_layer)

	_svc = SubViewportContainer.new()
	_svc.name = "ViewModelViewportContainer"
	_svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_svc.stretch = true
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_svc)

	_viewport = SubViewport.new()
	_viewport.name = "ViewModelViewport"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_svc.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.84, 0.87, 0.92)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08

	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	_key_light = DirectionalLight3D.new()
	_key_light.light_color = Color(1.0, 0.94, 0.85)
	_key_light.light_energy = 1.65
	_key_light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	_viewport.add_child(_key_light)

	_fill_light = DirectionalLight3D.new()
	_fill_light.light_color = Color(0.75, 0.84, 0.98)
	_fill_light.light_energy = 0.55
	_fill_light.rotation_degrees = Vector3(25.0, -145.0, 0.0)
	_viewport.add_child(_fill_light)

	_vm_cam = Camera3D.new()
	_vm_cam.name = "ViewModelCamera"
	_vm_cam.fov = 62.0
	_vm_cam.near = 0.01
	_vm_cam.far = 8.0
	_viewport.add_child(_vm_cam)

	_vm_group = Node3D.new()
	_vm_group.name = "ViewModelRoot"
	_vm_group.position = Vector3(0.05, -0.025, -0.025)
	_vm_cam.add_child(_vm_group)

	_build_muzzle_fx()


func _build_muzzle_fx() -> void:
	_muzzle_fx_root = Node3D.new()
	_muzzle_fx_root.visible = false
	_vm_cam.add_child(_muzzle_fx_root)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.78, 0.40)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 2.6
	_muzzle_fx_root.add_child(_muzzle_light)

	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fire_mat.billboard_keep_scale = true
	fire_mat.no_depth_test = true
	fire_mat.albedo_color = Color(1.0, 0.90, 0.65, 0.95)
	if ResourceLoader.exists("res://assets/textures/polish/muzzle_fire.png"):
		fire_mat.albedo_texture = ResourceLoader.load("res://assets/textures/polish/muzzle_fire.png") as Texture2D

	var qm1 := QuadMesh.new()
	qm1.size = Vector2(0.32, 0.32)
	_muzzle_fire_quad = MeshInstance3D.new()
	_muzzle_fire_quad.mesh = qm1
	_muzzle_fire_quad.material_override = fire_mat
	_muzzle_fx_root.add_child(_muzzle_fire_quad)

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.billboard_keep_scale = true
	smoke_mat.albedo_color = Color(0.86, 0.88, 0.90, 0.35)
	if ResourceLoader.exists("res://assets/textures/polish/muzzle_smoke.png"):
		smoke_mat.albedo_texture = ResourceLoader.load("res://assets/textures/polish/muzzle_smoke.png") as Texture2D

	var qm2 := QuadMesh.new()
	qm2.size = Vector2(0.28, 0.28)
	_muzzle_smoke_quad = MeshInstance3D.new()
	_muzzle_smoke_quad.mesh = qm2
	_muzzle_smoke_quad.material_override = smoke_mat
	_muzzle_fx_root.add_child(_muzzle_smoke_quad)


func _load_arms_pair() -> void:
	for team_key in ["ct", "t"]:
		var path: String = GameData.get_arms_path(team_key)
		var scene := _get_packed(path)
		if scene == null:
			continue
		var inst := scene.instantiate() as Node3D
		if inst == null:
			continue
		inst.visible = false
		_vm_group.add_child(inst)
		_disable_culling_recursive(inst)
		var skel: Skeleton3D = _find_skeleton(inst)
		var bone_map: Dictionary = {}
		var twists: Array[Dictionary] = []
		if skel != null:
			for b_idx in range(skel.get_bone_count()):
				var b_name: String = skel.get_bone_name(b_idx)
				if _is_arm_bone(b_name):
					bone_map[b_name] = b_idx
			for side in ["L", "R"]:
				var hand_idx: int = skel.find_bone("hand_%s" % side)
				var lower_idx: int = skel.find_bone("arm_lower_%s" % side)
				if hand_idx < 0 or lower_idx < 0:
					continue
				var helpers: Array[Dictionary] = []
				for ti in range(2):
					var t_name_upper := "arm_lower_%s_TWIST%s" % [side, "" if ti == 0 else "1"]
					var t_name_lower := "arm_lower_%s_twist%s" % [side, "" if ti == 0 else "1"]
					var t_idx: int = skel.find_bone(t_name_upper)
					if t_idx < 0:
						t_idx = skel.find_bone(t_name_lower)
					if t_idx >= 0:
						var t_rest: Transform3D = skel.get_bone_rest(t_idx)
						helpers.append({
							"idx": t_idx,
							"rest_q": t_rest.basis.get_rotation_quaternion().normalized(),
							"rest_pos": t_rest.origin,
							"weight": float(ti + 1) / 3.0,
						})
				if not helpers.is_empty():
					var h_rest: Transform3D = skel.get_bone_rest(hand_idx)
					twists.append({
						"hand_idx": hand_idx,
						"lower_idx": lower_idx,
						"hand_rest_inv": h_rest.basis.get_rotation_quaternion().inverse(),
						"helpers": helpers,
					})
		_arms_by_team[team_key] = {
			"root": inst,
			"skel": skel,
			"bones": bone_map,
			"twists": twists,
		}


func set_visible_viewmodel(v: bool) -> void:
	if _layer != null:
		_layer.visible = v


func trigger_muzzle_flash(silenced: bool) -> void:
	if silenced:
		return
	_muzzle_flash_timer = MUZZLE_FLASH_DUR
	if _muzzle_fire_quad != null:
		_muzzle_fire_quad.scale = Vector3.ONE * randf_range(0.85, 1.35)
		_muzzle_fire_quad.rotation.z = randf_range(0.0, TAU)
	if _muzzle_smoke_quad != null:
		_muzzle_smoke_quad.scale = Vector3.ONE * randf_range(0.9, 1.25)


func load_weapon(slot: int, weapon_id: int, grenade_kind: String, team_name: String) -> void:
	_set_active_team(team_name)
	var key := "%d:%d:%s" % [slot, weapon_id, grenade_kind]
	if key == _current_key:
		return
	_current_key = key
	_clear_loaded_weapon()

	var model_path := ""
	var anims_path := ""
	if slot == 4 and not grenade_kind.is_empty():
		_family = "grenade"
		model_path = "res://assets/models/grenades/%s.glb" % grenade_kind
		anims_path = "res://assets/models/grenades/%s_anims.glb" % grenade_kind
	elif slot == 5:
		_family = "c4"
		model_path = "res://assets/models/c4.glb"
		anims_path = "res://assets/models/c4_anims.glb"
	elif slot == 3:
		_family = "bayonet"
		model_path = "res://assets/models/bayonet.glb"
		anims_path = "res://assets/models/bayonet_anims.glb"
	else:
		_family = "firearm"
		model_path = GameData.get_viewmodel_path(weapon_id)
		anims_path = GameData.get_viewmodel_anims_path(weapon_id)

	var m_scene := _get_packed(model_path)
	if m_scene != null:
		var inst := m_scene.instantiate() as Node3D
		if inst != null:
			_vm_group.add_child(inst)
			_disable_culling_recursive(inst)
			_weapon_model = inst
			_weapon_skel = _find_skeleton(inst)
			if _weapon_skel != null:
				_weapon_skel_inv = _node_rel_xform(_weapon_skel, _vm_group).affine_inverse()
				_silencer_bone_idx = _weapon_skel.find_bone("silencer")
				_muzzle_bone_idx = _weapon_skel.find_bone("muzzle")
			_silencer_node = _find_named_node(inst, "silencer")
			_muzzle_node = _find_named_node(inst, "muzzle")
			if _family == "grenade":
				var g_wpn := _find_named_node(inst, "weapon")
				if g_wpn != null:
					_grenade_model_basis_inv = _node_rel_xform(g_wpn, inst).affine_inverse()
				else:
					_grenade_model_basis_inv = Transform3D.IDENTITY

	var a_scene := _get_packed(anims_path)
	if a_scene != null:
		var s_inst := a_scene.instantiate() as Node3D
		if s_inst != null:
			_source_root = s_inst
			_source_anim_player = _find_anim_player(s_inst)
			if _source_anim_player != null:
				_source_anim_player.active = false
			_index_source_nodes(s_inst)
			_source_wpn = _source_nodes.get("wpn", null)
			_source_wpn_offset = _source_nodes.get("weapon_offset", null)
			_source_c4_weapon = _source_nodes.get("weapon", null)
			_rebuild_bindings()

	_last_clip = ""
	_prev_clip = ""
	_blend_start = -10.0


func update_rig(delta: float, state: Dictionary) -> void:
	_clock += delta
	var team_name: String = str(state.get("team", "ct"))
	_set_active_team(team_name)
	if _source_root == null or _source_anim_player == null:
		return

	var sway: Vector2 = state.get("sway", Vector2.ZERO)
	var bob: Vector2 = state.get("bob", Vector2.ZERO)
	var kick_back: float = float(state.get("kick_back", 0.0))
	var kick_pitch: float = float(state.get("kick_pitch", 0.0))
	var user_off: Vector3 = SettingsManager.viewmodel_offset * MovementMath.SOURCE_UNIT

	_vm_group.position = Vector3(
		0.05 + user_off.x * 0.35 + sway.x,
		-0.025 + user_off.z * 0.35 + bob.y,
		-0.025 - user_off.y * 0.35 + kick_back
	)
	_vm_group.rotation = Vector3(kick_pitch, 0.0, 0.0)

	var sel := _select_clip_and_progress(state)
	var clip_name: String = sel["clip"]
	var progress: float = clampf(float(sel["progress"]), 0.0, 1.0)
	if not _source_anim_player.has_animation(clip_name):
		clip_name = _fallback_idle_clip()
	if not _source_anim_player.has_animation(clip_name):
		return

	if _last_clip != clip_name:
		if not _last_clip.is_empty() and not clip_name.begins_with("draw") and not clip_name.begins_with("shoot"):
			_prev_clip = _last_clip
			_prev_time = _source_anim_player.current_animation_position if _source_anim_player.has_animation(_prev_clip) else 0.0
			_blend_start = _clock
		elif _last_clip == "lookat01":
			_prev_clip = _last_clip
			_prev_time = _source_anim_player.current_animation_position
			_blend_start = _clock
		_last_clip = clip_name

	var anim_len: float = maxf(0.01, _source_anim_player.get_animation(clip_name).length)
	var target_t: float = progress * anim_len

	# Sample previous pose when crossfading
	var blend_w: float = clampf((_clock - _blend_start) / BLEND_DURATION, 0.0, 1.0)
	var prev_xforms: Dictionary = {}
	if blend_w < 1.0 and not _prev_clip.is_empty() and _source_anim_player.has_animation(_prev_clip):
		_source_anim_player.assigned_animation = _prev_clip
		_source_anim_player.seek(_prev_time, true)
		for nm in _source_nodes:
			prev_xforms[nm] = (_source_nodes[nm] as Node3D).transform

	_source_anim_player.assigned_animation = clip_name
	_source_anim_player.seek(target_t, true)

	if blend_w < 1.0 and not prev_xforms.is_empty():
		for nm in prev_xforms:
			var n: Node3D = _source_nodes[nm]
			n.transform = (prev_xforms[nm] as Transform3D).interpolate_with(n.transform, blend_w)

	_retarget_to_scene(state, progress)
	_update_muzzle_fx(delta)


func _select_clip_and_progress(state: Dictionary) -> Dictionary:
	var deploy_cd: float = float(state.get("deploy_cd", 0.0))
	var reload_t: float = float(state.get("reload_timer", 0.0))
	var reload_dur: float = maxf(0.2, float(state.get("reload_dur", 2.2)))
	var shot_el: float = float(state.get("shot_elapsed", 99.0))
	var inspect_t: float = float(state.get("inspect_timer", 0.0))
	var inspect_dur: float = float(state.get("inspect_dur", 3.5))
	var sil_act: String = str(state.get("silencer_action", ""))
	var sil_prog: float = float(state.get("silencer_progress", 0.0))

	if _family == "firearm":
		if not sil_act.is_empty() and _source_anim_player.has_animation(sil_act):
			return {"clip": sil_act, "progress": sil_prog}
		if bool(state.get("is_reloading", false)):
			var r_clip := "reload_empty" if (int(state.get("ammo", 1)) == 0 and _source_anim_player.has_animation("reload_empty")) else "reload"
			return {"clip": r_clip, "progress": clampf(1.0 - reload_t / reload_dur, 0.0, 1.0)}
		if deploy_cd > 0.0:
			var d_dur: float = maxf(0.15, float(state.get("deploy_dur", 0.65)))
			return {"clip": "draw", "progress": clampf(1.0 - deploy_cd / d_dur, 0.0, 1.0)}
		var shoot_dur: float = maxf(0.18, float(state.get("shoot_anim_dur", 0.5)))
		if shot_el < shoot_dur:
			return {"clip": "shoot1", "progress": clampf(shot_el / shoot_dur, 0.0, 1.0)}
		if inspect_t > 0.0 and _source_anim_player.has_animation("lookat01"):
			return {"clip": "lookat01", "progress": clampf(1.0 - inspect_t / inspect_dur, 0.0, 1.0)}
		return {"clip": "idle", "progress": 0.0}

	if _family == "bayonet":
		if deploy_cd > 0.0:
			var kd_dur: float = maxf(0.15, float(state.get("deploy_dur", 0.6)))
			return {"clip": "draw", "progress": clampf(1.0 - deploy_cd / kd_dur, 0.0, 1.0)}
		var k_el: float = float(state.get("knife_elapsed", 99.0))
		var k_stab: bool = bool(state.get("knife_stab", false))
		var k_dur: float = 0.72 if k_stab else 0.45
		if k_el < k_dur:
			var k_clip := "heavy_miss1" if k_stab else ("light_miss1" if (int(state.get("shot_seq", 0)) % 2 == 0) else "light_miss2")
			return {"clip": k_clip, "progress": clampf(k_el / k_dur, 0.0, 1.0)}
		if inspect_t > 0.0 and _source_anim_player.has_animation("lookat01"):
			return {"clip": "lookat01", "progress": clampf(1.0 - inspect_t / inspect_dur, 0.0, 1.0)}
		return {"clip": "idle1", "progress": fmod(_clock * 0.25, 1.0)}

	if _family == "grenade":
		var throw_el: float = float(state.get("grenade_throw_elapsed", 99.0))
		var underhand: bool = bool(state.get("grenade_underhand", false))
		if throw_el < 0.35:
			var t_clip := "throw_underhand" if underhand else "throw_overhand"
			return {"clip": t_clip, "progress": clampf(throw_el / 0.35, 0.0, 1.0)}
		if bool(state.get("grenade_holding", false)):
			var hold_el: float = float(state.get("grenade_hold_elapsed", 0.0))
			if hold_el < 0.32 and _source_anim_player.has_animation("pullpin"):
				return {"clip": "pullpin", "progress": clampf(hold_el / 0.32, 0.0, 1.0)}
			var ch_clip := "throwcharge_low" if underhand else "throwcharge_high"
			if _source_anim_player.has_animation(ch_clip):
				return {"clip": ch_clip, "progress": clampf((hold_el - 0.32) * 2.5, 0.0, 1.0)}
		if deploy_cd > 0.0:
			var gd_dur: float = maxf(0.15, float(state.get("deploy_dur", 0.55)))
			return {"clip": "draw", "progress": clampf(1.0 - deploy_cd / gd_dur, 0.0, 1.0)}
		return {"clip": "idle", "progress": fmod(_clock * 0.25, 1.0)}

	# c4
	if bool(state.get("is_planting", false)):
		return {"clip": "plant_c4", "progress": clampf(float(state.get("plant_progress", 0.0)) / 3.2, 0.0, 1.0)}
	if deploy_cd > 0.0:
		return {"clip": "draw_c4", "progress": clampf(1.0 - deploy_cd / maxf(0.15, float(state.get("deploy_dur", 0.6))), 0.0, 1.0)}
	if inspect_t > 0.0 and _source_anim_player.has_animation("lookat01_c4"):
		return {"clip": "lookat01_c4", "progress": clampf(1.0 - inspect_t / inspect_dur, 0.0, 1.0)}
	return {"clip": "idle_c4", "progress": 0.0}


func _retarget_to_scene(state: Dictionary, progress: float) -> void:
	var arm_basis: Transform3D = CAMERA_BASIS if (_family == "firearm" or _family == "bayonet") else ROT_Y_PI
	var arms_entry: Dictionary = _arms_by_team.get(_active_team, {})
	var arms_skel: Skeleton3D = arms_entry.get("skel", null)
	if arms_skel != null:
		for bind in _source_arms_bindings:
			var b_idx: int = int(bind["idx"])
			var src: Node3D = bind["src"]
			var sg := _src_global(src)
			var cam_xf: Transform3D = arm_basis * sg
			arms_skel.set_bone_global_pose_override(
				b_idx,
				Transform3D(cam_xf.basis.orthonormalized(), cam_xf.origin),
				1.0,
				true
			)
		_apply_forearm_twists(arms_skel, arms_entry.get("twists", []))

	if _weapon_model == null:
		return

	if _family == "bayonet":
		var wpn_xf: Transform3D = CAMERA_BASIS * (_src_global(_source_wpn) if _source_wpn != null else Transform3D.IDENTITY)
		var off_xf: Transform3D = _src_global(_source_wpn_offset) if _source_wpn_offset != null else Transform3D.IDENTITY
		_weapon_model.transform = wpn_xf * off_xf * BAYONET_MESH_TO_SOURCE
		return

	if _family == "c4":
		var c4_wpn_xf: Transform3D = ROT_Y_PI * (_src_global(_source_wpn) if _source_wpn != null else Transform3D.IDENTITY)
		var c4_basis_inv: Transform3D = _src_global(_source_c4_weapon).affine_inverse() if _source_c4_weapon != null else Transform3D.IDENTITY
		_weapon_model.transform = c4_wpn_xf * c4_basis_inv
		return

	if _family == "grenade":
		var gr_wpn_xf: Transform3D = ROT_Y_PI * (_src_global(_source_wpn) if _source_wpn != null else Transform3D.IDENTITY)
		_weapon_model.transform = gr_wpn_xf * _grenade_model_basis_inv
		_weapon_model.visible = float(state.get("grenade_throw_elapsed", 99.0)) > 0.30
		if _weapon_skel != null:
			for b in _source_weapon_bindings:
				var idx: int = int(b["idx"])
				var sn: Node3D = b["src"]
				_weapon_skel.set_bone_pose_position(idx, sn.position)
				_weapon_skel.set_bone_pose_rotation(idx, sn.quaternion)
				_weapon_skel.set_bone_pose_scale(idx, sn.scale)
		return

	# firearm
	var attach_cam: Transform3D = CAMERA_BASIS * (_src_global(_source_wpn) if _source_wpn != null else Transform3D.IDENTITY)
	if _weapon_skel != null:
		var sil_vis: bool = bool(state.get("silencer_on", true))
		var sil_act: String = str(state.get("silencer_action", ""))
		if sil_act == "silencer_attach":
			sil_vis = progress >= 0.42
		elif sil_act == "silencer_detach":
			sil_vis = progress <= 0.58

		for b in _source_weapon_bindings:
			var idx: int = int(b["idx"])
			var sn: Node3D = b["src"]
			var bone_cam: Transform3D = attach_cam * _src_global(sn)
			var local_skel: Transform3D = _weapon_skel_inv * bone_cam
			var basis_clean: Basis = local_skel.basis.orthonormalized()
			if idx == _silencer_bone_idx and not sil_vis:
				basis_clean = basis_clean.scaled(Vector3.ONE * 0.0001)
			_weapon_skel.set_bone_global_pose_override(
				idx,
				Transform3D(basis_clean, local_skel.origin),
				1.0,
				true
			)


func _apply_forearm_twists(skel: Skeleton3D, twists: Array) -> void:
	for t in twists:
		var lower_idx: int = int(t["lower_idx"])
		var hand_idx: int = int(t["hand_idx"])
		var lower_g: Transform3D = skel.get_bone_global_pose_override(lower_idx)
		var hand_g: Transform3D = skel.get_bone_global_pose_override(hand_idx)
		var hand_local_q: Quaternion = (lower_g.affine_inverse() * hand_g).basis.get_rotation_quaternion().normalized()
		var delta_q: Quaternion = (hand_local_q * (t["hand_rest_inv"] as Quaternion)).normalized()
		if delta_q.w < 0.0:
			delta_q = -delta_q
		var twist_angle: float = 2.0 * atan2(delta_q.x, delta_q.w)
		for h in t["helpers"]:
			var h_idx: int = int(h["idx"])
			var w: float = float(h["weight"])
			var roll_q := Quaternion(Vector3.RIGHT, twist_angle * w)
			var local_q: Quaternion = (roll_q * (h["rest_q"] as Quaternion)).normalized()
			var local_xf := Transform3D(Basis(local_q), h["rest_pos"] as Vector3)
			var g_xf: Transform3D = lower_g * local_xf
			skel.set_bone_global_pose_override(
				h_idx,
				Transform3D(g_xf.basis.orthonormalized(), g_xf.origin),
				1.0,
				true
			)


func _update_muzzle_fx(delta: float) -> void:
	if _muzzle_flash_timer <= 0.0:
		if _muzzle_fx_root != null:
			_muzzle_fx_root.visible = false
		if _muzzle_light != null:
			_muzzle_light.light_energy = 0.0
		return
	_muzzle_flash_timer = maxf(0.0, _muzzle_flash_timer - delta)
	var t: float = clampf(_muzzle_flash_timer / MUZZLE_FLASH_DUR, 0.0, 1.0)
	_muzzle_fx_root.visible = true
	var m_pos := Vector3(0.14, -0.05, -0.62)
	if _source_wpn != null and _source_nodes.has("muzzle"):
		var m_xf: Transform3D = _vm_group.transform * CAMERA_BASIS * _src_global(_source_wpn) * _src_global(_source_nodes["muzzle"] as Node3D)
		m_pos = m_xf.origin
	elif _weapon_skel != null and _muzzle_bone_idx >= 0:
		m_pos = (_vm_group.transform * _node_rel_xform(_weapon_skel, _vm_group) * _weapon_skel.get_bone_global_pose(_muzzle_bone_idx)).origin
	_muzzle_fx_root.position = m_pos
	if _muzzle_light != null:
		_muzzle_light.light_energy = 2.8 * t
	if _muzzle_fire_quad != null and _muzzle_fire_quad.material_override is StandardMaterial3D:
		(_muzzle_fire_quad.material_override as StandardMaterial3D).albedo_color.a = 0.95 * t
	if _muzzle_smoke_quad != null and _muzzle_smoke_quad.material_override is StandardMaterial3D:
		(_muzzle_smoke_quad.material_override as StandardMaterial3D).albedo_color.a = 0.35 * t


func _rebuild_bindings() -> void:
	_source_arms_bindings.clear()
	_source_weapon_bindings.clear()
	var arms_entry: Dictionary = _arms_by_team.get(_active_team, {})
	var bones: Dictionary = arms_entry.get("bones", {})
	for b_name in bones:
		var sn: Node3D = _source_nodes.get(b_name, null)
		if sn != null:
			_source_arms_bindings.append({"idx": int(bones[b_name]), "src": sn})
	if _weapon_skel != null:
		for b_idx in range(_weapon_skel.get_bone_count()):
			var b_name: String = _weapon_skel.get_bone_name(b_idx)
			var sn2: Node3D = _source_nodes.get(b_name, null)
			if sn2 != null:
				_source_weapon_bindings.append({"idx": b_idx, "src": sn2})


func _set_active_team(team_name: String) -> void:
	var norm := "ct" if team_name == "ct" else "t"
	if norm == _active_team:
		return
	_active_team = norm
	for k in _arms_by_team:
		var root: Node3D = _arms_by_team[k].get("root", null)
		if root != null:
			root.visible = (k == norm)
	if _source_root != null:
		_rebuild_bindings()


func _clear_loaded_weapon() -> void:
	_muzzle_flash_timer = 0.0
	if _muzzle_fx_root != null:
		_muzzle_fx_root.visible = false
	if _weapon_model != null and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = null
	_weapon_skel = null
	_silencer_node = null
	_silencer_bone_idx = -1
	_muzzle_node = null
	_muzzle_bone_idx = -1
	if _source_root != null and is_instance_valid(_source_root):
		_source_root.queue_free()
	_source_root = null
	_source_anim_player = null
	_source_nodes.clear()
	_source_arms_bindings.clear()
	_source_weapon_bindings.clear()
	_source_wpn = null
	_source_wpn_offset = null
	_source_c4_weapon = null


func _src_global(n: Node3D) -> Transform3D:
	if n == null:
		return Transform3D.IDENTITY
	var acc := n.transform
	var p := n.get_parent()
	while p != null and p != _source_root:
		if p is Node3D:
			acc = (p as Node3D).transform * acc
		p = p.get_parent()
	return acc


func _node_rel_xform(n: Node3D, ancestor: Node3D) -> Transform3D:
	var acc := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			acc = (cur as Node3D).transform * acc
		cur = cur.get_parent()
	return acc


func _fallback_idle_clip() -> String:
	match _family:
		"bayonet":
			return "idle1"
		"c4":
			return "idle_c4"
		_:
			return "idle"


func _is_arm_bone(n: String) -> bool:
	return (
		n.begins_with("arm_upper_")
		or n.begins_with("arm_lower_")
		or n.begins_with("hand_")
		or n.begins_with("finger_")
	)


func _index_source_nodes(root: Node) -> void:
	if root is Node3D and not _source_nodes.has(root.name):
		_source_nodes[root.name] = root
	for c in root.get_children():
		_index_source_nodes(c)


func _get_packed(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _cache_scenes.has(path):
		return _cache_scenes[path] as PackedScene
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	if res is PackedScene:
		_cache_scenes[path] = res
		return res as PackedScene
	return null


func _disable_culling_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).extra_cull_margin = 16.0
	for c in node.get_children():
		_disable_culling_recursive(c)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var f := _find_anim_player(c)
		if f != null:
			return f
	return null


func _find_named_node(node: Node, target_name: String) -> Node3D:
	if node is Node3D and node.name == target_name:
		return node as Node3D
	for c in node.get_children():
		var f := _find_named_node(c, target_name)
		if f != null:
			return f
	return null
