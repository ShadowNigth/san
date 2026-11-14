extends Node

const SOURCE_UNIT: float = 0.0254

const WEAPON_ICONS: Array[String] = [
	"ak-47", "m4a1-s", "usp-s", "awp", "bayonet", "butterfly", "karambit",
	"glock", "deagle", "m4a4", "nova", "mp9", "hkp2000", "p250",
	"fiveseven", "tec9", "cz75a", "revolver", "elite", "famas", "galilar",
	"aug", "sg556", "ssg08", "scar20", "g3sg1", "mac10", "mp7",
	"mp5sd", "ump45", "p90", "bizon", "xm1014", "mag7", "sawedoff",
	"m249", "negev",
]

const BUY_ICON_MAP: Dictionary = {
	"ak-47": "ak47",
	"m4a1-s": "m4a1_silencer",
	"usp-s": "usp_silencer",
	"awp": "awp",
	"glock": "glock",
	"deagle": "deagle",
	"m4a4": "m4a1",
	"nova": "nova",
	"mp9": "mp9",
	"hkp2000": "hkp2000",
	"p250": "p250",
	"fiveseven": "fiveseven",
	"tec9": "tec9",
	"cz75a": "cz75a",
	"revolver": "revolver",
	"elite": "elite",
	"famas": "famas",
	"galilar": "galilar",
	"aug": "aug",
	"sg556": "sg556",
	"ssg08": "ssg08",
	"scar20": "scar20",
	"g3sg1": "g3sg1",
	"mac10": "mac10",
	"mp7": "mp7",
	"mp5sd": "mp5sd",
	"ump45": "ump45",
	"p90": "p90",
	"bizon": "bizon",
	"xm1014": "xm1014",
	"mag7": "mag7",
	"sawedoff": "sawedoff",
	"m249": "m249",
	"negev": "negev",
}

const VIEWMODEL_FALLBACKS: Dictionary = {
	"ak-47": "ak-47",
	"m4a1-s": "m4a1_s",
	"usp-s": "usp-s",
	"awp": "awp",
	"glock": "glock",
	"deagle": "deagle",
	"m4a4": "m4a4",
	"mp9": "mp9",
	"famas": "m4a4",
	"galilar": "ak-47",
	"aug": "m4a4",
	"sg556": "ak-47",
	"ssg08": "awp",
	"scar20": "awp",
	"g3sg1": "awp",
	"mac10": "mp9",
	"mp7": "mp9",
	"mp5sd": "mp9",
	"ump45": "mp9",
	"p90": "mp9",
	"bizon": "mp9",
	"nova": "m4a4",
	"xm1014": "m4a4",
	"mag7": "m4a4",
	"sawedoff": "ak-47",
	"m249": "ak-47",
	"negev": "ak-47",
	"hkp2000": "usp-s",
	"p250": "usp-s",
	"fiveseven": "usp-s",
	"tec9": "glock",
	"cz75a": "glock",
	"revolver": "deagle",
	"elite": "glock",
}

const DEFAULT_LOADOUT_CT: Dictionary = {
	"pistols": [2, 12, 13, 14, 8],
	"mid": [11, 27, 29, 30, 10],
	"rifles": [1, 9, 19, 23, 3],
}

const DEFAULT_LOADOUT_T: Dictionary = {
	"pistols": [7, 13, 15, 18, 8],
	"mid": [26, 29, 30, 31, 32],
	"rifles": [0, 20, 22, 23, 3],
}

var weapons: Array[Dictionary] = []
var weapon_actions: Array = []
var weapon_audio_kits: Array = []
var utility_data: Dictionary = {}
var c4_audio: Dictionary = {}
var ui_cues: Dictionary = {}
var sound_ranges: Dictionary = {}
var round_strings: Dictionary = {}
var dust2_overview: Dictionary = {}
var dust2_physics_meta: Dictionary = {}
var world_grips: Dictionary = {}

var recoil_sys := RecoilSystem.new()
var accuracy_sys := AccuracySystem.new()
var triggers := TriggerVolumes.new()
var nav := NavGraph.new()


