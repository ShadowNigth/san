class_name MainMenu
extends Control

var _mode_opt: OptionButton = null
var _team_opt: OptionButton = null
var _diff_opt: OptionButton = null
var _desc_label: Label = null
var _settings_panel: SettingsPanel = null

const MODE_KEYS: Array[String] = ["competitive", "casual", "deathmatch", "practice"]
const MODE_DESCS: Dictionary = {
	"competitive": "5v5 | Economía $800-$16k | 24 rondas con cambio de bando | Fuego amigo activo | Compra manual de chaleco y kit.",
	"casual": "10v10 | Economía $1000-$10k | 15 rondas | Armadura y kit gratuitos | Sin fuego amigo.",
	"deathmatch": "Todos contra todos por equipos | Arma bonus cada 30s (+5 pts) | Healthshot cada 3 bajas | Reaparición instantánea.",
	"practice": "3v3 Práctica | $16,000 constantes | Compra en cualquier lugar | Ideal para probar movimiento, recoil, humos y granadas.",
}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Fondo sutil con radar de Dust II
	var radar_bg := TextureRect.new()
	radar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	radar_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	radar_bg.modulate = Color(1.0, 1.0, 1.0, 0.14)
	if ResourceLoader.exists("res://assets/textures/dust2_radar.png"):
		var tex: Resource = ResourceLoader.load("res://assets/textures/dust2_radar.png")
		if tex is Texture2D:
			radar_bg.texture = tex
	add_child(radar_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(920, 560)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.92)
	sb.border_color = Color(0.36, 0.62, 0.90, 0.72)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 18)
	card.add_child(root_v)

	var title := Label.new()
	title.text = "CS2GO — PORT A GODOT 4 (GDSCRIPT)"
	title.add_theme_font_size_override("font_size", 32)
	title.modulate = Color(0.95, 0.97, 1.0)
	root_v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Simulación a 128 Hz | Movimiento Source | 37 Armas con Balística y Penetración | Dust II | Bots Tácticos"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.modulate = Color(0.68, 0.78, 0.92)
	root_v.add_child(subtitle)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(columns)

	# Columna izquierda: configuración de partida
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 12)
	columns.add_child(left_col)

	var mode_lbl := Label.new()
	mode_lbl.text = "Modo de Juego:"
	left_col.add_child(mode_lbl)
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("Competitivo (5v5)", 0)
	_mode_opt.add_item("Casual (10v10)", 1)
	_mode_opt.add_item("Deathmatch", 2)
	_mode_opt.add_item("Práctica (3v3)", 3)
	_mode_opt.selected = maxi(0, MODE_KEYS.find(SettingsManager.chosen_mode))
	_mode_opt.item_selected.connect(_on_mode_changed)
	left_col.add_child(_mode_opt)

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(360, 54)
	_desc_label.modulate = Color(0.82, 0.86, 0.92)
	left_col.add_child(_desc_label)
	_on_mode_changed(_mode_opt.selected)

	var team_lbl := Label.new()
	team_lbl.text = "Equipo inicial:"
	left_col.add_child(team_lbl)
	_team_opt = OptionButton.new()
	_team_opt.add_item("Counter-Terrorists (CT)", 0)
	_team_opt.add_item("Terrorists (T)", 1)
	_team_opt.selected = 0 if SettingsManager.chosen_team == "ct" else 1
	left_col.add_child(_team_opt)

	var diff_lbl := Label.new()
	diff_lbl.text = "Dificultad de Bots:"
	left_col.add_child(diff_lbl)
	_diff_opt = OptionButton.new()
	_diff_opt.add_item("Fácil", 0)
	_diff_opt.add_item("Normal", 1)
	_diff_opt.add_item("Difícil", 2)
	_diff_opt.add_item("Experto", 3)
	_diff_opt.selected = clampi(SettingsManager.bot_difficulty, 0, 3)
	left_col.add_child(_diff_opt)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(spacer)

	var play_btn := Button.new()
	play_btn.text = "JUGAR EN DE_DUST2"
	play_btn.custom_minimum_size = Vector2(0, 54)
	play_btn.add_theme_font_size_override("font_size", 20)
	play_btn.pressed.connect(_on_play_pressed)
	left_col.add_child(play_btn)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 10)
	left_col.add_child(actions_row)

	var cfg_btn := Button.new()
	cfg_btn.text = "Configuración"
	cfg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cfg_btn.pressed.connect(func() -> void: _settings_panel.open_panel())
	actions_row.add_child(cfg_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Salir"
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	actions_row.add_child(quit_btn)

	# Columna derecha: controles y mapa
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 10)
	columns.add_child(right_col)

	var ctrl_title := Label.new()
	ctrl_title.text = "CONTROLES CLAVE"
	ctrl_title.add_theme_font_size_override("font_size", 16)
	ctrl_title.modulate = Color(0.45, 0.78, 1.0)
	right_col.add_child(ctrl_title)

	var ctrl_info := Label.new()
	ctrl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl_info.text = (
		"WASD: Movimiento Source (air-strafing 128Hz)\n"
		+ "Shift / Ctrl / Espacio: Caminar / Agacharse / Saltar\n"
		+ "Click Izq / Click Der: Disparar / Mira-Silenciador-Ráfaga-Estocada\n"
		+ "1..5 / Q: Primaria / Secundaria / Cuchillo / Granadas / C4 / Anterior\n"
		+ "R / G / F / X: Recargar / Soltar arma / Inspeccionar / Healthshot\n"
		+ "E: Plantar o Desactivar C4\n"
		+ "B: Menú de Compra  |  Tab: Marcador  |  H / M: Zoom / Mapa completo"
	)
	ctrl_info.add_theme_font_size_override("font_size", 14)
	ctrl_info.modulate = Color(0.86, 0.90, 0.96)
	right_col.add_child(ctrl_info)

	_settings_panel = SettingsPanel.new()
	_settings_panel.closed.connect(func() -> void:
		_diff_opt.selected = clampi(SettingsManager.bot_difficulty, 0, 3)
	)
	add_child(_settings_panel)


func _on_mode_changed(idx: int) -> void:
	var key: String = MODE_KEYS[clampi(idx, 0, MODE_KEYS.size() - 1)]
	_desc_label.text = str(MODE_DESCS.get(key, ""))


func _on_play_pressed() -> void:
	SettingsManager.chosen_mode = MODE_KEYS[clampi(_mode_opt.selected, 0, MODE_KEYS.size() - 1)]
	SettingsManager.chosen_team = "ct" if _team_opt.selected == 0 else "t"
	SettingsManager.bot_difficulty = clampi(_diff_opt.selected, 0, 3)
	SettingsManager.save_settings()
	AudioManager.play_ui("ui-play", -4.0)
	get_tree().change_scene_to_file("res://scenes/Dust2Match.tscn")
