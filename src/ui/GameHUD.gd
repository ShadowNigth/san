class_name GameHUD
extends CanvasLayer

signal return_to_menu_requested
signal switch_team_requested

var player: PlayerController = null

var crosshair: CrosshairOverlay = null
var radar: RadarOverlay = null
var buy_menu: BuyMenu = null
var scoreboard: ScoreboardOverlay = null
var settings_panel: SettingsPanel = null

var _pause_panel: PanelContainer = null
var _location_label: Label = null
var _money_label: Label = null
var _c4_badge: Label = null
var _top_ct_label: Label = null
var _top_t_label: Label = null
var _timer_label: Label = null
var _phase_label: Label = null
var _hp_label: Label = null
var _armor_label: Label = null
var _weapon_label: Label = null
var _ammo_label: Label = null
var _nades_label: Label = null
var _prompt_label: Label = null
var _progress_bar: ProgressBar = null
var _banner_panel: PanelContainer = null
var _banner_title: Label = null
var _banner_sub: Label = null
var _killfeed_box: VBoxContainer = null
var _fps_label: Label = null

var _banner_timer: float = 0.0


func _ready() -> void:
	layer = 10
	_build_hud()
	MatchManager.round_started.connect(_on_round_started)
	MatchManager.round_ended.connect(_on_round_ended)
	MatchManager.match_ended.connect(_on_match_ended)
	MatchManager.kill_feed_added.connect(_on_kill_feed)
	MatchManager.bomb_planted_event.connect(_on_bomb_planted)
	MatchManager.bomb_defused_event.connect(_on_bomb_defused)


func bind_player(p: PlayerController) -> void:
	player = p
	crosshair.player = p
	radar.player = p
	p.damaged_enemy.connect(func(_dmg: float, hs: bool, _k: bool) -> void: crosshair.notify_hit(hs))
	p.hit_taken.connect(func(from_p: Vector3, _amt: float) -> void: crosshair.notify_damage_from(from_p))


