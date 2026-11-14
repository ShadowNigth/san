class_name MatchScene
extends Node3D

var world: Dust2World = null
var player: PlayerController = null
var hud: GameHUD = null
var bots: Array[BotController] = []


func _ready() -> void:
	world = Dust2World.new()
	world.name = "World"
	add_child(world)

	hud = GameHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.return_to_menu_requested.connect(_on_return_to_menu)
	hud.switch_team_requested.connect(_on_switch_team)

	MatchManager.round_started.connect(_on_round_started)
	MatchManager.bomb_exploded_event.connect(_on_bomb_exploded)

	_start_match(SettingsManager.chosen_mode, SettingsManager.chosen_team)


func _start_match(mode: String, p_team: String) -> void:
	_clear_actors()
	MatchManager.configure_match(mode, p_team)
	var rules: Dictionary = MatchManager.get_rules()
	var team_size: int = int(rules.get("team_size", 5))
	var start_money: int = int(rules.get("start_money", 800))

	player = PlayerController.new()
	player.name = "LocalPlayer"
	player.team = p_team
	player.world_ref = world
	player.money = start_money
	player.secondary_id = 2 if p_team == "ct" else 7
	add_child(player)
	hud.bind_player(player)

	# Bots en ambos equipos
	var ct_bots: int = team_size - (1 if p_team == "ct" else 0)
	var t_bots: int = team_size - (1 if p_team == "t" else 0)

	for i in range(ct_bots):
		var b := BotController.new()
		b.name = "Bot_CT_%d" % i
		b.setup_bot(i, "ct", world)
		b.money = start_money
		b.secondary_id = 2
		add_child(b)
		bots.append(b)

	for i in range(t_bots):
		var b := BotController.new()
		b.name = "Bot_T_%d" % i
		b.setup_bot(i, "t", world)
		b.money = start_money
		b.secondary_id = 7
		add_child(b)
		bots.append(b)

	_on_round_started(MatchManager.round_number)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _clear_actors() -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
		player = null
	for b in bots:
		if b != null and is_instance_valid(b):
			b.queue_free()
	bots.clear()


func _physics_process(delta: float) -> void:
	MatchManager.tick(delta)


func _on_round_started(_round_num: int) -> void:
	if world != null:
		world.clear_round_props()

	var ct_list: Array[CombatantBase] = []
	var t_list: Array[CombatantBase] = []
	for c in MatchManager.combatants:
		if c == null or not is_instance_valid(c):
			continue
		if c.team == "ct":
			ct_list.append(c as CombatantBase)
		else:
			t_list.append(c as CombatantBase)

	var c4_carrier_idx: int = randi() % t_list.size() if not t_list.is_empty() else -1
	if MatchManager.mode == "deathmatch":
		c4_carrier_idx = -1

	for i in range(ct_list.size()):
		var sp: Vector3 = GameData.nav.get_spawn_position("ct", i)
		var sy: float = GameData.nav.get_spawn_yaw("ct", i)
		ct_list[i].reset_for_round(sp, sy, false)

	for i in range(t_list.size()):
		var sp: Vector3 = GameData.nav.get_spawn_position("t", i)
		var sy: float = GameData.nav.get_spawn_yaw("t", i)
		t_list[i].reset_for_round(sp, sy, i == c4_carrier_idx)


func _on_bomb_exploded(pos: Vector3) -> void:
	if world != null:
		world.trigger_c4_explosion(pos)


func _on_switch_team() -> void:
	var new_team: String = "t" if SettingsManager.chosen_team == "ct" else "ct"
	SettingsManager.chosen_team = new_team
	SettingsManager.save_settings()
	_start_match(SettingsManager.chosen_mode, new_team)


func _on_return_to_menu() -> void:
	AudioManager.stop_music()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
