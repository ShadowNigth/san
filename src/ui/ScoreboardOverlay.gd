class_name ScoreboardOverlay
extends PanelContainer

var _header_label: Label = null
var _ct_list: VBoxContainer = null
var _t_list: VBoxContainer = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(820, 480)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.88)
	sb.border_color = Color(0.45, 0.55, 0.70, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	add_child(root_box)

	_header_label = Label.new()
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 20)
	root_box.add_child(_header_label)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(split)

	var ct_col := VBoxContainer.new()
	ct_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ct_title := Label.new()
	ct_title.text = "COUNTER-TERRORISTS"
	ct_title.modulate = Color(0.42, 0.76, 1.0)
	ct_title.add_theme_font_size_override("font_size", 16)
	ct_col.add_child(ct_title)
	_ct_list = VBoxContainer.new()
	ct_col.add_child(_ct_list)
	split.add_child(ct_col)

	var t_col := VBoxContainer.new()
	t_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t_title := Label.new()
	t_title.text = "TERRORISTS"
	t_title.modulate = Color(0.98, 0.72, 0.28)
	t_title.add_theme_font_size_override("font_size", 16)
	t_col.add_child(t_title)
	_t_list = VBoxContainer.new()
	t_col.add_child(_t_list)
	split.add_child(t_col)


func refresh() -> void:
	_header_label.text = "DE_DUST2  |  %s  |  RONDA %d  |  CT %d : %d T" % [
		MatchManager.mode.to_upper(),
		MatchManager.round_number,
		MatchManager.score_ct,
		MatchManager.score_t,
	]

	for c in _ct_list.get_children():
		c.queue_free()
	for c in _t_list.get_children():
		c.queue_free()

	var ct_rows: Array = []
	var t_rows: Array = []
	for actor in MatchManager.combatants:
		if actor == null or not is_instance_valid(actor):
			continue
		if actor.team == "ct":
			ct_rows.append(actor)
		else:
			t_rows.append(actor)

	ct_rows.sort_custom(func(a: Variant, b: Variant) -> bool: return a.score > b.score)
	t_rows.sort_custom(func(a: Variant, b: Variant) -> bool: return a.score > b.score)

	_populate_rows(_ct_list, ct_rows)
	_populate_rows(_t_list, t_rows)


func _populate_rows(container: VBoxContainer, actors: Array) -> void:
	var hdr := Label.new()
	hdr.text = "%-18s %4s %4s %5s %7s" % ["NOMBRE", "K", "D", "PTS", "DINERO"]
	hdr.modulate = Color(0.68, 0.72, 0.78)
	hdr.add_theme_font_size_override("font_size", 13)
	container.add_child(hdr)

	for a in actors:
		var lbl := Label.new()
		var state_tag: String = "" if a.alive else " [M]"
		var name_str: String = (a.display_name + state_tag).substr(0, 18)
		lbl.text = "%-18s %4d %4d %5d $%6d" % [name_str, a.kills, a.deaths, a.score, a.money]
		lbl.add_theme_font_size_override("font_size", 14)
		if a.is_local_player:
			lbl.modulate = Color(1.0, 0.96, 0.45)
		elif not a.alive:
			lbl.modulate = Color(0.55, 0.55, 0.58)
		container.add_child(lbl)
