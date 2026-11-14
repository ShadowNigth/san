class_name CrosshairOverlay
extends Control

var player: PlayerController = null
var hitmarker_timer: float = 0.0
var hitmarker_headshot: bool = false
var damage_dir_timer: float = 0.0
var damage_from_pos := Vector3.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func notify_hit(headshot: bool) -> void:
	hitmarker_timer = 0.16
	hitmarker_headshot = headshot


func notify_damage_from(pos: Vector3) -> void:
	damage_from_pos = pos
	damage_dir_timer = 0.9


func _process(delta: float) -> void:
	if hitmarker_timer > 0.0:
		hitmarker_timer = maxf(0.0, hitmarker_timer - delta)
	if damage_dir_timer > 0.0:
		damage_dir_timer = maxf(0.0, damage_dir_timer - delta)
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player) or not player.alive:
		return

	var sz: Vector2 = size
	var center: Vector2 = sz * 0.5

	# Flashbang whiteout
	if player.flash_amount > 0.01:
		var alpha: float = clampf(player.flash_amount / 2.2, 0.0, 0.96)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 1.0, 1.0, alpha))

	# Sniper scope overlay
	if player.zoom_level > 0 and (player.active_slot == 1 or player.active_slot == 2):
		var radius: float = minf(sz.x, sz.y) * 0.44
		draw_rect(Rect2(0.0, 0.0, center.x - radius, sz.y), Color.BLACK)
		draw_rect(Rect2(center.x + radius, 0.0, sz.x - (center.x + radius), sz.y), Color.BLACK)
		draw_rect(Rect2(center.x - radius, 0.0, radius * 2.0, center.y - radius), Color.BLACK)
		draw_rect(Rect2(center.x - radius, center.y + radius, radius * 2.0, sz.y - (center.y + radius)), Color.BLACK)
		draw_arc(center, radius, 0.0, TAU, 96, Color.BLACK, 18.0)
		draw_line(Vector2(center.x - radius, center.y), Vector2(center.x + radius, center.y), Color(0, 0, 0, 0.85), 1.6)
		draw_line(Vector2(center.x, center.y - radius), Vector2(center.x, center.y + radius), Color(0, 0, 0, 0.85), 1.6)
		draw_circle(center, 2.2, Color(0.95, 0.15, 0.15, 0.9))
		return

	# Mira clásica / dinámica
	var gap: float = SettingsManager.crosshair_gap
	if SettingsManager.crosshair_dynamic and (player.active_slot == 1 or player.active_slot == 2):
		var wid: int = player.get_active_weapon_id()
		var acc_state: AccuracySystem.WeaponAccuracyState = player.primary_accuracy if player.active_slot == 1 else player.secondary_accuracy
		var spread_val: float = GameData.accuracy_sys.weapon_inaccuracy(wid, acc_state, player._build_pose_dict())
		gap += clampf(spread_val * 460.0, 0.0, 42.0)

	var line_len: float = SettingsManager.crosshair_size
	var thick: float = SettingsManager.crosshair_thickness
	var col: Color = SettingsManager.crosshair_color
	var outline := Color(0.0, 0.0, 0.0, 0.72)

	var bars: Array[Rect2] = [
		Rect2(center.x - gap - line_len, center.y - thick * 0.5, line_len, thick),
		Rect2(center.x + gap, center.y - thick * 0.5, line_len, thick),
		Rect2(center.x - thick * 0.5, center.y - gap - line_len, thick, line_len),
		Rect2(center.x - thick * 0.5, center.y + gap, thick, line_len),
	]
	for r in bars:
		draw_rect(r.grow(1.0), outline)
		draw_rect(r, col)

	if SettingsManager.crosshair_dot:
		draw_rect(Rect2(center.x - thick * 0.5 - 1.0, center.y - thick * 0.5 - 1.0, thick + 2.0, thick + 2.0), outline)
		draw_rect(Rect2(center.x - thick * 0.5, center.y - thick * 0.5, thick, thick), col)

	# Hitmarker sutil al acertar
	if hitmarker_timer > 0.0:
		var hm_col: Color = Color(1.0, 0.25, 0.25, hitmarker_timer * 5.0) if hitmarker_headshot else Color(1.0, 1.0, 1.0, hitmarker_timer * 4.5)
		for dir in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(center + dir * 5.0, center + dir * 11.0, hm_col, 2.0)

	# Indicador direccional de daño recibido
	if damage_dir_timer > 0.0:
		var to_att: Vector3 = damage_from_pos - player.global_position
		var fwd := Vector2(-sin(player.yaw), -cos(player.yaw))
		var right := Vector2(cos(player.yaw), -sin(player.yaw))
		var rel := Vector2(right.dot(Vector2(to_att.x, to_att.z)), -fwd.dot(Vector2(to_att.x, to_att.z)))
		if rel.length_squared() > 1e-4:
			var ang: float = atan2(rel.y, rel.x)
			draw_arc(center, 110.0, ang - 0.24, ang + 0.24, 16, Color(0.95, 0.14, 0.14, clampf(damage_dir_timer, 0.0, 0.75)), 9.0)
