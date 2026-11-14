class_name Dust2World
extends Node3D

var map_visual_root: Node3D = null
var dynamic_root: Node3D = null
var round_props_root: Node3D = null

var active_smokes: Array[Dictionary] = []
var active_fires: Array[Dictionary] = []
var dropped_items: Array[Dictionary] = []
var planted_c4_node: Node3D = null
var _c4_led: MeshInstance3D = null
var _c4_beep_accum: float = 0.0
var _tracer_pool: Array[Dictionary] = []
var _fire_tick_accum: float = 0.0


func _ready() -> void:
	dynamic_root = Node3D.new()
	dynamic_root.name = "DynamicWorld"
	add_child(dynamic_root)

	round_props_root = Node3D.new()
	round_props_root.name = "RoundProps"
	add_child(round_props_root)

	_setup_sky_and_lighting()
	_load_dust2_visuals()
	_load_dust2_physics()


func _setup_sky_and_lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	var hdr_path: String = "res://assets/models/maps/dust2_sky.hdr"
	if ResourceLoader.exists(hdr_path):
		var tex: Resource = ResourceLoader.load(hdr_path)
		if tex is Texture2D:
			sky_mat.panorama = tex
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.ssao_enabled = false

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	add_child(sun)


func _load_dust2_visuals() -> void:
	var path: String = "res://assets/models/maps/dust2.glb"
	if not ResourceLoader.exists(path):
		push_warning("Dust2World: falta %s" % path)
		return
	var packed: Resource = ResourceLoader.load(path)
	if packed is PackedScene:
		map_visual_root = packed.instantiate() as Node3D
		if map_visual_root != null:
			map_visual_root.name = "Dust2Visuals"
			add_child(map_visual_root)


func _load_dust2_physics() -> void:
	var path: String = "res://assets/models/maps/dust2_physics.glb"
	if not ResourceLoader.exists(path):
		push_warning("Dust2World: falta %s" % path)
		return
	var packed: Resource = ResourceLoader.load(path)
	if not (packed is PackedScene):
		return
	var phys_root := packed.instantiate() as Node3D
	if phys_root == null:
		return

	var colliders_holder := Node3D.new()
	colliders_holder.name = "Dust2Colliders"
	add_child(colliders_holder)
	_build_colliders_recursive(phys_root, Transform3D.IDENTITY, colliders_holder)
	phys_root.queue_free()


func _build_colliders_recursive(
	node: Node, parent_xform: Transform3D, out_parent: Node3D
) -> void:
	var local_xform: Transform3D = parent_xform
	if node is Node3D:
		local_xform = parent_xform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var meta: Dictionary = GameData.dust2_physics_meta.get(node.name, {})
			var interact_as: Array = meta.get("interact_as", [])
			var pass_bullets: bool = (
				interact_as.has("passbullets")
				or interact_as.has("playerclip")
				or interact_as.has("npcclip")
			)
			var body := StaticBody3D.new()
			body.name = "Col_%s" % node.name
			body.transform = local_xform
			body.collision_layer = 1 if pass_bullets else (1 | 4)
			body.collision_mask = 0
			body.set_meta("bullet_material", str(meta.get("bullet_material", "concrete")))
			body.set_meta("surface", str(meta.get("surface", "concrete")))

			var col := CollisionShape3D.new()
			col.shape = mi.mesh.create_trimesh_shape()
			body.add_child(col)
			out_parent.add_child(body)

	for child in node.get_children():
		_build_colliders_recursive(child, local_xform, out_parent)


func clear_round_props() -> void:
	active_smokes.clear()
	active_fires.clear()
	dropped_items.clear()
	planted_c4_node = null
	_c4_led = null
	_tracer_pool.clear()
	for child in round_props_root.get_children():
		child.queue_free()


func _physics_process(delta: float) -> void:
	_update_smokes(delta)
	_update_fires(delta)
	_update_tracers(delta)
	_update_planted_c4(delta)


func _update_smokes(delta: float) -> void:
	for i in range(active_smokes.size() - 1, -1, -1):
		var s: Dictionary = active_smokes[i]
		s["timer"] = float(s["timer"]) - delta
		var node: Node3D = s["node"]
		var t_left: float = float(s["timer"])
		if t_left <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			active_smokes.remove_at(i)
		elif is_instance_valid(node):
			var scale_factor: float = 1.0
			if t_left > 19.3:
				scale_factor = clampf((20.0 - t_left) / 0.7, 0.25, 1.0)
			elif t_left < 2.2:
				scale_factor = clampf(t_left / 2.2, 0.1, 1.0)
			node.scale = Vector3.ONE * scale_factor


