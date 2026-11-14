class_name BuyMenu
extends PanelContainer

signal closed

var player: PlayerController = null
var _money_label: Label = null
var _status_label: Label = null
var _columns_box: HBoxContainer = null
var _last_buy: Array = []


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(1060, 560)
	_build_ui()


func _build_ui() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.08, 0.11, 0.94)
	bg.border_color = Color(0.32, 0.56, 0.82, 0.65)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(18)
	add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "MENÚ DE COMPRA  [B / ESC para cerrar]"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_money_label = Label.new()
	_money_label.text = "$800"
	_money_label.add_theme_font_size_override("font_size", 24)
	_money_label.modulate = Color(0.45, 0.95, 0.45)
	header.add_child(_money_label)

	var rebuy_btn := Button.new()
	rebuy_btn.text = "Recomprar anterior"
	rebuy_btn.pressed.connect(_on_rebuy)
	header.add_child(rebuy_btn)

	var close_btn := Button.new()
	close_btn.text = "Cerrar"
	close_btn.pressed.connect(close_menu)
	header.add_child(close_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.modulate = Color(0.85, 0.85, 0.9)
	vbox.add_child(_status_label)

	_columns_box = HBoxContainer.new()
	_columns_box.add_theme_constant_override("separation", 12)
	_columns_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_columns_box)


func open_menu(p_player: PlayerController) -> void:
	player = p_player
	rebuild()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	AudioManager.play_ui("ui-buy-hover", -5.0)


func close_menu() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	closed.emit()


func rebuild() -> void:
	if player == null or not is_instance_valid(player):
		return
	_money_label.text = "$%d" % player.money
	var in_zone: bool = GameData.triggers.in_buy_zone(player.global_position, player.team, MovementMath.HULL_RADIUS, 1.8)
	var allowed: bool = MatchManager.is_buy_allowed(in_zone)
	if allowed:
		_status_label.text = "Tiempo de compra restante: %.0fs  |  Equipo: %s" % [MatchManager.buy_timer, player.team.to_upper()]
	else:
		_status_label.text = "Fuera de zona o tiempo de compra terminado"

	for c in _columns_box.get_children():
		c.queue_free()

	var loadout: Dictionary = GameData.get_loadout_for_team(player.team)
	_add_equipment_column(allowed)
	_add_weapon_column("PISTOLAS", loadout["pistols"], allowed)
	_add_weapon_column("NIVEL MEDIO", loadout["mid"], allowed)
	_add_weapon_column("RIFLES", loadout["rifles"], allowed)
	_add_grenades_column(allowed)


func _make_column(title_text: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = title_text
	lbl.horizontal = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.modulate = Color(0.75, 0.85, 0.96)
	col.add_child(lbl)
	_columns_box.add_child(col)
	return col


func _add_equipment_column(allowed: bool) -> void:
	var col: VBoxContainer = _make_column("EQUIPO")
	var items: Array[Dictionary] = [
		{"kind": "vest", "name": "Chaleco Kevlar", "icon": "kevlar", "owned": player.armor >= 100.0},
		{"kind": "helmet", "name": "Chaleco + Casco", "icon": "armor_helmet", "owned": player.armor >= 100.0 and player.has_helmet},
		{"kind": "kit", "name": "Kit de Desactivación", "icon": "defuser", "owned": player.has_defuse_kit},
	]
	for it in items:
		if str(it["kind"]) == "kit" and player.team != "ct":
			continue
		var price: int = EconomySystem.equipment_price(it["kind"], player.armor, player.has_helmet)
		var owned: bool = bool(it["owned"])
		var btn := _create_item_button(
			it["name"],
			"ADQUIRIDO" if owned else "$%d" % price,
			"res://assets/icons/buy/%s.svg" % it["icon"],
			allowed and not owned and player.money >= price
		)
		btn.pressed.connect(func() -> void:
			if player.try_buy_equipment(it["kind"]):
				_record_buy("equip", it["kind"])
				rebuild()
		)
		col.add_child(btn)


func _add_weapon_column(title_text: String, ids: Array, allowed: bool) -> void:
	var col: VBoxContainer = _make_column(title_text)
	for wid_var in ids:
		var wid: int = int(wid_var)
		var w: Dictionary = GameData.get_weapon(wid)
		var price: int = 0 if MatchManager.mode == "deathmatch" else int(w.get("price", 0))
		var icon_path: String = GameData.get_buy_icon_path(str(w.get("icon", "ak-47")))
		var owned: bool = player.primary_id == wid or player.secondary_id == wid
		var sub: String = "EN USO" if owned else "$%d" % price
		var btn := _create_item_button(
			str(w.get("name", "Weapon")),
			sub,
			icon_path,
			allowed and player.money >= price
		)
		btn.pressed.connect(func() -> void:
			if player.try_buy_weapon(wid):
				_record_buy("weapon", wid)
				rebuild()
		)
		col.add_child(btn)


func _add_grenades_column(allowed: bool) -> void:
	var col: VBoxContainer = _make_column("GRANADAS")
	var specs: Array[Dictionary] = [
		{"kind": "he", "name": "Granada HE", "icon": "hegrenade"},
		{"kind": "flash", "name": "Aturdidora", "icon": "flashbang"},
		{"kind": "smoke", "name": "Granada de Humo", "icon": "smokegrenade"},
		{"kind": "molotov", "name": "Cóctel Molotov", "icon": "molotov"},
		{"kind": "incendiary", "name": "Incendiaria", "icon": "incgrenade"},
		{"kind": "decoy", "name": "Señuelo", "icon": "decoy"},
	]
	for sp in specs:
		var kind: String = sp["kind"]
		if not GrenadeMath.grenade_available(kind, player.team):
			continue
		var entry: Dictionary = GameData.utility_data.get("weapons", {}).get(kind, {})
		var price: int = int(entry.get("m_nPrice", 300))
		var count_owned: int = int(player.grenades.get(kind, 0))
		var can_carry: bool = GrenadeMath.can_carry_grenade(player.grenades, kind, MatchManager.mode != "casual")
		var btn := _create_item_button(
			"%s (%d)" % [sp["name"], count_owned],
			"$%d" % price,
			"res://assets/icons/buy/%s.svg" % sp["icon"],
			allowed and can_carry and player.money >= price
		)
		btn.pressed.connect(func() -> void:
			if player.try_buy_grenade(kind):
				_record_buy("nade", kind)
				rebuild()
		)
		col.add_child(btn)


func _create_item_button(title_text: String, price_text: String, icon_path: String, enabled: bool) -> Button:
	var btn := Button.new()
	btn.disabled = not enabled
	btn.custom_minimum_size = Vector2(180, 68)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = "%s\n%s" % [title_text, price_text]
	if ResourceLoader.exists(icon_path):
		var tex: Resource = ResourceLoader.load(icon_path)
		if tex is Texture2D:
			btn.icon = tex
			btn.expand_icon = true
	return btn


func _record_buy(kind: String, value: Variant) -> void:
	_last_buy.append({"kind": kind, "value": value})


func _on_rebuy() -> void:
	if player == null:
		return
	for entry in _last_buy:
		match entry["kind"]:
			"equip":
				player.try_buy_equipment(str(entry["value"]))
			"weapon":
				player.try_buy_weapon(int(entry["value"]))
			"nade":
				player.try_buy_grenade(str(entry["value"]))
	rebuild()
