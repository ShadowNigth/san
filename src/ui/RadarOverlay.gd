class_name RadarOverlay
extends Control

var player: PlayerController = null
var zoom_alternate: bool = false
var full_map_held: bool = false
var _radar_tex: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var tex_path: String = "res://assets/textures/dust2_radar.png"
	if ResourceLoader.exists(tex_path):
		var res: Resource = ResourceLoader.load(tex_path)
		if res is Texture2D:
			_radar_tex = res


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("radar_zoom"):
		zoom_alternate = not zoom_alternate
	full_map_held = Input.is_action_pressed("radar_full")
	queue_redraw()


func _world_to_tex_px(world_pos: Vector3) -> Vector2:
	var ov: Dictionary = GameData.dust2_overview
	var pos_x: float = float(ov.get("pos_x", -2476.0))
	var pos_y: float = float(ov.get("pos_y", 3239.0))
	var ov_scale: float = float(ov.get("scale", 4.4))
	var tex_w: float = float(_radar_tex.get_width()) if _radar_tex != null else 1024.0
	var factor: float = tex_w / 1024.0
	var px: float = ((world_pos.x / 0.0254 - pos_x) / ov_scale) * factor
	var pz: float = ((pos_y + world_pos.z / 0.0254) / ov_scale) * factor
	return Vector2(px, pz)


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return

	var box_size: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, box_size), Color(0.05, 0.07, 0.09, 0.88))

	var tex_w: float = float(_radar_tex.get_width()) if _radar_tex != null else 1024.0
	var base_scale: float = minf(box_size.x, box_size.y) / tex_w
	var zoom: float = 1.0 if full_map_held else (1.45 if zoom_alternate else 2.15)
	var eff_scale: float = base_scale * zoom
	var center: Vector2 = box_size * 0.5

	var p_tex: Vector2 = _world_to_tex_px(player.global_position)
	var origin_tex: Vector2 = Vector2(tex_w * 0.5, tex_w * 0.5) if full_map_held else p_tex
	var rot_angle: float = 0.0 if full_map_held else player.yaw

	draw_set_transform(center, rot_angle, Vector2(eff_scale, eff_scale))
	if _radar_tex != null:
		draw_texture(_radar_tex, -origin_tex, Color(1.0, 1.0, 1.0, 0.92))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Sitios A y B
	var font: Font = ThemeDB.fallback_font
	for s_idx in range(2):
		var sp: Vector2 = _xform_radar(GameData.nav.get_site_position(s_idx), origin_tex, eff_scale, center, rot_angle)
		var lbl: String = "A" if s_idx == 0 else "B"
		draw_string(font, sp + Vector2(-6, 6), lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.95, 0.35, 0.25, 0.95))

	# Humos activos en radar
	if player.world_ref != null:
		for sm in player.world_ref.active_smokes:
			var sm_p: Vector2 = _xform_radar(sm["pos"], origin_tex, eff_scale, center, rot_angle)
			draw_circle(sm_p, 8.0 * zoom * 0.6, Color(0.82, 0.86, 0.9, 0.5))

	# Bomba C4
	if MatchManager.bomb_planted:
		var bp: Vector2 = _xform_radar(MatchManager.bomb_position, origin_tex, eff_scale, center, rot_angle)
		draw_circle(bp, 6.5, Color(1.0, 0.15, 0.15, 0.95))
	elif player.world_ref != null:
		for it in player.world_ref.dropped_items:
			if it["kind"] == "c4" and player.team == "t":
				var dp: Vector2 = _xform_radar(it["pos"], origin_tex, eff_scale, center, rot_angle)
				draw_rect(Rect2(dp - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.72, 0.15))

	# Compañeros y enemigos visibles
	for c in MatchManager.combatants:
		if c == null or not is_instance_valid(c) or not c.alive:
			continue
		var is_ally: bool = c.team == player.team
		if not is_ally and MatchManager.mode != "deathmatch":
			# Mostrar enemigo solo si está en línea de visión del jugador o lleva C4 visible
			var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(player.get_eye_position(), c.get_eye_position(), 4)
			if not space.intersect_ray(q).is_empty():
				continue
		var pos2d: Vector2 = _xform_radar(c.global_position, origin_tex, eff_scale, center, rot_angle)
		if not full_map_held:
			var delta_v: Vector2 = pos2d - center
			var max_r: float = minf(box_size.x, box_size.y) * 0.46
			if delta_v.length() > max_r:
				pos2d = center + delta_v.normalized() * max_r

		var col: Color
		if c == player:
			col = Color(0.98, 0.95, 0.32)
		elif is_ally:
			col = Color(0.32, 0.76, 1.0) if c.team == "ct" else Color(0.96, 0.68, 0.28)
		else:
			col = Color(1.0, 0.22, 0.22)

		draw_circle(pos2d, 5.0, Color(0, 0, 0, 0.7))
		draw_circle(pos2d, 3.8, col)

		var heading_angle: float = rot_angle - c.yaw - PI * 0.5
		var nose: Vector2 = pos2d + Vector2(cos(heading_angle), sin(heading_angle)) * 8.5
		draw_line(pos2d, nose, col, 2.0)

	# Borde del radar
	draw_rect(Rect2(Vector2.ZERO, box_size), Color(0.45, 0.55, 0.65, 0.45), false, 1.5)


func _xform_radar(
	wp: Vector3, origin_tex: Vector2, eff_scale: float, center: Vector2, rot_angle: float
) -> Vector2:
	var pt: Vector2 = (_world_to_tex_px(wp) - origin_tex) * eff_scale
	return center + pt.rotated(rot_angle)