func _ready() -> void:
	var weapon_stats_raw: Dictionary = _load_json("res://assets/data/weapon_stats.json")
	var recoil_raw: Dictionary = _load_json("res://assets/data/recoil.json")
	var accuracy_raw: Dictionary = _load_json("res://assets/data/accuracy.json")
	weapon_actions = _load_json_array("res://assets/data/weapon_actions.json")
	weapon_audio_kits = _load_json_array("res://assets/data/weapon_audio_kits.json")
	utility_data = _load_json("res://assets/data/utility.json")
	var buy_zones_raw: Dictionary = _load_json("res://assets/data/dust2_buy_zones.json")
	var nav_raw: Dictionary = _load_json("res://assets/data/dust2_nav.json")
	var places_raw: Dictionary = _load_json("res://assets/data/dust2_places.json")
	dust2_overview = _load_json("res://assets/data/dust2_overview.json")
	dust2_physics_meta = _load_json("res://assets/data/dust2_physics_meta.json")
	c4_audio = _load_json("res://assets/data/c4_audio.json")
	ui_cues = _load_json("res://assets/data/ui_cues.json")
	sound_ranges = _load_json("res://assets/data/sound_ranges.json")
	round_strings = _load_json("res://assets/data/round_strings.json")
	world_grips = _load_json("res://assets/data/world_grips.json")

	_build_weapon_roster(weapon_stats_raw.get("weapons", []))
	recoil_sys.configure(recoil_raw.get("weapons", []), weapons.size())
	accuracy_sys.configure(accuracy_raw, weapons.size(), recoil_sys)
	triggers.configure(buy_zones_raw, places_raw)
	nav.configure(nav_raw)


