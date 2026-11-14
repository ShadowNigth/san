class_name SettingsPanel
extends PanelContainer

signal closed

var _sens_slider: HSlider = null
var _sens_val: Label = null
var _fov_slider: HSlider = null
var _fov_val: Label = null
var _vol_master: HSlider = null
var _vol_sfx: HSlider = null
var _vol_music: HSlider = null
var _dyn_ch: CheckButton = null
var _dot_ch: CheckButton = null
var _diff_opt: OptionButton = null


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(560, 480)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.12, 0.96)
	sb.border_color = Color(0.42, 0.62, 0.85, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(20)
	add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var title := Label.new()
	title.text = "CONFIGURACIÓN"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_sens_val = Label.new()
	_sens_slider = _add_slider(vbox, "Sensibilidad del ratón", 0.3, 5.0, 0.05, SettingsManager.sensitivity, _sens_val)

	_fov_val = Label.new()
	_fov_slider = _add_slider(vbox, "Campo de visión (FOV)", 70.0, 110.0, 1.0, SettingsManager.fov, _fov_val)

	_vol_master = _add_slider(vbox, "Volumen Maestro", 0.0, 1.0, 0.05, SettingsManager.master_volume, null)
	_vol_sfx = _add_slider(vbox, "Volumen Efectos (SFX)", 0.0, 1.0, 0.05, SettingsManager.sfx_volume, null)
	_vol_music = _add_slider(vbox, "Volumen Música", 0.0, 1.0, 0.05, SettingsManager.music_volume, null)

	_dyn_ch = CheckButton.new()
	_dyn_ch.text = "Mira dinámica (expande con movimiento y retroceso)"
	_dyn_ch.button_pressed = SettingsManager.crosshair_dynamic
	vbox.add_child(_dyn_ch)

	_dot_ch = CheckButton.new()
	_dot_ch.text = "Punto central en la mira"
	_dot_ch.button_pressed = SettingsManager.crosshair_dot
	vbox.add_child(_dot_ch)

	var diff_row := HBoxContainer.new()
	var diff_lbl := Label.new()
	diff_lbl.text = "Dificultad de Bots:"
	diff_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_row.add_child(diff_lbl)
	_diff_opt = OptionButton.new()
	_diff_opt.add_item("Fácil", 0)
	_diff_opt.add_item("Normal", 1)
	_diff_opt.add_item("Difícil", 2)
	_diff_opt.add_item("Experto", 3)
	_diff_opt.selected = clampi(SettingsManager.bot_difficulty, 0, 3)
	diff_row.add_child(_diff_opt)
	vbox.add_child(diff_row)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.pressed.connect(func() -> void:
		visible = false
		closed.emit()
	)
	btn_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "Guardar y Aplicar"
	save_btn.pressed.connect(_apply_and_close)
	btn_row.add_child(save_btn)


func _add_slider(
	parent: VBoxContainer,
	label_text: String,
	min_v: float,
	max_v: float,
	step_v: float,
	init_v: float,
	value_lbl: Label
) -> HSlider:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	if value_lbl != null:
		value_lbl.text = "%.2f" % init_v
		row.add_child(value_lbl)
	parent.add_child(row)

	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.value = init_v
	if value_lbl != null:
		s.value_changed.connect(func(v: float) -> void: value_lbl.text = "%.2f" % v)
	parent.add_child(s)
	return s


func open_panel() -> void:
	_sens_slider.value = SettingsManager.sensitivity
	_fov_slider.value = SettingsManager.fov
	_vol_master.value = SettingsManager.master_volume
	_vol_sfx.value = SettingsManager.sfx_volume
	_vol_music.value = SettingsManager.music_volume
	_dyn_ch.button_pressed = SettingsManager.crosshair_dynamic
	_dot_ch.button_pressed = SettingsManager.crosshair_dot
	_diff_opt.selected = clampi(SettingsManager.bot_difficulty, 0, 3)
	visible = true


func _apply_and_close() -> void:
	SettingsManager.sensitivity = _sens_slider.value
	SettingsManager.fov = _fov_slider.value
	SettingsManager.master_volume = _vol_master.value
	SettingsManager.sfx_volume = _vol_sfx.value
	SettingsManager.music_volume = _vol_music.value
	SettingsManager.crosshair_dynamic = _dyn_ch.button_pressed
	SettingsManager.crosshair_dot = _dot_ch.button_pressed
	SettingsManager.bot_difficulty = _diff_opt.selected
	SettingsManager.save_settings()
	visible = false
	closed.emit()
