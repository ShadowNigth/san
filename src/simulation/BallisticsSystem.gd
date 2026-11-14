class_name BallisticsSystem
extends RefCounted

const SOURCE_UNITS_PER_METER: float = 1.0 / 0.0254
const MAX_BARRIER_PENETRATIONS: int = 4

const MATERIAL_MODIFIERS: Dictionary = {
	"flesh": 1.0,
	"wood": 3.0,
	"metal": 0.5,
	"concrete": 0.4,
	"glass": 3.0,
}


static func range_damage(damage: float, distance_meters: float, modifier: float) -> float:
	return damage * pow(modifier, (distance_meters * SOURCE_UNITS_PER_METER) / 500.0)


static func penetrate(
	damage: float, power: float, thickness_meters: float, material: String
) -> float:
	var modifier: float = float(MATERIAL_MODIFIERS.get(material, 0.4))
	var thickness: float = thickness_meters * SOURCE_UNITS_PER_METER
	if thickness > 90.0 or power <= 0.0:
		return 0.0
	var base_fraction: float = 0.05 if material == "glass" else 0.16
	var loss: float = (
		damage * base_fraction
		+ (3.0 / power) * 1.25 * (3.0 / modifier)
		+ (thickness * thickness) / (24.0 * modifier)
	)
	return maxf(0.0, damage - maxf(0.0, loss))


static func hit_region_multiplier(region: String, head_multiplier: float = 4.0) -> float:
	match region:
		"head":
			return head_multiplier
		"stomach":
			return 1.25
		"leg":
			return 0.75
		_:
			return 1.0


static func apply_armor_damage(
	damage: float, region: String, armor: float, helmet: bool, armor_ratio: float
) -> Dictionary:
	var incoming: float = maxf(0.0, damage)
	var available_armor: float = maxf(0.0, armor)
	var protected_hit: bool = region != "leg" and (region != "head" or helmet)
	if not protected_hit or available_armor <= 0.0:
		return {"health_damage": incoming, "armor_damage": 0.0, "armor": available_armor}
	var ratio: float = clampf(armor_ratio * 0.5, 0.0, 1.0)
	var armor_damage: float = minf(available_armor, (incoming - incoming * ratio) * 0.5)
	return {
		"health_damage": incoming - armor_damage * 2.0,
		"armor_damage": armor_damage,
		"armor": available_armor - armor_damage,
	}


static func knife_range(stab: bool) -> float:
	return (32.0 if stab else 48.0) * 0.0254


static func knife_damage(stab: bool, first_swing: bool, back: bool) -> int:
	if back:
		return 180 if stab else 90
	if stab:
		return 65
	return 40 if first_swing else 25


static func knife_backstab(
	attacker_pos: Vector3, victim_pos: Vector3, victim_forward: Vector3
) -> bool:
	var delta := Vector2(victim_pos.x - attacker_pos.x, victim_pos.z - attacker_pos.z)
	var dist: float = delta.length()
	if dist <= 1e-6:
		return false
	var fwd := Vector2(victim_forward.x, victim_forward.z)
	if fwd.length_squared() <= 1e-6:
		return false
	return (delta / dist).dot(fwd.normalized()) > 0.475