func _update_fires(delta: float) -> void:
	for i in range(active_fires.size() - 1, -1, -1):
		var f: Dictionary = active_fires[i]
		f["timer"] = float(f["timer"]) - delta
		if float(f["timer"]) <= 0.0:
			var n: Node3D = f["node"]
			if is_instance_valid(n):
				n.queue_free()
			active_fires.remove_at(i)

	if active_fires.is_empty():
		return

	_fire_tick_accum += delta
	if _fire_tick_accum < 0.2:
		return
	_fire_tick_accum = 0.0

	var rules: Dictionary = MatchManager.get_rules()
	var ff_enabled: bool = bool(rules.get("friendly_fire", false))
	for c in MatchManager.combatants:
		if c == null or not is_instance_valid(c) or not c.alive:
			continue
		for f in active_fires:
			var f_pos: Vector3 = f["pos"]
			var dist_xz: float = Vector2(c.global_position.x - f_pos.x, c.global_position.z - f_pos.z).length()
			var dy: float = absf(c.global_position.y - f_pos.y)
			if dist_xz <= float(f["radius"]) and dy <= 1.8:
				var owner_node: Node = f["owner"]
				var dmg: float = 8.0
				if owner_node != null and is_instance_valid(owner_node) and owner_node != c and owner_node.team == c.team:
					if not ff_enabled:
						continue
					dmg *= 0.4
				c.take_damage(dmg, owner_node, 0, "chest", false, false)
				break


func _update_tracers(delta: float) -> void:
	for i in range(_tracer_pool.size() - 1, -1, -1):
		var tr: Dictionary = _tracer_pool[i]
		tr["timer"] = float(tr["timer"]) - delta
		if float(tr["timer"]) <= 0.0:
			var n: Node3D = tr["node"]
			if is_instance_valid(n):
				n.queue_free()
			_tracer_pool.remove_at(i)


func _update_planted_c4(delta: float) -> void:
	if not MatchManager.bomb_planted or planted_c4_node == null or not is_instance_valid(planted_c4_node):
		return
	var t_left: float = MatchManager.bomb_timer
	var interval: float = clampf(0.11 + t_left * 0.022, 0.11, 0.95)
	_c4_beep_accum += delta
	if _c4_beep_accum >= interval:
		_c4_beep_accum = 0.0
		var clip: String = "bomb-beep-fast" if t_left <= 10.0 else "bomb-beep"
		var max_r: float = float(GameData.sound_ranges.get("c4Beep", 32.0))
		AudioManager.play_3d(clip, planted_c4_node.global_position, max_r, 1.0)
	if _c4_led != null and is_instance_valid(_c4_led):
		_c4_led.visible = _c4_beep_accum < interval * 0.35


func spawn_grenade_projectile(
	kind: String, pos: Vector3, vel: Vector3, thrower: Node
) -> void:
	var proj := GrenadeProjectile.new()
	round_props_root.add_child(proj)
	proj.setup(kind, pos, vel, thrower, self)


