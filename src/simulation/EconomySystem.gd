class_name EconomySystem
extends RefCounted

const RULES: Dictionary = {
	"casual": {
		"start_money": 1000,
		"max_money": 10000,
		"free_armor": true,
		"free_kit": true,
		"freeze_time": 5.0,
		"buy_time": 45.0,
		"round_time": 135.0,
		"round_end_time": 6.0,
		"team_size": 10,
		"plant_reward": 200,
		"defuse_reward": 200,
		"team_kill_penalty": -300,
		"starting_loss_level": 0,
		"max_rounds": 15,
		"win_score": 8,
		"friendly_fire": false,
	},
	"competitive": {
		"start_money": 800,
		"max_money": 16000,
		"free_armor": false,
		"free_kit": false,
		"freeze_time": 8.0,
		"buy_time": 20.0,
		"round_time": 115.2,
		"round_end_time": 5.0,
		"team_size": 5,
		"plant_reward": 300,
		"defuse_reward": 300,
		"team_kill_penalty": -300,
		"starting_loss_level": 1,
		"max_rounds": 24,
		"win_score": 13,
		"friendly_fire": true,
	},
	"deathmatch": {
		"start_money": 16000,
		"max_money": 16000,
		"free_armor": true,
		"free_kit": false,
		"freeze_time": 0.0,
		"buy_time": 9999.0,
		"round_time": 600.0,
		"round_end_time": 6.0,
		"team_size": 8,
		"plant_reward": 0,
		"defuse_reward": 0,
		"team_kill_penalty": 0,
		"starting_loss_level": 0,
		"max_rounds": 1,
		"win_score": 1,
		"friendly_fire": false,
	},
	"practice": {
		"start_money": 16000,
		"max_money": 16000,
		"free_armor": true,
		"free_kit": true,
		"freeze_time": 1.0,
		"buy_time": 9999.0,
		"round_time": 300.0,
		"round_end_time": 4.0,
		"team_size": 3,
		"plant_reward": 300,
		"defuse_reward": 300,
		"team_kill_penalty": 0,
		"starting_loss_level": 0,
		"max_rounds": 30,
		"win_score": 16,
		"friendly_fire": false,
	},
}


static func rules_for(mode: String) -> Dictionary:
	return RULES.get(mode, RULES["casual"])


static func is_knife(weapon_id: int) -> bool:
	return (weapon_id >= 4 and weapon_id <= 6) or weapon_id >= 37


static func weapon_slot(weapon_id: int) -> int:
	if is_knife(weapon_id):
		return 3
	if weapon_id == 2 or weapon_id == 7 or weapon_id == 8 or (weapon_id >= 12 and weapon_id <= 18):
		return 2
	return 1


static func weapon_available(weapon_data: Dictionary, team: String) -> bool:
	var w_team: String = str(weapon_data.get("team", "both"))
	return w_team == "both" or w_team == team


static func kill_reward(weapon_data: Dictionary, mode: String) -> int:
	var base_award: int = int(weapon_data.get("killAward", 300))
	if mode == "casual":
		return int(base_award * 0.5)
	return base_award


static func equipment_price(kind: String, armor: float, helmet: bool) -> int:
	if kind == "kit":
		return 400
	if kind == "vest":
		return 0 if armor >= 100.0 else 650
	if helmet:
		return 0 if armor >= 100.0 else 650
	return 350 if armor >= 100.0 else 1000


static func add_money(balance: int, amount: int, mode: String) -> int:
	var max_m: int = int(rules_for(mode).get("max_money", 16000))
	return clampi(balance + amount, 0, max_m)


static func next_loss_level(level: int, won: bool) -> int:
	return clampi(level + (-1 if won else 1), 0, 4)


static func round_reward(
	mode: String, won: bool, reason: String, loss_level: int, planted: bool
) -> int:
	if mode == "casual":
		if won:
			return 2700
		return 2400 + (200 if (planted and reason == "defuse") else 0)
	if won:
		return 3500 if (reason == "bomb" or reason == "defuse") else 3250
	var clamped: int = clampi(loss_level, 0, 4)
	return 1400 + clamped * 500 + (600 if (planted and reason == "defuse") else 0)