func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("GameData: no se pudo abrir %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _load_json_array(path: String) -> Array:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("GameData: no se pudo abrir %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Array else []


func _build_weapon_roster(raw_weapons: Array) -> void:
	weapons.clear()
	for i in range(raw_weapons.size()):
		var w: Dictionary = raw_weapons[i].duplicate(true)
		var knife: bool = EconomySystem.is_knife(i)
		var shell: bool = i == 10 or i == 32 or i == 34
		var raw_speed: Variant = w.get("maxSpeed", 250.0)
		var speed_arr: Array = raw_speed if raw_speed is Array else [raw_speed, raw_speed]
		var raw_spread: Variant = w.get("spread", 0.0)
		var spread0: float = float(raw_spread[0]) if raw_spread is Array else float(raw_spread)
		var raw_delay: Variant = w.get("delay", 0.1)
		var delay0: float = 0.5 if knife else (float(raw_delay[0]) if raw_delay is Array else float(raw_delay))
		var delay1: float = 0.85 if knife else (float(raw_delay[1]) if (raw_delay is Array and raw_delay.size() > 1) else delay0)
		var slot: int = EconomySystem.weapon_slot(i)
		var pellets: int = int(w.get("pellets", 1))
		var zoom_levels: int = int(w.get("zoomLevels", 0))
		var label: String = "ASSAULT RIFLE"
		if knife:
			label = "KNIFE"
		elif slot == 2:
			label = "SIDEARM"
		elif pellets > 1:
			label = "SHOTGUN"
		elif zoom_levels > 1:
			label = "SNIPER RIFLE"
		elif (i >= 26 and i <= 31) or i == 11:
			label = "SUBMACHINE GUN"
		elif i >= 35:
			label = "MACHINE GUN"

		var mag_size: int = int(w.get("mag", 30))
		var reserve_count: int = int(w.get("reserveCount", 90))
		var reserve_as_clips: bool = bool(w.get("reserveAsClips", false))
		w["id"] = i
		w["slot"] = slot
		w["label"] = label
		w["icon"] = WEAPON_ICONS[i] if i < WEAPON_ICONS.size() else "ak-47"
		w["reserve"] = reserve_count * mag_size if reserve_as_clips else reserve_count
		w["reserveClips"] = reserve_count if reserve_as_clips else 0
		w["damage"] = 35.0 if knife else float(w.get("damage", 30.0))
		w["head"] = 1.0 if knife else float(w.get("head", 4.0))
		w["delay"] = delay0
		w["alternateDelay"] = delay1
		w["reload"] = 0.0 if knife else float(w.get("reload", 2.5))
		w["speed"] = float(speed_arr[0]) * SOURCE_UNIT
		w["scopedSpeed"] = float(speed_arr[1]) * SOURCE_UNIT if zoom_levels > 0 else float(speed_arr[0]) * SOURCE_UNIT
		w["suppressed"] = i == 1 or i == 2 or i == 28
		w["canToggleSilencer"] = i == 1 or i == 2
		w["pelletSpread"] = spread0 if pellets > 1 else 0.0
		w["reloadStyle"] = "shell" if shell else "magazine"
		w["burstMode"] = i == 7 or i == 19
		weapons.append(w)


func get_weapon(id: int) -> Dictionary:
	if id < 0 or id >= weapons.size():
		return weapons[0] if not weapons.is_empty() else {}
	return weapons[id]


func get_weapon_actions(id: int) -> Dictionary:
	if id >= 0 and id < weapon_actions.size() and weapon_actions[id] is Dictionary:
		return weapon_actions[id]
	return {"deploy": 1.0}


func get_audio_kit(id: int) -> Dictionary:
	if id >= 0 and id < weapon_audio_kits.size() and weapon_audio_kits[id] is Dictionary:
		return weapon_audio_kits[id]
	return {}


func reload_magazine(id: int, ammo: int, reserve: int) -> Dictionary:
	var w: Dictionary = get_weapon(id)
	var mag: int = int(w.get("mag", 30))
	if ammo >= mag or reserve <= 0:
		return {"ammo": ammo, "reserve": reserve}
	var as_clips: bool = bool(w.get("reserveAsClips", false))
	var transfer: int = mini(mag if as_clips else mag - ammo, reserve)
	return {
		"ammo": transfer if as_clips else ammo + transfer,
		"reserve": reserve - transfer,
	}


func get_buy_icon_path(icon_slug: String) -> String:
	var mapped: String = str(BUY_ICON_MAP.get(icon_slug, icon_slug))
	var path: String = "res://assets/icons/buy/%s.svg" % mapped
	if ResourceLoader.exists(path):
		return path
	return "res://assets/icons/buy/ak47.svg"


func get_viewmodel_path(weapon_id: int) -> String:
	if EconomySystem.is_knife(weapon_id):
		return "res://assets/models/bayonet.glb"
	var icon_slug: String = str(get_weapon(weapon_id).get("icon", "ak-47"))
	var exact: String = "res://assets/models/viewmodels/%s.glb" % icon_slug
	if ResourceLoader.exists(exact):
		return exact
	var exact_under: String = "res://assets/models/viewmodels/%s.glb" % icon_slug.replace("-", "_")
	if ResourceLoader.exists(exact_under):
		return exact_under
	var fallback_slug: String = str(VIEWMODEL_FALLBACKS.get(icon_slug, "ak-47"))
	var fb_under: String = "res://assets/models/viewmodels/%s.glb" % fallback_slug.replace("-", "_")
	if not ResourceLoader.exists("res://assets/models/viewmodels/%s.glb" % fallback_slug) and ResourceLoader.exists(fb_under):
		return fb_under
	return "res://assets/models/viewmodels/%s.glb" % fallback_slug


func get_viewmodel_anims_path(weapon_id: int) -> String:
	if EconomySystem.is_knife(weapon_id):
		return "res://assets/models/bayonet_anims.glb"
	var icon_slug: String = str(get_weapon(weapon_id).get("icon", "ak-47"))
	for cand in [icon_slug, icon_slug.replace("-", "_"), str(VIEWMODEL_FALLBACKS.get(icon_slug, "ak-47")), str(VIEWMODEL_FALLBACKS.get(icon_slug, "ak-47")).replace("-", "_")]:
		var p := "res://assets/models/viewmodels/%s_anims.glb" % cand
		if ResourceLoader.exists(p):
			return p
	return "res://assets/models/viewmodels/ak-47_anims.glb"


func get_arms_path(team: String) -> String:
	return "res://assets/models/agents/ct_arms.glb" if team == "ct" else "res://assets/models/agents/t_arms.glb"


func get_world_grip(weapon_id: int) -> Dictionary:
	var key := str(weapon_id)
	if world_grips.has(key) and world_grips[key] is Dictionary:
		return world_grips[key]
	var icon_slug: String = str(get_weapon(weapon_id).get("icon", "ak-47"))
	var fb: String = str(VIEWMODEL_FALLBACKS.get(icon_slug, "ak-47"))
	for wid in range(weapons.size()):
		if str(weapons[wid].get("icon", "")) == fb and world_grips.has(str(wid)):
			return world_grips[str(wid)]
	return {}


func get_loadout_for_team(team: String) -> Dictionary:
	return DEFAULT_LOADOUT_CT if team == "ct" else DEFAULT_LOADOUT_T
