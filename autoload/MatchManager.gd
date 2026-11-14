extends Node

signal state_updated
signal round_started(round_num: int)
signal round_ended(winner: String, reason: String, mvp_name: String)
signal match_ended(winner: String)
signal kill_feed_added(entry: Dictionary)
signal bomb_planted_event(site_idx: int, pos: Vector3)
signal bomb_defused_event(defuser_name: String)
signal bomb_exploded_event(pos: Vector3)
signal dm_bonus_changed(weapon_id: int, time_left: float)

enum Phase { FREEZE, LIVE, ROUND_END, MATCH_END }

var mode: String = "competitive"
var player_team: String = "ct"
var phase: Phase = Phase.FREEZE
var round_number: int = 1
var score_ct: int = 0
var score_t: int = 0
var loss_level_ct: int = 1
var loss_level_t: int = 1
var phase_timer: float = 8.0
var buy_timer: float = 20.0
var match_elapsed: float = 0.0

var bomb_planted: bool = false
var bomb_site: int = -1
var bomb_position := Vector3.ZERO
var bomb_timer: float = 40.0
var bomb_defusing: bool = false
var bomb_defuse_progress: float = 0.0
var bomb_defuse_duration: float = 10.0

# Deathmatch bonus weapon
var dm_bonus_weapon: int = 0
var dm_bonus_timer: float = 30.0

# Roster de participantes (PlayerController / BotController o diccionarios de estado)
var combatants: Array = []
var kill_feed: Array[Dictionary] = []
var round_damage: Dictionary = {}
var round_kills: Dictionary = {}

var _rules: Dictionary = {}
var _halftime_swapped: bool = false


func configure_match(new_mode: String, team: String) -> void:
	mode = new_mode
	player_team = team
	_rules = EconomySystem.rules_for(mode)
	round_number = 1
	score_ct = 0
	score_t = 0
	loss_level_ct = int(_rules.get("starting_loss_level", 0))
	loss_level_t = int(_rules.get("starting_loss_level", 0))
	_halftime_swapped = false
	kill_feed.clear()
	combatants.clear()
	match_elapsed = 0.0
	if mode == "deathmatch":
		_pick_next_dm_bonus()
	start_round(true)


func register_combatant(actor: Node) -> void:
	if not combatants.has(actor):
		combatants.append(actor)


func get_rules() -> Dictionary:
	return _rules


func is_buy_allowed(in_zone: bool) -> bool:
	if mode == "deathmatch":
		return true
	if phase == Phase.ROUND_END or phase == Phase.MATCH_END:
		return false
	return buy_timer > 0.0 and (in_zone or mode == "practice")


func is_frozen() -> bool:
	return phase == Phase.FREEZE


func start_round(is_first: bool = false) -> void:
	bomb_planted = false
	bomb_site = -1
	bomb_timer = 40.0
	bomb_defusing = false
	bomb_defuse_progress = 0.0
	round_damage.clear()
	round_kills.clear()

	if not is_first and mode == "competitive" and round_number == 13 and not _halftime_swapped:
		_halftime_swapped = true
		var tmp_score: int = score_ct
		score_ct = score_t
		score_t = tmp_score
		loss_level_ct = int(_rules.get("starting_loss_level", 1))
		loss_level_t = int(_rules.get("starting_loss_level", 1))
		player_team = "t" if player_team == "ct" else "ct"
		for c in combatants:
			if c != null and is_instance_valid(c):
				c.swap_team_halftime()

	var freeze_t: float = float(_rules.get("freeze_time", 5.0))
	phase = Phase.FREEZE if freeze_t > 0.0 else Phase.LIVE
	phase_timer = freeze_t if phase == Phase.FREEZE else float(_rules.get("round_time", 115.2))
	buy_timer = float(_rules.get("buy_time", 20.0))
	round_started.emit(round_number)
	state_updated.emit()


