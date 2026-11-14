class_name AccuracySystem
extends RefCounted

const SOURCE_UNIT: float = 0.0254


class WeaponAccuracyState:
	extends RefCounted
	var penalty: float = 0.0
	var baseline: float = -1.0
	var mode: int = 0

	func reset() -> void:
		penalty = 0.0
		baseline = -1.0
		mode = 0


var _params: Array = []
var _defaults: Dictionary = {}
var _recoil: RecoilSystem = null


func configure(accuracy_data: Dictionary, weapon_count: int, recoil_sys: RecoilSystem) -> void:
	_defaults = accuracy_data.get("defaults", {})
	var raw_weapons: Array = accuracy_data.get("weapons", [])
	_params.clear()
	for id in range(weapon_count):
		var src_idx: int = 4 if (id >= 4 and id <= 6) or id >= raw_weapons.size() else id
		_params.append(raw_weapons[src_idx])
	_recoil = recoil_sys


func accuracy_recovery(
	weapon_id: int, shots: float, crouched: bool, grounded: bool = true, on_ladder: bool = false
) -> float:
	if _recoil == null:
		return 0.4
	var p: Dictionary = _recoil.get_recovery_params(weapon_id)
	if p.is_empty():
		return 0.4
	if on_ladder:
		return float(p.get("recoveryStand", 0.4))
	if not grounded:
		return float(p.get("recoveryCrouch", 0.4)) * 4.0
	var t_start: float = float(p.get("recoveryTransitionStart", 0))
	var t_end: float = float(p.get("recoveryTransitionEnd", 1))
	var progress: float = clampf((float(int(shots)) - t_start) / maxf(1.0, t_end - t_start), 0.0, 1.0)
	var start_rec: float = float(p.get("recoveryCrouch" if crouched else "recoveryStand", 0.4))
	var final_rec: float = float(
		p.get("recoveryCrouchFinal" if crouched else "recoveryStandFinal", -1.0)
	)
	var target_rec: float = final_rec if final_rec >= 0.0 else start_rec
	return start_rec + (target_rec - start_rec) * progress


func accuracy_baseline(weapon_id: int, pose: Dictionary) -> float:
	if weapon_id < 0 or weapon_id >= _params.size():
		return 0.01
	var p: Dictionary = _params[weapon_id]
	var mode: int = clampi(int(pose.get("mode", 0)), 0, 1)
	var crouch: float = clampf(float(pose.get("crouch", 0.0)), 0.0, 1.0)
	var on_ladder: bool = bool(pose.get("ladder", false))
	var grounded: bool = bool(pose.get("grounded", true))
	var reloading: bool = bool(pose.get("reloading", false))
	var stand_arr: Array = p.get("stand", [0.01, 0.01])
	var crouch_arr: Array = p.get("crouch", [0.008, 0.008])
	var jump_arr: Array = p.get("jump", [0.1, 0.1])
	var ladder_arr: Array = p.get("ladder", [0.1, 0.1])
	var air_scale: float = float(_defaults.get("weapon_air_spread_scale", 1.0))

	var stance: float = 0.0
	if on_ladder:
		stance = float(ladder_arr[mode]) + float(ladder_arr[0])
	elif not grounded:
		stance = float(stand_arr[mode]) + float(jump_arr[mode]) * air_scale
	else:
		stance = float(stand_arr[mode]) + (float(crouch_arr[mode]) - float(stand_arr[mode])) * crouch
	return stance + (float(p.get("reload", 0.0)) if reloading else 0.0)


func advance_weapon_accuracy(
	state: WeaponAccuracyState,
	weapon_id: int,
	shots: float,
	crouched: bool,
	dt: float,
	pose: Dictionary
) -> void:
	if dt <= 0.0:
		return
	var baseline: float = accuracy_baseline(weapon_id, pose)
	var prev_base: float = state.baseline if state.baseline >= 0.0 else baseline
	var previous: float = prev_base + state.penalty
	var grounded: bool = bool(pose.get("grounded", true))
	var on_ladder: bool = bool(pose.get("ladder", false))
	var recovery: float = accuracy_recovery(weapon_id, shots, crouched, grounded, on_ladder)
	var factor: float = exp((-log(10.0) * dt) / recovery) if recovery > 0.0 else 0.0
	var total: float = maxf(baseline, baseline + (previous - baseline) * factor)
	state.baseline = baseline
	state.penalty = maxf(0.0, total - baseline)
	if state.penalty < 1e-8:
		state.penalty = 0.0
	state.mode = clampi(int(pose.get("mode", 0)), 0, 1)