func detonate_grenade(
	kind: String, pos: Vector3, thrower: Node, thrower_team: String
) -> void:
	var explode_r: float = float(GameData.sound_ranges.get("explode", 60.0))
	AudioManager.play_3d("utility-%s-explode" % kind, pos, explode_r, 2.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var rules: Dictionary = MatchManager.get_rules()
	var ff_enabled: bool = bool(rules.get("friendly_fire", false))

	match kind:
		"he":
			_spawn_explosion_flash(pos, Color(1.0, 0.65, 0.25))
			for c in MatchManager.combatants:
				if c == null or not is_instance_valid(c) or not c.alive:
					continue
				var eye: Vector3 = c.global_position + Vector3(0.0, 1.1, 0.0)
				var d: float = pos.distance_to(eye)
				var base_dmg: float = GrenadeMath.he_damage(d)
				if base_dmg <= 0.5:
					continue
				var ray := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.15, 0), eye, 4)
				if not space.intersect_ray(ray).is_empty():
					base_dmg *= 0.35
				if thrower != null and is_instance_valid(thrower) and thrower != c and thrower.team == c.team:
					if not ff_enabled:
						continue
					base_dmg *= 0.85
				var armored: Dictionary = BallisticsSystem.apply_armor_damage(
					base_dmg, "chest", c.armor, c.has_helmet, 0.6
				)
				c.armor = float(armored["armor"])
				c.take_damage(float(armored["health_damage"]), thrower, 0, "chest", false, false)

		"flash":
			_spawn_explosion_flash(pos, Color(1.0, 1.0, 1.0))
			for c in MatchManager.combatants:
				if c == null or not is_instance_valid(c) or not c.alive:
					continue
				var eye: Vector3 = c.get_eye_position()
				var to_flash: Vector3 = pos - eye
				var dist: float = to_flash.length()
				if dist > 30.0 or dist < 0.01:
					continue
				var ray := PhysicsRayQueryParameters3D.create(eye, pos, 4)
				if not space.intersect_ray(ray).is_empty():
					continue
				var look: Vector3 = c.get_look_direction()
				var dot_val: float = look.dot(to_flash / dist)
				var exposure: float = GrenadeMath.flash_exposure(dist, dot_val)
				if exposure > 0.08:
					c.apply_flash(exposure * 3.8)

		"smoke":
			var smoke_root := Node3D.new()
			smoke_root.global_position = pos + Vector3(0.0, 1.35, 0.0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.76, 0.78, 0.80, 0.94)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 1.0
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			for offset in [
				Vector3.ZERO,
				Vector3(1.1, -0.3, 0.7),
				Vector3(-1.1, -0.2, -0.8),
				Vector3(0.7, 0.5, -1.0),
				Vector3(-0.8, 0.4, 1.0),
			]:
				var mi := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 2.3
				sm.height = 3.8
				sm.radial_segments = 14
				sm.rings = 8
				mi.mesh = sm
				mi.material_override = mat
				mi.position = offset
				smoke_root.add_child(mi)
			round_props_root.add_child(smoke_root)
			active_smokes.append({"node": smoke_root, "pos": smoke_root.global_position, "radius": 3.6, "timer": 20.0})

			# Apaga fuegos dentro de 3.8 m
			for i in range(active_fires.size() - 1, -1, -1):
				if Vector3(active_fires[i]["pos"]).distance_to(pos) <= 3.8:
					var fn: Node3D = active_fires[i]["node"]
					if is_instance_valid(fn):
						fn.queue_free()
					active_fires.remove_at(i)

		"molotov", "incendiary":
			for s in active_smokes:
				if Vector3(s["pos"]).distance_to(pos) <= 3.8:
					return
			var fire_root := Node3D.new()
			fire_root.global_position = pos
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.42, 0.08, 0.72)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.38, 0.05)
			mat.emission_energy_multiplier = 2.4
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var disc := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 2.6 if kind == "molotov" else 2.1
			cyl.bottom_radius = cyl.top_radius + 0.3
			cyl.height = 0.14
			disc.mesh = cyl
			disc.material_override = mat
			disc.position = Vector3(0.0, 0.08, 0.0)
			fire_root.add_child(disc)
			round_props_root.add_child(fire_root)
			var dur: float = 7.0 if kind == "molotov" else 5.5
			var rad: float = 2.7 if kind == "molotov" else 2.2
			active_fires.append({"node": fire_root, "pos": pos, "radius": rad, "timer": dur, "owner": thrower, "team": thrower_team})

		"decoy":
			_spawn_explosion_flash(pos, Color(0.95, 0.55, 0.25))


func is_line_blocked_by_smoke(a: Vector3, b: Vector3) -> bool:
	var ab: Vector3 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 1e-6:
		return false
	for s in active_smokes:
		var c: Vector3 = s["pos"]
		var r: float = float(s["radius"])
		var t: float = clampf((c - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest: Vector3 = a + ab * t
		if closest.distance_squared_to(c) <= r * r:
			return true
	return false


func spawn_planted_c4(pos: Vector3) -> void:
	if planted_c4_node != null and is_instance_valid(planted_c4_node):
		planted_c4_node.queue_free()
	var root := Node3D.new()
	root.global_position = pos
	var c4_path: String = "res://assets/models/c4.glb"
	if ResourceLoader.exists(c4_path):
		var packed: Resource = ResourceLoader.load(c4_path)
		if packed is PackedScene:
			var model := (packed as PackedScene).instantiate() as Node3D
			if model != null:
				model.scale = Vector3.ONE * 0.45
				root.add_child(model)
	var led := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1.0, 0.1, 0.1)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.05, 0.05)
	lmat.emission_energy_multiplier = 4.0
	led.mesh = sm
	led.material_override = lmat
	led.position = Vector3(0.0, 0.08, 0.0)
	root.add_child(led)
	round_props_root.add_child(root)
	planted_c4_node = root
	_c4_led = led
	_c4_beep_accum = 0.0