func tick(dt: float) -> void:
	match_elapsed += dt
	if buy_timer > 0.0 and phase != Phase.ROUND_END:
		buy_timer = maxf(0.0, buy_timer - dt)

	if mode == "deathmatch":
		dm_bonus_timer -= dt
		if dm_bonus_timer <= 0.0:
			_pick_next_dm_bonus()
		dm_bonus_changed.emit(dm_bonus_weapon, dm_bonus_timer)

	if phase == Phase.FREEZE:
		phase_timer -= dt
		if phase_timer <= 0.0:
			phase = Phase.LIVE
			phase_timer = float(_rules.get("round_time", 115.2))
			AudioManager.play_ui("ui-go", -4.0)
			state_updated.emit()
	elif phase == Phase.LIVE:
		if bomb_planted:
			bomb_timer -= dt
			if bomb_timer <= 0.0:
				bomb_exploded_event.emit(bomb_position)
				_finish_round("t", "bomb")
				return
		else:
			phase_timer -= dt
			if phase_timer <= 0.0:
				if mode == "deathmatch":
					_finish_deathmatch()
				else:
					_finish_round("ct", "time")
				return
		_check_elimination_win()
	elif phase == Phase.ROUND_END:
		phase_timer -= dt
		if phase_timer <= 0.0:
			round_number += 1
			start_round(false)


func _check_elimination_win() -> void:
	if mode == "deathmatch" or mode == "practice":
		return
	var alive_ct: int = 0
	var alive_t: int = 0
	for c in combatants:
		if c == null or not is_instance_valid(c):
			continue
		if c.alive:
			if c.team == "ct":
				alive_ct += 1
			else:
				alive_t += 1
	if alive_ct == 0 and alive_t == 0:
		_finish_round("t" if bomb_planted else "ct", "elimination")
	elif alive_ct == 0:
		_finish_round("t", "elimination")
	elif alive_t == 0 and not bomb_planted:
		_finish_round("ct", "elimination")


func notify_bomb_planted(site_idx: int, pos: Vector3, planter: Variant) -> void:
	if bomb_planted:
		return
	bomb_planted = true
	bomb_site = site_idx
	bomb_position = pos
	bomb_timer = 40.0
	if planter != null:
		var reward: int = int(_rules.get("plant_reward", 300))
		planter.money = EconomySystem.add_money(planter.money, reward, mode)
		planter.score += 2
	bomb_planted_event.emit(site_idx, pos)
	state_updated.emit()


func notify_bomb_defused(defuser: Variant) -> void:
	if not bomb_planted:
		return
	bomb_planted = false
	bomb_defusing = false
	if defuser != null:
		var reward: int = int(_rules.get("defuse_reward", 300))
		defuser.money = EconomySystem.add_money(defuser.money, reward, mode)
		defuser.score += 2
	bomb_defused_event.emit(defuser.display_name if defuser != null else "CT")
	_finish_round("ct", "defuse")


func register_kill(
	killer: Variant,
	victim: Variant,
	weapon_id: int,
	headshot: bool,
	penetrated: bool,
	blind_kill: bool
) -> void:
	var k_name: String = killer.display_name if killer != null else "Mundo"
	var k_team: String = killer.team if killer != null else ""
	var v_name: String = victim.display_name if victim != null else "Objetivo"
	var v_team: String = victim.team if victim != null else ""

	if killer != null and killer != victim:
		if killer.team == victim.team:
			killer.kills = maxi(0, killer.kills - 1)
			var penalty: int = int(_rules.get("team_kill_penalty", -300))
			killer.money = EconomySystem.add_money(killer.money, penalty, mode)
		else:
			killer.kills += 1
			killer.score += 2
			round_kills[killer.get_instance_id()] = int(round_kills.get(killer.get_instance_id(), 0)) + 1
			var w_data: Dictionary = GameData.get_weapon(weapon_id)
			var award: int = EconomySystem.kill_reward(w_data, mode)
			if mode == "deathmatch" and weapon_id == dm_bonus_weapon:
				award += 5
				killer.score += 5
				AudioManager.play_ui("dm-bonus-kill", -3.0)
			killer.money = EconomySystem.add_money(killer.money, award, mode)
			if mode == "deathmatch":
				killer.dm_streak += 1
				if killer.dm_streak % 3 == 0:
					killer.has_healthshot = true

	if victim != null:
		victim.deaths += 1
		victim.dm_streak = 0

	var entry := {
		"killer": k_name,
		"killer_team": k_team,
		"victim": v_name,
		"victim_team": v_team,
		"weapon_id": weapon_id,
		"weapon_icon": str(GameData.get_weapon(weapon_id).get("icon", "ak-47")),
		"headshot": headshot,
		"penetrated": penetrated,
		"blind": blind_kill,
		"time": match_elapsed,
	}
	kill_feed.push_front(entry)
	if kill_feed.size() > 6:
		kill_feed.resize(6)
	kill_feed_added.emit(entry)
	state_updated.emit()