func apply_firing_inaccuracy(
	state: WeaponAccuracyState, weapon_id: int, mode: int, pose: Dictionary
) -> void:
	if weapon_id < 0 or weapon_id >= _params.size():
		return
	var p: Dictionary = _params[weapon_id]
	var m: int = clampi(mode, 0, 1)
	var baseline: float = accuracy_baseline(weapon_id, pose)
	var prev_base: float = state.baseline if state.baseline >= 0.0 else baseline
	var previous: float = prev_base + state.penalty
	var fire_arr: Array = p.get("fire", [0.0, 0.0])
	state.penalty = maxf(0.0, maxf(previous, baseline) + float(fire_arr[m]) - baseline)
	state.baseline = baseline
	state.mode = m


func apply_landing_inaccuracy(
	state: WeaponAccuracyState, weapon_id: int, mode: int, downward_speed: float
) -> void:
	if weapon_id < 0 or weapon_id >= _params.size():
		return
	var p: Dictionary = _params[weapon_id]
	var m: int = clampi(mode, 0, 1)
	var land_arr: Array = p.get("land", [0.0, 0.0])
	state.penalty += (float(land_arr[m]) * maxf(0.0, downward_speed)) / SOURCE_UNIT


func airborne_inaccuracy(weapon_id: int, vertical_speed: float) -> float:
	if weapon_id < 0 or weapon_id >= _params.size():
		return 0.0
	var p: Dictionary = _params[weapon_id]
	var sv_jump: float = float(_defaults.get("sv_jump_impulse", 301.99338))
	var air_scale: float = float(_defaults.get("weapon_air_spread_scale", 1.0))
	var ratio: float = sqrt(absf(vertical_speed) / SOURCE_UNIT / sv_jump)
	var progress: float = clampf((ratio - 0.25) / 0.75, 0.0, 2.0)
	var jump_initial: float = float(p.get("jumpInitial", 0.0))
	var jump_apex: float = float(p.get("jumpApex", 0.0))
	var val: float = clampf(jump_apex + (jump_initial - jump_apex) * progress, 0.0, 2.0 * jump_initial)
	return val * air_scale


func weapon_inaccuracy(weapon_id: int, state: WeaponAccuracyState, pose: Dictionary) -> float:
	if weapon_id < 0 or weapon_id >= _params.size():
		return 0.01
	var p: Dictionary = _params[weapon_id]
	var m: int = clampi(int(pose.get("mode", 0)), 0, 1)
	var max_speed_arr: Array = p.get("maxSpeed", [215.0, 215.0])
	var max_speed: float = float(max_speed_arr[m]) * SOURCE_UNIT
	var speed: float = float(pose.get("speed", 0.0))
	var moving: float = clampf((speed / max_speed - 0.34) / 0.61, 0.0, 1.0) if max_speed > 0.0 else 0.0
	if not bool(pose.get("walking", false)):
		moving = pow(moving, 0.25)
	var baseline: float = accuracy_baseline(weapon_id, pose)
	var prev_base: float = state.baseline if state.baseline >= 0.0 else baseline
	var move_arr: Array = p.get("move", [0.0, 0.0])
	var grounded: bool = bool(pose.get("grounded", true))
	var v_speed: float = float(pose.get("verticalSpeed", 0.0))
	var air_add: float = airborne_inaccuracy(weapon_id, v_speed) if not grounded else 0.0
	return minf(
		1.0,
		maxf(baseline, prev_base + state.penalty) + float(move_arr[m]) * moving + air_add
	)


func weapon_shot_spread(weapon_id: int, state: WeaponAccuracyState, pose: Dictionary) -> float:
	if weapon_id < 0 or weapon_id >= _params.size():
		return 0.01
	var p: Dictionary = _params[weapon_id]
	var m: int = clampi(int(pose.get("mode", 0)), 0, 1)
	var spread_arr: Array = p.get("spread", [0.001, 0.001])
	return weapon_inaccuracy(weapon_id, state, pose) + float(spread_arr[m])


static func spread_offset(radius: float, angle_sample: float, radius_sample: float) -> Vector2:
	var ang: float = angle_sample * TAU
	var dist: float = radius_sample * radius
	return Vector2(cos(ang) * dist, sin(ang) * dist)
