class_name RecoilSystem
extends RefCounted

const RECOIL_VIEW_SCALE: float = 0.45
const SCALE: float = 2.0
const TABLE_SIZE: int = 64
const SMOOTHING: float = 0.55
const SUPPRESSION: float = 0.75
const SUPPRESSION_SHOTS: float = 4.0
const ANGLE_DECAY: float = 8.0
const VELOCITY_DECAY: float = 4.5
const ANGLE_LINEAR_DECAY: float = 18.0
const INDEX_DECAY: float = log(10.0) * 2.0


class ParkMillerRandom:
	extends RefCounted
	var _seed: int = -1
	var _previous: int = 0
	var _shuffle: PackedInt64Array = PackedInt64Array()

	func _init(seed_value: int) -> void:
		_seed = -maxi(1, absi(seed_value))
		_shuffle.resize(32)
		_shuffle.fill(0)

	func _advance() -> void:
		@warning_ignore("integer_division")
		var high: int = _seed / 127773
		_seed = 16807 * (_seed - high * 127773) - 2836 * high
		if _seed < 0:
			_seed += 2147483647

	func next_float() -> float:
		if _seed <= 0 or _previous == 0:
			_seed = maxi(1, -_seed)
			for i in range(39, -1, -1):
				_advance()
				if i < 32:
					_shuffle[i] = _seed
			_previous = _shuffle[0]
		_advance()
		@warning_ignore("integer_division")
		var index: int = _previous / 67108864
		_previous = _shuffle[index]
		_shuffle[index] = _seed
		return minf(float(_previous) / 2147483647.0, 1.0 - 1.2e-7)

	func range_float(min_val: float, max_val: float) -> float:
		return min_val + next_float() * (max_val - min_val)


class AimPunch:
	extends RefCounted
	var pitch: float = 0.0
	var yaw: float = 0.0
	var pitch_velocity: float = 0.0
	var yaw_velocity: float = 0.0

	func reset() -> void:
		pitch = 0.0
		yaw = 0.0
		pitch_velocity = 0.0
		yaw_velocity = 0.0


class WeaponRecoilState:
	extends RefCounted
	var index: float = 0.0
	var time_since_shot: float = 1e9
	var mode: int = 0

	func reset() -> void:
		index = 0.0
		time_since_shot = 1e9
		mode = 0


var _params: Array = []
var _tables: Array = []


func configure(recoil_weapons: Array, weapon_count: int) -> void:
	_params.clear()
	_tables.clear()
	for id in range(weapon_count):
		var src_idx: int = 4 if (id >= 4 and id <= 6) or id >= recoil_weapons.size() else id
		var p: Dictionary = recoil_weapons[src_idx]
		_params.append(p)
		var modes_table: Array = []
		for mode in range(2):
			var rng := ParkMillerRandom.new(int(p.get("seed", 1)))
			var angle: float = 0.0
			var magnitude: float = 0.0
			var full_auto: bool = bool(p.get("fullAuto", false))
			var angles: Array = p.get("angle", [0.0, 0.0])
			var angle_vars: Array = p.get("angleVariance", [0.0, 0.0])
			var mags: Array = p.get("magnitude", [0.0, 0.0])
			var mag_vars: Array = p.get("magnitudeVariance", [0.0, 0.0])
			var shot_list: Array = []
			for shot in range(TABLE_SIZE):
				var next_angle: float = float(angles[mode]) + rng.range_float(
					-float(angle_vars[mode]), float(angle_vars[mode])
				)
				var next_mag: float = float(mags[mode]) + rng.range_float(
					-float(mag_vars[mode]), float(mag_vars[mode])
				)
				if full_auto and shot > 0:
					angle = angle + SMOOTHING * (next_angle - angle)
					magnitude = magnitude + SMOOTHING * (next_mag - magnitude)
				else:
					angle = next_angle
					magnitude = next_mag
				var suppression: float = 1.0
				if full_auto and float(shot) < SUPPRESSION_SHOTS:
					suppression = SUPPRESSION + ((1.0 - SUPPRESSION) * float(shot)) / SUPPRESSION_SHOTS
				magnitude *= suppression
				var strength: float = deg_to_rad(magnitude * SCALE)
				var rad_angle: float = deg_to_rad(angle)
				shot_list.append(
					Vector2(cos(rad_angle) * strength, -sin(rad_angle) * strength)
				)
			modes_table.append(shot_list)
		_tables.append(modes_table)


func get_impulse(weapon_id: int, shot: float, mode: int = 0) -> Vector2:
	if weapon_id < 0 or weapon_id >= _tables.size():
		return Vector2.ZERO
	var m: int = clampi(mode, 0, 1)
	var idx: int = maxi(0, int(shot)) % TABLE_SIZE
	return _tables[weapon_id][m][idx]


func apply_weapon_recoil(
	punch: AimPunch, state: WeaponRecoilState, weapon_id: int, mode: int = 0
) -> void:
	var imp: Vector2 = get_impulse(weapon_id, state.index, mode)
	punch.pitch_velocity += imp.x
	punch.yaw_velocity += imp.y
	state.index += 1.0
	state.time_since_shot = 0.0
	state.mode = clampi(mode, 0, 1)


func advance_aim_punch(punch: AimPunch, dt: float) -> void:
	if dt <= 0.0:
		return
	var mag: float = Vector2(punch.pitch, punch.yaw).length()
	var decayed_mag: float = mag * exp(-ANGLE_DECAY * dt)
	var linear: float = deg_to_rad(ANGLE_LINEAR_DECAY * SCALE) * dt
	var angle_ratio: float = 0.0
	if decayed_mag > linear and decayed_mag > 0.0:
		angle_ratio = exp(-ANGLE_DECAY * dt) * (1.0 - linear / decayed_mag)
	var vel_ratio: float = exp(-VELOCITY_DECAY * dt)
	punch.pitch = punch.pitch * angle_ratio + punch.pitch_velocity * (1.0 + vel_ratio) * 0.5 * dt
	punch.yaw = punch.yaw * angle_ratio + punch.yaw_velocity * (1.0 + vel_ratio) * 0.5 * dt
	punch.pitch_velocity *= vel_ratio
	punch.yaw_velocity *= vel_ratio
	if absf(punch.pitch) < 1e-7:
		punch.pitch = 0.0
	if absf(punch.yaw) < 1e-7:
		punch.yaw = 0.0


func advance_weapon_recoil(state: WeaponRecoilState, weapon_id: int, dt: float) -> void:
	if dt <= 0.0 or weapon_id < 0 or weapon_id >= _params.size():
		return
	var old_time: float = state.time_since_shot
	state.time_since_shot += dt
	var cycle_times: Array = _params[weapon_id].get("cycleTime", [0.1, 0.1])
	var grace: float = float(cycle_times[clampi(state.mode, 0, 1)]) * 1.1
	var recovery_step: float = maxf(0.0, state.time_since_shot - maxf(grace, old_time))
	state.index *= exp(-INDEX_DECAY * recovery_step)
	if state.index < 1e-7:
		state.index = 0.0


func get_recovery_params(weapon_id: int) -> Dictionary:
	if weapon_id < 0 or weapon_id >= _params.size():
		return {}
	return _params[weapon_id]