func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	crosshair = CrosshairOverlay.new()
	root.add_child(crosshair)

	# Radar arriba izquierda
	var radar_box := VBoxContainer.new()
	radar_box.position = Vector2(18, 18)
	radar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radar_box)

	_location_label = Label.new()
	_location_label.text = "DUST II"
	_location_label.add_theme_font_size_override("font_size", 14)
	_location_label.modulate = Color(0.92, 0.94, 0.98)
	radar_box.add_child(_location_label)

	radar = RadarOverlay.new()
	radar.custom_minimum_size = Vector2(210, 210)
	radar_box.add_child(radar)

	var econ_row := HBoxContainer.new()
	econ_row.add_theme_constant_override("separation", 12)
	radar_box.add_child(econ_row)

	_money_label = Label.new()
	_money_label.text = "$800"
	_money_label.add_theme_font_size_override("font_size", 22)
	_money_label.modulate = Color(0.45, 0.95, 0.45)
	econ_row.add_child(_money_label)

	_c4_badge = Label.new()
	_c4_badge.text = "[C4]"
	_c4_badge.visible = false
	_c4_badge.add_theme_font_size_override("font_size", 18)
	_c4_badge.modulate = Color(1.0, 0.72, 0.18)
	econ_row.add_child(_c4_badge)

	# Barra superior central (marcador + reloj)
	var top_bar := PanelContainer.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top_bar.offset_top = 14
	top_bar.offset_left = -165
	top_bar.offset_right = 165
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = Color(0.05, 0.07, 0.10, 0.75)
	top_sb.set_corner_radius_all(4)
	top_sb.set_content_margin_all(8)
	top_bar.add_theme_stylebox_override("panel", top_sb)
	root.add_child(top_bar)

	var top_vbox := VBoxContainer.new()
	top_bar.add_child(top_vbox)

	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 18)
	top_vbox.add_child(score_row)

	_top_ct_label = Label.new()
	_top_ct_label.text = "CT 0"
	_top_ct_label.add_theme_font_size_override("font_size", 20)
	_top_ct_label.modulate = Color(0.45, 0.78, 1.0)
	score_row.add_child(_top_ct_label)

	_timer_label = Label.new()
	_timer_label.text = "01:55"
	_timer_label.add_theme_font_size_override("font_size", 22)
	score_row.add_child(_timer_label)

	_top_t_label = Label.new()
	_top_t_label.text = "0 T"
	_top_t_label.add_theme_font_size_override("font_size", 20)
	_top_t_label.modulate = Color(0.98, 0.72, 0.28)
	score_row.add_child(_top_t_label)

	_phase_label = Label.new()
	_phase_label.horizontal = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 12)
	_phase_label.modulate = Color(0.78, 0.82, 0.88)
	top_vbox.add_child(_phase_label)

	# Killfeed arriba derecha
	_killfeed_box = VBoxContainer.new()
	_killfeed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_killfeed_box.offset_left = -400
	_killfeed_box.offset_top = 18
	_killfeed_box.offset_right = -18
	_killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_killfeed_box.add_theme_constant_override("separation", 4)
	root.add_child(_killfeed_box)

	_fps_label = Label.new()
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.offset_left = -130
	_fps_label.offset_top = 4
	_fps_label.offset_right = -18
	_fps_label.horizontal = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.modulate = Color(0.7, 0.9, 0.7, 0.8)
	root.add_child(_fps_label)

	# Salud & Armadura abajo izquierda
	var bot_left := PanelContainer.new()
	bot_left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bot_left.offset_left = 18
	bot_left.offset_bottom = -18
	bot_left.offset_top = -86
	bot_left.offset_right = 270
	bot_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot_left.add_theme_stylebox_override("panel", top_sb)
	root.add_child(bot_left)

	var bl_hbox := HBoxContainer.new()
	bl_hbox.add_theme_constant_override("separation", 18)
	bot_left.add_child(bl_hbox)

	_hp_label = Label.new()
	_hp_label.text = "+ 100"
	_hp_label.add_theme_font_size_override("font_size", 30)
	bl_hbox.add_child(_hp_label)

	_armor_label = Label.new()
	_armor_label.text = "ARM 0"
	_armor_label.add_theme_font_size_override("font_size", 22)
	_armor_label.modulate = Color(0.65, 0.85, 1.0)
	bl_hbox.add_child(_armor_label)

	# Munición & Armas abajo derecha
	var bot_right := PanelContainer.new()
	bot_right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bot_right.offset_right = -18
	bot_right.offset_bottom = -18
	bot_right.offset_left = -350
	bot_right.offset_top = -102
	bot_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot_right.add_theme_stylebox_override("panel", top_sb)
	root.add_child(bot_right)

	var br_vbox := VBoxContainer.new()
	bot_right.add_child(br_vbox)

	var br_top := HBoxContainer.new()
	br_top.add_theme_constant_override("separation", 12)
	br_vbox.add_child(br_top)

	_weapon_label = Label.new()
	_weapon_label.text = "USP-S"
	_weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_label.add_theme_font_size_override("font_size", 18)
	br_top.add_child(_weapon_label)

	_ammo_label = Label.new()
	_ammo_label.text = "12 / 24"
	_ammo_label.add_theme_font_size_override("font_size", 28)
	br_top.add_child(_ammo_label)

	_nades_label = Label.new()
	_nades_label.text = ""
	_nades_label.add_theme_font_size_override("font_size", 13)
	_nades_label.modulate = Color(0.84, 0.88, 0.94)
	br_vbox.add_child(_nades_label)

	# Prompt contextual + barra de plantar/desactivar centro inferior
	var center_bot := VBoxContainer.new()
	center_bot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	center_bot.offset_left = -210
	center_bot.offset_right = 210
	center_bot.offset_top = -145
	center_bot.offset_bottom = -85
	center_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_bot)

	_prompt_label = Label.new()
	_prompt_label.horizontal = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 15)
	_prompt_label.modulate = Color(1.0, 0.92, 0.55)
	center_bot.add_child(_prompt_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.visible = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	center_bot.add_child(_progress_bar)

	# Banner de ronda / match
	_banner_panel = PanelContainer.new()
	_banner_panel.visible = false
	_banner_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner_panel.offset_top = 115
	_banner_panel.offset_left = -260
	_banner_panel.offset_right = 260
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_theme_stylebox_override("panel", top_sb)
	root.add_child(_banner_panel)

	var ban_v := VBoxContainer.new()
	_banner_panel.add_child(ban_v)
	_banner_title = Label.new()
	_banner_title.horizontal = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 26)
	ban_v.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.horizontal = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_font_size_override("font_size", 15)
	ban_v.add_child(_banner_sub)

	buy_menu = BuyMenu.new()
	buy_menu.closed.connect(_sync_mouse_lock)
	root.add_child(buy_menu)

	scoreboard = ScoreboardOverlay.new()
	root.add_child(scoreboard)

	settings_panel = SettingsPanel.new()
	settings_panel.closed.connect(func() -> void: _pause_panel.visible = true)
	root.add_child(settings_panel)

	_build_pause_menu(root)


