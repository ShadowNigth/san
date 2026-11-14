extends SceneTree

var _failures: int = 0


func _init() -> void:
	print("[CS2GO Tests] Iniciando verificación de simulación...")
	_test_movement()
	_test_ballistics()
	_test_economy()
	_test_grenades()
	_test_recoil_and_accuracy()
	_test_dust2_data()

	if _failures > 0:
		printerr("[CS2GO Tests] FALLARON %d comprobaciones." % _failures)
		quit(1)
	else:
		print("[CS2GO Tests] TODAS las comprobaciones pasaron con éxito.")
		quit(0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)


func _test_movement() -> void:
	var dt: float = 1.0 / 128.0
	var vel := Vector2.ZERO
	for _i in range(64):
		vel = MovementMath.accelerate(vel, Vector2(0.0, -1.0), 250.0 * MovementMath.SOURCE_UNIT, dt, true)
	_assert(vel.length() > 5.5 and vel.length() <= 6.4, "Ground acceleration within expected CS2 range")

	var capped: Vector2 = MovementMath.limit_jump_speed(Vector2(10.0, 0.0), 6.35)
	_assert(absf(capped.length() - 6.35 * 1.1) < 0.01, "Jump speed cap limits horizontal speed to 1.1x max")

	var air_v := Vector2(6.0, 0.0)
	var air_next: Vector2 = MovementMath.accelerate(air_v, Vector2(0.0, -1.0), 6.35, dt, false)
	_assert(air_next.length() > air_v.length(), "Air strafe perpendicular wish accelerates speed")


func _test_ballistics() -> void:
	var d_wood: float = BallisticsSystem.penetrate(36.0, 2.0, 0.15, "wood")
	var d_conc: float = BallisticsSystem.penetrate(36.0, 2.0, 0.15, "concrete")
	_assert(d_wood > d_conc, "Wood penetrates more damage than concrete")

	var leg: Dictionary = BallisticsSystem.apply_armor_damage(40.0, "leg", 100.0, true, 1.55)
	_assert(is_equal_approx(float(leg["health_damage"]), 40.0), "Leg hits bypass armor")

	var head_no_helm: Dictionary = BallisticsSystem.apply_armor_damage(100.0, "head", 100.0, false, 1.55)
	_assert(is_equal_approx(float(head_no_helm["health_damage"]), 100.0), "Head hit without helmet deals full damage")

	var back: bool = BallisticsSystem.knife_backstab(Vector3(0, 0, 2), Vector3(0, 0, 0), Vector3(0, 0, -1))
	_assert(back, "Knife backstab detects attacker behind victim")
	_assert(BallisticsSystem.knife_damage(true, true, true) == 180, "Right-click backstab deals 180 dmg")


func _test_economy() -> void:
	var r_win: int = EconomySystem.round_reward("competitive", true, "defuse", 2, true)
	_assert(r_win == 3500, "Competitive defuse win rewards $3500")
	var r_loss: int = EconomySystem.round_reward("competitive", false, "defuse", 0, true)
	_assert(r_loss == 2000, "Competitive loss with plant adds +$600 bonus")
	_assert(EconomySystem.weapon_slot(0) == 1, "AK-47 is slot 1")
	_assert(EconomySystem.weapon_slot(8) == 2, "Desert Eagle is slot 2")
	_assert(EconomySystem.weapon_slot(4) == 3, "Bayonet is slot 3")


func _test_grenades() -> void:
	_assert(GrenadeMath.he_damage(0.0) > 95.0, "HE close blast > 95 dmg")
	_assert(GrenadeMath.he_damage(10.0) == 0.0, "HE outside 8.9m deals 0 dmg")
	_assert(GrenadeMath.fire_impact_allowed(0.95), "Flat floor allows molotov detonation")
	_assert(not GrenadeMath.fire_impact_allowed(0.2), "Steep wall bounces molotov")


func _test_recoil_and_accuracy() -> void:
	var f_rec: FileAccess = FileAccess.open("res://assets/data/recoil.json", FileAccess.READ)
	var f_acc: FileAccess = FileAccess.open("res://assets/data/accuracy.json", FileAccess.READ)
	_assert(f_rec != null and f_acc != null, "recoil.json and accuracy.json readable")
	var rec_data: Dictionary = JSON.parse_string(f_rec.get_as_text())
	var acc_data: Dictionary = JSON.parse_string(f_acc.get_as_text())

	var rec_sys := RecoilSystem.new()
	rec_sys.configure(rec_data["weapons"], 37)
	var acc_sys := AccuracySystem.new()
	acc_sys.configure(acc_data, 37, rec_sys)

	var imp0: Vector2 = rec_sys.get_impulse(0, 0, 0)
	var imp1: Vector2 = rec_sys.get_impulse(0, 1, 0)
	_assert(imp0.length() > 0.0 and imp1 != imp0, "AK-47 recoil table deterministic and distinct")

	var stand_pose := {"mode": 0, "crouch": 0.0, "grounded": true, "ladder": false, "reloading": false, "walking": false, "speed": 0.0, "verticalSpeed": 0.0}
	var run_pose := {"mode": 0, "crouch": 0.0, "grounded": true, "ladder": false, "reloading": false, "walking": false, "speed": 5.5, "verticalSpeed": 0.0}
	var st := AccuracySystem.WeaponAccuracyState.new()
	var s_stand: float = acc_sys.weapon_shot_spread(0, st, stand_pose)
	var s_run: float = acc_sys.weapon_shot_spread(0, st, run_pose)
	_assert(s_run > s_stand * 5.0, "Running inaccuracy far exceeds standing inaccuracy")


func _test_dust2_data() -> void:
	var bz: Dictionary = JSON.parse_string(FileAccess.open("res://assets/data/dust2_buy_zones.json", FileAccess.READ).get_as_text())
	var pl: Dictionary = JSON.parse_string(FileAccess.open("res://assets/data/dust2_places.json", FileAccess.READ).get_as_text())
	var nv: Dictionary = JSON.parse_string(FileAccess.open("res://assets/data/dust2_nav.json", FileAccess.READ).get_as_text())

	var triggers := TriggerVolumes.new()
	triggers.configure(bz, pl)
	var nav := NavGraph.new()
	nav.configure(nv)

	var t_spawn: Vector3 = nav.get_spawn_position("t", 0)
	var ct_spawn: Vector3 = nav.get_spawn_position("ct", 0)
	var site_a: Vector3 = nav.get_site_position(0)
	var site_b: Vector3 = nav.get_site_position(1)

	_assert(triggers.in_buy_zone(t_spawn, "t", 0.4, 1.8), "T spawn inside T buy zone")
	_assert(triggers.in_buy_zone(ct_spawn, "ct", 0.4, 1.8), "CT spawn inside CT buy zone")
	_assert(triggers.bomb_site_at(site_a, 0.4, 1.8) == 0, "Site A position inside Site A hull")
	_assert(triggers.bomb_site_at(site_b, 0.4, 1.8) == 1, "Site B position inside Site B hull")

	var path_a: PackedVector3Array = nav.find_path(t_spawn, site_a)
	var path_b: PackedVector3Array = nav.find_path(ct_spawn, site_b)
	_assert(path_a.size() >= 4, "A* finds multi-waypoint route T Spawn -> Site A")
	_assert(path_b.size() >= 4, "A* finds multi-waypoint route CT Spawn -> Site B")
