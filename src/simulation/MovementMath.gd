class_name MovementMath
extends RefCounted

const SOURCE_UNIT: float = 0.0254
const GROUND_ACCELERATION: float = 5.5
const AIR_ACCELERATION: float = 12.0
const AIR_WISH_SPEED: float = 30.0 * SOURCE_UNIT
const FRICTION: float = 5.2
const STOP_SPEED: float = 80.0 * SOURCE_UNIT
const GRAVITY: float = 800.0 * SOURCE_UNIT
const JUMP_IMPULSE: float = 301.99338 * SOURCE_UNIT
const WALK_MODIFIER: float = 0.52
const CROUCH_MODIFIER: float = 0.34
const JUMP_SPEED_LIMIT: float = 1.1
const HULL_RADIUS: float = 16.0 * SOURCE_UNIT
const STANDING_HEIGHT: float = 72.0 * SOURCE_UNIT
const DUCK_HEIGHT: float = 54.0 * SOURCE_UNIT
const STANDING_EYE: float = 64.0 * SOURCE_UNIT
const DUCK_EYE: float = 46.0 * SOURCE_UNIT


static func limit_jump_speed(horizontal_vel: Vector2, max_speed: float) -> Vector2:
	var mag: float = horizontal_vel.length()
	var limit: float = max_speed * JUMP_SPEED_LIMIT
	if mag > limit and mag > 0.0:
		return horizontal_vel * (limit / mag)
	return horizontal_vel


static func fall_step(vertical: float, dt: float) -> Dictionary:
	return {
		"distance": (vertical - GRAVITY * dt * 0.5) * dt,
		"vertical": vertical - GRAVITY * dt,
	}


static func accelerate(
	horizontal_vel: Vector2,
	wish_dir: Vector2,
	speed: float,
	dt: float,
	grounded: bool,
	acceleration_speed: float = -1.0
) -> Vector2:
	if acceleration_speed < 0.0:
		acceleration_speed = speed
	var v: Vector2 = horizontal_vel
	if grounded:
		var mag: float = v.length()
		if mag > 0.0:
			var drop: float = maxf(mag, STOP_SPEED) * FRICTION * dt
			var factor: float = maxf(0.0, mag - drop) / mag
			v *= factor
	var dir_len: float = wish_dir.length()
	if dir_len <= 1e-8:
		return v
	var dir: Vector2 = wish_dir / dir_len
	var cap: float = speed if grounded else minf(speed, AIR_WISH_SPEED)
	var add: float = maxf(0.0, cap - v.dot(dir))
	var accel: float = GROUND_ACCELERATION if grounded else AIR_ACCELERATION
	var amount: float = minf(add, accel * acceleration_speed * dt)
	return v + dir * amount


static func smooth_eye_height(current_eye: float, ducking: bool, dt: float) -> float:
	var target: float = DUCK_EYE if ducking else STANDING_EYE
	return current_eye + (target - current_eye) * (1.0 - exp(-15.0 * dt))


static func hull_height_for_eye(eye: float) -> float:
	return eye + STANDING_HEIGHT - STANDING_EYE


static func compute_wish_vector(input_forward: float, input_right: float, yaw: float) -> Vector2:
	# En Godot Y-up (-Z adelante, +X derecha):
	# forward = (-sin(yaw), -cos(yaw)), right = (cos(yaw), -sin(yaw))
	var wx: float = input_right * cos(yaw) - input_forward * sin(yaw)
	var wz: float = -input_right * sin(yaw) - input_forward * cos(yaw)
	return Vector2(wx, wz)