func _build_pause_menu(root: Control) -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.visible = false
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause_panel.custom_minimum_size = Vector2(340, 310)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	sb.border_color = Color(0.45, 0.65, 0.9, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(20)
	_pause_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_pause_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(v)

	var t := Label.new()
	t.text = "PAUSA"
	t.horizontal = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	v.add_child(t)

	var resume_btn := Button.new()
	resume_btn.text = "Continuar partida"
	resume_btn.pressed.connect(_close_pause)
	v.add_child(resume_btn)

	var cfg_btn := Button.new()
	cfg_btn.text = "Configuración"
	cfg_btn.pressed.connect(func() -> void:
		_pause_panel.visible = false
		settings_panel.open_panel()
	)
	v.add_child(cfg_btn)

	var team_btn := Button.new()
	team_btn.text = "Cambiar de equipo (CT / T)"
	team_btn.pressed.connect(func() -> void:
		_close_pause()
		switch_team_requested.emit()
	)
	v.add_child(team_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Volver al menú principal"
	menu_btn.pressed.connect(func() -> void:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return_to_menu_requested.emit()
	)
	v.add_child(menu_btn)


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
		if _banner_timer <= 0.0:
			_banner_panel.visible = false

	_handle_ui_shortcuts()
	_refresh_labels()


func _handle_ui_shortcuts() -> void:
	if Input.is_action_just_pressed("pause"):
		if buy_menu.visible:
			buy_menu.close_menu()
		elif settings_panel.visible:
			settings_panel.visible = false
			_pause_panel.visible = true
		elif _pause_panel.visible:
			_close_pause()
		else:
			_open_pause()
		return

	if Input.is_action_just_pressed("buy_menu") and player != null and player.alive and not _pause_panel.visible and not settings_panel.visible:
		if buy_menu.visible:
			buy_menu.close_menu()
		else:
			buy_menu.open_menu(player)
		_sync_mouse_lock()

	if Input.is_action_pressed("scoreboard") and not buy_menu.visible and not _pause_panel.visible:
		scoreboard.visible = true
		scoreboard.refresh()
	else:
		scoreboard.visible = false

	# Radar expandido al mantener M
	if radar != null:
		var target_sz: Vector2 = Vector2(440, 440) if radar.full_map_held else Vector2(210, 210)
		radar.custom_minimum_size = target_sz
		radar.size = target_sz


func _open_pause() -> void:
	_pause_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_sync_mouse_lock()


func _close_pause() -> void:
	_pause_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_sync_mouse_lock()


func _sync_mouse_lock() -> void:
	if player != null:
		player.input_locked = buy_menu.visible or _pause_panel.visible or settings_panel.visible


func _refresh_labels() -> void:
	_fps_label.visible = SettingsManager.show_fps
	if SettingsManager.show_fps:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	var alive_ct: int = 0
	var alive_t: int = 0
	for c in MatchManager.combatants:
		if c != null and is_instance_valid(c) and c.alive:
			if c.team == "ct":
				alive_ct += 1
			else:
				alive_t += 1

	_top_ct_label.text = "CT %d (%d)" % [MatchManager.score_ct, alive_ct]
	_top_t_label.text = "(%d) %d T" % [alive_t, MatchManager.score_t]

	if MatchManager.bomb_planted:
		_timer_label.text = "C4  %.1f" % maxf(0.0, MatchManager.bomb_timer)
		_timer_label.modulate = Color(1.0, 0.25, 0.25)
	else:
		var t_sec: int = maxi(0, int(ceil(MatchManager.phase_timer)))
		_timer_label.text = "%02d:%02d" % [int(t_sec / 60), t_sec % 60]
		_timer_label.modulate = Color(0.95, 0.85, 0.35) if MatchManager.is_frozen() else Color.WHITE

	if MatchManager.mode == "deathmatch":
		var bw: Dictionary = GameData.get_weapon(MatchManager.dm_bonus_weapon)
		_phase_label.text = "DM | Bonus (+5 pts): %s (%.0fs)" % [str(bw.get("name", "")), MatchManager.dm_bonus_timer]
	elif MatchManager.is_frozen():
		_phase_label.text = "TIEMPO CONGELADO - COMPRA [B]"
	else:
		_phase_label.text = "RONDA %d  |  %s" % [MatchManager.round_number, MatchManager.mode.to_upper()]

	if player == null or not is_instance_valid(player):
		return

	_location_label.text = GameData.triggers.callout_at(player.global_position).to_upper()
	_money_label.text = "$%d" % player.money
	_c4_badge.visible = player.has_c4

	_hp_label.text = "+ %d" % int(ceil(player.health))
	_hp_label.modulate = Color(1.0, 0.28, 0.28) if player.health <= 25.0 else Color.WHITE
	var kit_str: String = "  [KIT]" if player.has_defuse_kit else ""
	var helm_str: String = "+" if player.has_helmet else ""
	_armor_label.text = "ARM%s %d%s" % [helm_str, int(ceil(player.armor)), kit_str]

	if player.active_slot == 4:
		_weapon_label.text = "GRANADA: %s" % player.active_grenade.to_upper()
		_ammo_label.text = "x%d" % int(player.grenades.get(player.active_grenade, 0))
	elif player.active_slot == 5:
		_weapon_label.text = "EXPLOSIVO C4"
		_ammo_label.text = "[LMB]"
	elif player.active_slot == 3:
		_weapon_label.text = "CUCHILLO BAYONETA"
		_ammo_label.text = "--"
	else:
		var wid: int = player.get_active_weapon_id()
		var w: Dictionary = GameData.get_weapon(wid)
		var ammo_v: Vector2i = player.get_active_ammo()
		_weapon_label.text = str(w.get("name", "Arma"))
		_ammo_label.text = "%d / %d" % [ammo_v.x, ammo_v.y]

	var nade_parts: Array[String] = []
	for k in GrenadeMath.GRENADE_TYPES:
		var cnt: int = int(player.grenades.get(k, 0))
		if cnt > 0:
			nade_parts.append("%s:%d" % [k.to_upper().substr(0, 3), cnt])
	if player.has_healthshot:
		nade_parts.append("[X] HEAL")
	_nades_label.text = "  |  ".join(nade_parts)

	# Prompts y barra de C4
	_progress_bar.visible = false
	_prompt_label.text = ""
	if player.is_planting:
		_prompt_label.text = "PLANTANDO C4..."
		_progress_bar.visible = true
		_progress_bar.value = clampf(player.plant_progress / 3.2, 0.0, 1.0)
	elif player.is_defusing:
		_prompt_label.text = "DESACTIVANDO C4..."
		_progress_bar.visible = true
		_progress_bar.value = clampf(player.defuse_progress / (5.0 if player.has_defuse_kit else 10.0), 0.0, 1.0)
	elif not player.alive:
		_prompt_label.text = "ELIMINADO — Reaparición / Siguiente ronda en breve"
	else:
		var in_zone: bool = GameData.triggers.in_buy_zone(player.global_position, player.team, MovementMath.HULL_RADIUS, 1.8)
		if MatchManager.is_buy_allowed(in_zone):
			_prompt_label.text = "Pulsa [B] para abrir Menú de Compra"
		elif player.team == "ct" and MatchManager.bomb_planted and player.global_position.distance_to(MatchManager.bomb_position) <= 2.35:
			_prompt_label.text = "Mantén [E] para desactivar C4"
		elif player.team == "t" and player.has_c4 and not MatchManager.bomb_planted:
			var site: int = GameData.triggers.bomb_site_at(player.global_position, MovementMath.HULL_RADIUS, 1.8)
			if site >= 0:
				_prompt_label.text = "Pulsa [5] + Mantén [Click Izq / E] para plantar C4"


func _on_round_started(round_num: int) -> void:
	_show_banner("RONDA %d" % round_num, "%s — Prepárate y compra [B]" % MatchManager.mode.to_upper(), 3.0)


func _on_round_ended(winner: String, reason: String, mvp: String) -> void:
	var title: String = "GANAN LOS COUNTER-TERRORISTS" if winner == "ct" else "GANAN LOS TERRORISTS"
	var reason_es: String = reason
	match reason:
		"bomb":
			reason_es = "Objetivo destruido"
		"defuse":
			reason_es = "Bomba desactivada"
		"time":
			reason_es = "Tiempo agotado"
		"elimination":
			reason_es = "Equipo enemigo eliminado"
	var sub: String = reason_es if mvp.is_empty() else "%s  |  MVP: %s" % [reason_es, mvp]
	_show_banner(title, sub, 4.5)


func _on_match_ended(winner: String) -> void:
	var title: String = "VICTORIA CT (%d - %d)" % [MatchManager.score_ct, MatchManager.score_t] if winner == "ct" else "VICTORIA T (%d - %d)" % [MatchManager.score_t, MatchManager.score_ct]
	_show_banner(title, "Partida finalizada — Pulsa ESC para volver al menú", 8.0)


func _on_bomb_planted(site_idx: int, _pos: Vector3) -> void:
	_show_banner("BOMBA PLANTADA EN SITIO %s" % ("A" if site_idx == 0 else "B"), "40 segundos para la detonación", 3.5)


func _on_bomb_defused(defuser_name: String) -> void:
	_show_banner("BOMBA DESACTIVADA", "Desactivada por %s" % defuser_name, 3.5)


func _show_banner(title: String, sub: String, duration: float) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	_banner_panel.visible = true
	_banner_timer = duration


func _on_kill_feed(_entry: Dictionary) -> void:
	for c in _killfeed_box.get_children():
		c.queue_free()
	for e in MatchManager.kill_feed:
		var lbl := Label.new()
		var hs_tag: String = " [HS]" if bool(e.get("headshot", false)) else ""
		var pen_tag: String = " [WB]" if bool(e.get("penetrated", false)) else ""
		var w_name: String = str(GameData.get_weapon(int(e.get("weapon_id", 0))).get("name", ""))
		lbl.text = "%s  [%s%s%s]  %s" % [
			str(e.get("killer", "")),
			w_name,
			hs_tag,
			pen_tag,
			str(e.get("victim", "")),
		]
		lbl.horizontal = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.modulate = Color(0.55, 0.84, 1.0) if str(e.get("killer_team", "")) == "ct" else Color(1.0, 0.78, 0.38)
		_killfeed_box.add_child(lbl)