func trigger_c4_explosion(pos: Vector3) -> void:
	AudioManager.play_3d("bomb-explode", pos, float(GameData.sound_ranges.get("c4Explode", 80.0)), 4.0)
	_spawn_explosion_flash(pos, Color(1.0, 0.6, 0.2))
	for c in MatchManager.combatants:
		if c == null or not is_instance_valid(c) or not c.alive:
			continue
		var d: float = pos.distance_to(c.global_position)
		if d < 42.0:
			var dmg: float = maxf(0.0, 500.0 * exp(-(d * d) / 480.0))
			c.take_damage(dmg, null, 0, "chest", false, false)


func spawn_dropped_item(
	kind: String, weapon_id: int, ammo: int, reserve: int, pos: Vector3, impulse: Vector3
) -> void:
	var item_root := Node3D.new()
	item_root.global_position = pos
	var model_path: String = "res://assets/models/c4.glb" if kind == "c4" else GameData.get_viewmodel_path(weapon_id)
	if ResourceLoader.exists(model_path):
		var packed: Resource = ResourceLoader.load(model_path)
		if packed is PackedScene:
			var m := (packed as PackedScene).instantiate() as Node3D
			if m != null:
				m.scale = Vector3.ONE * (0.45 if kind == "c4" else 0.72)
				item_root.add_child(m)
	# Snap al suelo con raycast
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var drop_origin: Vector3 = pos + impulse * 0.25 + Vector3(0.0, 0.4, 0.0)
	var q := PhysicsRayQueryParameters3D.create(drop_origin, drop_origin + Vector3(0.0, -8.0, 0.0), 1)
	var hit: Dictionary = space.intersect_ray(q)
	if not hit.is_empty():
		item_root.global_position = Vector3(hit["position"]) + Vector3(0.0, 0.06, 0.0)
	round_props_root.add_child(item_root)
	dropped_items.append({
		"node": item_root,
		"kind": kind,
		"weapon_id": weapon_id,
		"ammo": ammo,
		"reserve": reserve,
		"pos": item_root.global_position,
	})


func try_pickup_nearby(actor: Node, only_c4_or_primary: bool = true) -> Dictionary:
	for i in range(dropped_items.size() - 1, -1, -1):
		var it: Dictionary = dropped_items[i]
		var d: float = actor.global_position.distance_to(it["pos"])
		if d > 1.35:
			continue
		if it["kind"] == "c4" and actor.team == "t" and not actor.has_c4:
			var node: Node3D = it["node"]
			if is_instance_valid(node):
				node.queue_free()
			dropped_items.remove_at(i)
			return {"picked": "c4"}
		if it["kind"] == "weapon" and not only_c4_or_primary:
			var w_id: int = int(it["weapon_id"])
			var slot: int = EconomySystem.weapon_slot(w_id)
			if (slot == 1 and actor.primary_id < 0) or (slot == 2 and actor.secondary_id < 0):
				var node2: Node3D = it["node"]
				if is_instance_valid(node2):
					node2.queue_free()
				dropped_items.remove_at(i)
				return {"picked": "weapon", "weapon_id": w_id, "ammo": it["ammo"], "reserve": it["reserve"]}
	return {}


func spawn_tracer(from: Vector3, to: Vector3) -> void:
	var diff: Vector3 = to - from
	var length: float = diff.length()
	if length < 0.2:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = length
	cyl.radial_segments = 4
	cyl.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.55, 0.78)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.45)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.mesh = cyl
	mi.material_override = mat
	round_props_root.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var dir: Vector3 = diff / length
	if absf(dir.y) < 0.999:
		mi.look_at(to, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_tracer_pool.append({"node": mi, "timer": 0.055})


func spawn_impact_spark(pos: Vector3, normal: Vector3, material_name: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.012)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.05, 0.05) if material_name == "flesh" else Color(0.12, 0.12, 0.12)
	mi.mesh = bm
	mi.material_override = mat
	round_props_root.add_child(mi)
	mi.global_position = pos + normal * 0.006
	if absf(normal.y) < 0.999:
		mi.look_at(pos + normal * 2.0, Vector3.UP)
	else:
		mi.rotation_degrees = Vector3(-90.0 if normal.y > 0.0 else 90.0, 0.0, 0.0)
	_tracer_pool.append({"node": mi, "timer": 8.0})


func _spawn_explosion_flash(pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.6
	sm.height = 3.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.mesh = sm
	mi.material_override = mat
	round_props_root.add_child(mi)
	mi.global_position = pos + Vector3(0.0, 0.5, 0.0)
	_tracer_pool.append({"node": mi, "timer": 0.18})