func register_damage(attacker: Variant, amount: float) -> void:
	if attacker == null:
		return
	var aid: int = attacker.get_instance_id()
	round_damage[aid] = float(round_damage.get(aid, 0.0)) + amount


func _finish_round(winner: String, reason: String) -> void:
	if phase != Phase.LIVE:
		return
	phase = Phase.ROUND_END
	phase_timer = float(_rules.get("round_end_time", 5.0))
	if winner == "ct":
		score_ct += 1
	else:
		score_t += 1

	var ct_won: bool = winner == "ct"
	var ct_pay: int = EconomySystem.round_reward(mode, ct_won, reason, loss_level_ct, bomb_planted)
	var t_pay: int = EconomySystem.round_reward(mode, not ct_won, reason, loss_level_t, bomb_planted)
	loss_level_ct = EconomySystem.next_loss_level(loss_level_ct, ct_won)
	loss_level_t = EconomySystem.next_loss_level(loss_level_t, not ct_won)

	for c in combatants:
		if c == null or not is_instance_valid(c):
			continue
		var pay: int = ct_pay if c.team == "ct" else t_pay
		# En Competitive, T que sobrevive sin plantar al terminar tiempo recibe $0
		if mode == "competitive" and reason == "time" and c.team == "t" and c.alive:
			pay = 0
		c.money = EconomySystem.add_money(c.money, pay, mode)

	var mvp_name: String = _pick_mvp(winner)
	round_ended.emit(winner, reason, mvp_name)
	if winner == player_team:
		AudioManager.play_music("music-win", -5.0)
	else:
		AudioManager.play_music("music-lose", -5.0)

	var win_score: int = int(_rules.get("win_score", 13))
	var max_rounds: int = int(_rules.get("max_rounds", 24))
	if score_ct >= win_score or score_t >= win_score or round_number >= max_rounds:
		phase = Phase.MATCH_END
		phase_timer = 8.0
		var overall: String = "ct" if score_ct >= score_t else "t"
		match_ended.emit(overall)
	state_updated.emit()


func _finish_deathmatch() -> void:
	phase = Phase.MATCH_END
	phase_timer = 8.0
	var top_actor: Variant = null
	var top_score: int = -1
	for c in combatants:
		if c != null and is_instance_valid(c) and c.score > top_score:
			top_score = c.score
			top_actor = c
	var winner: String = top_actor.team if top_actor != null else player_team
	match_ended.emit(winner)
	state_updated.emit()


func _pick_mvp(winner_team: String) -> String:
	var best_name: String = ""
	var best_score: float = -1.0
	for c in combatants:
		if c == null or not is_instance_valid(c) or c.team != winner_team:
			continue
		var cid: int = c.get_instance_id()
		var s: float = float(round_kills.get(cid, 0)) * 100.0 + float(round_damage.get(cid, 0.0)) * 0.1
		if s > best_score:
			best_score = s
			best_name = c.display_name
	return best_name


func _pick_next_dm_bonus() -> void:
	var pool: Array[int] = [0, 1, 8, 9, 11, 20, 26, 29, 30, 3]
	dm_bonus_weapon = pool[randi() % pool.size()]
	dm_bonus_timer = 30.0
	AudioManager.play_ui("dm-bonus-start", -5.0)
