class_name GrenadeMath
extends RefCounted

const SOURCE_UNIT: float = 0.0254
const GRENADE_RADIUS: float = 2.0 * SOURCE_UNIT
const GRAVITY: float = MovementMath.GRAVITY * 0.4
const ELASTICITY: float = 0.45
const STOP_SPEED: float = 20.0 * SOURCE_UNIT

const GRENADE_TYPES: PackedStringArray = ["he", "flash", "smoke", "molotov", "incendiary", "decoy"]


static func throw_speed(utility_data: Dictionary, kind: String, strength: float) -> float:
	var weapons_dict: Dictionary = utility_data.get("weapons", {})
	var entry: Dictionary = weapons_dict.get(kind, {})
	var vel_units: float = float(entry.get("m_flThrowVelocity", 750.0))
	var s: float = clampf(strength, 0.0, 1.0)
	return vel_units * SOURCE_UNIT * 0.9 * (0.3 + 0.7 * s)


static func launch_params(
	utility_data: Dictionary,
	kind: String,
	strength: float,
	eye_pos: Vector3,
	look_dir: Vector3,
	player_velocity: Vector3
) -> Dictionary:
	var s: float = clampf(strength, 0.0, 1.0)
	var dir_norm: Vector3 = look_dir.normalized()
	var pitch: float = asin(clampf(dir_norm.y, -1.0, 1.0))
	var pitch_deg: float = rad_to_deg(pitch)
	var launch_pitch: float = pitch + deg_to_rad(((90.0 - absf(pitch_deg)) * 10.0) / 90.0)
	# En Godot -Z adelante, dir horizontal es (x, z) con atan2(-x, -z) o usar vector horizontal:
	var horiz := Vector2(dir_norm.x, dir_norm.z)
	var h_len: float = horiz.length()
	var aim: Vector3
	if h_len > 1e-6:
		var h_dir: Vector2 = horiz / h_len
		var ch: float = cos(launch_pitch)
		aim = Vector3(h_dir.x * ch, sin(launch_pitch), h_dir.y * ch).normalized()
	else:
		aim = Vector3(0.0, sin(launch_pitch), -cos(launch_pitch)).normalized()
	var start_pos: Vector3 = eye_pos + Vector3(0.0, (s * 12.0 - 12.0) * SOURCE_UNIT, 0.0)
	var vel: Vector3 = aim * throw_speed(utility_data, kind, s) + player_velocity * 1.25
	return {"position": start_pos, "direction": aim, "velocity": vel}


static func bounce(velocity: Vector3, normal: Vector3) -> Dictionary:
	var v: Vector3 = velocity
	var impact: float = maxf(0.0, -v.dot(normal))
	if impact > 0.0:
		v += normal * (impact * 2.0)
	v *= ELASTICITY
	if absf(v.x) < 0.1 * SOURCE_UNIT:
		v.x = 0.0
	if absf(v.y) < 0.1 * SOURCE_UNIT:
		v.y = 0.0
	if absf(v.z) < 0.1 * SOURCE_UNIT:
		v.z = 0.0
	var resting: bool = normal.y > 0.7 and v.length_squared() < STOP_SPEED * STOP_SPEED
	if resting:
		v = Vector3.ZERO
	return {"velocity": v, "impact": impact, "resting": resting}


static func he_damage(distance: float) -> float:
	if distance >= 8.9:
		return 0.0
	var d: float = maxf(0.0, distance - 0.6) / 3.5
	return 105.0 * exp(-(d * d))


static func flash_exposure(distance: float, facing_dot: float) -> float:
	return maxf(0.0, 1.0 - distance / 30.0) * (0.22 + 0.78 * maxf(0.0, facing_dot))


static func fire_impact_allowed(normal_y: float, slope_degrees: float = 30.0) -> bool:
	return normal_y >= cos(deg_to_rad(slope_degrees)) - 1e-6


static func grenade_available(kind: String, team: String) -> bool:
	if kind == "molotov" and team == "ct":
		return false
	if kind == "incendiary" and team == "t":
		return false
	return true


static func can_carry_grenade(inv: Dictionary, kind: String, competitive: bool = true) -> bool:
	var total: int = 0
	for k in GRENADE_TYPES:
		total += int(inv.get(k, 0))
	if total >= (4 if competitive else 3):
		return false
	var count_kind: int = int(inv.get(kind, 0))
	var max_kind: int = 2 if (kind == "flash" and competitive) else 1
	if count_kind >= max_kind:
		return false
	if kind == "molotov" or kind == "incendiary":
		if int(inv.get("molotov", 0)) + int(inv.get("incendiary", 0)) > 0:
			return false
	return true
