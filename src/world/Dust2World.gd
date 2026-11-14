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
var _atlas_fx_pool: Array[Dictionary] = []
var _fire_tick_accum: float = 0.0

var _smoke_noise_tex: ImageTexture = null
var _smoke_shader: Shader = null
var _flame_shader: Shader = null
var _heat_shader: Shader = null
var _flame_mesh: ArrayMesh = null
var _fire_atlas_tex: Texture2D = null
var _blast_atlas_tex: Texture2D = null
var _fireburst_atlas_tex: Texture2D = null
var _smoke_atlas_tex: Texture2D = null
var _glow_tex: Texture2D = null


func _ready() -> void:
	dynamic_root = Node3D.new()
	dynamic_root.name = "DynamicWorld"
	add_child(dynamic_root)

	round_props_root = Node3D.new()
	round_props_root.name = "RoundProps"
	add_child(round_props_root)

	_init_vfx_resources()
	_setup_sky_and_lighting()
	_load_dust2_visuals()
	_load_dust2_physics()


func _init_vfx_resources() -> void:
	var fn_r := FastNoiseLite.new()
	fn_r.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn_r.frequency = 0.045
	fn_r.fractal_octaves = 3
	fn_r.seed = 11
	var fn_g := FastNoiseLite.new()
	fn_g.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn_g.frequency = 0.055
	fn_g.fractal_octaves = 3
	fn_g.seed = 47
	var fn_b := FastNoiseLite.new()
	fn_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn_b.frequency = 0.085
	fn_b.fractal_octaves = 2
	fn_b.seed = 93
	var ir := fn_r.get_seamless_image(128, 128)
	var ig := fn_g.get_seamless_image(128, 128)
	var ib := fn_b.get_seamless_image(128, 128)
	var rgb_img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for py in range(128):
		for px in range(128):
			rgb_img.set_pixel(px, py, Color(ir.get_pixel(px, py).r, ig.get_pixel(px, py).r, ib.get_pixel(px, py).r))
	rgb_img.generate_mipmaps()
	_smoke_noise_tex = ImageTexture.create_from_image(rgb_img)

	if ResourceLoader.exists("res://assets/shaders/cs2_smoke.gdshader"):
		_smoke_shader = ResourceLoader.load("res://assets/shaders/cs2_smoke.gdshader") as Shader
	if ResourceLoader.exists("res://assets/shaders/incendiary_flame.gdshader"):
		_flame_shader = ResourceLoader.load("res://assets/shaders/incendiary_flame.gdshader") as Shader
	if ResourceLoader.exists("res://assets/shaders/incendiary_heat.gdshader"):
		_heat_shader = ResourceLoader.load("res://assets/shaders/incendiary_heat.gdshader") as Shader
	if ResourceLoader.exists("res://assets/textures/polish/grenade_fire_atlas.png"):
		_fire_atlas_tex = ResourceLoader.load("res://assets/textures/polish/grenade_fire_atlas.png") as Texture2D
	if ResourceLoader.exists("res://assets/textures/polish/grenade_blast_atlas.png"):
		_blast_atlas_tex = ResourceLoader.load("res://assets/textures/polish/grenade_blast_atlas.png") as Texture2D
	if ResourceLoader.exists("res://assets/textures/polish/grenade_fireburst_atlas.png"):
		_fireburst_atlas_tex = ResourceLoader.load("res://assets/textures/polish/grenade_fireburst_atlas.png") as Texture2D
	if ResourceLoader.exists("res://assets/textures/polish/grenade_smoke_atlas.png"):
		_smoke_atlas_tex = ResourceLoader.load("res://assets/textures/polish/grenade_smoke_atlas.png") as Texture2D
	if ResourceLoader.exists("res://assets/textures/polish/grenade_glow.png"):
		_glow_tex = ResourceLoader.load("res://assets/textures/polish/grenade_glow.png") as Texture2D

	_flame_mesh = _build_crossed_flame_mesh()


func _build_crossed_flame_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var planes := [0.0, PI * 0.5, PI * 0.25]
	var steps := 5
	for angle in planes:
		var dx: float = cos(angle) * 0.55
		var dz: float = sin(angle) * 0.55
		for s in range(steps):
			var v0: float = float(s) / float(steps)
			var v1: float = float(s + 1) / float(steps)
			var y0: float = v0 * 1.35
			var y1: float = v1 * 1.35
			var p00 := Vector3(-dx, y0, -dz)
			var p10 := Vector3(dx, y0, dz)
			var p01 := Vector3(-dx, y1, -dz)
			var p11 := Vector3(dx, y1, dz)
			st.set_uv(Vector2(0.0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(1.0, v0)); st.add_vertex(p10)
			st.set_uv(Vector2(1.0, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(0.0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(1.0, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(0.0, v1)); st.add_vertex(p01)
	return st.commit()


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
	_atlas_fx_pool.clear()
	for child in round_props_root.get_children():
		child.queue_free()


func _physics_process(delta: float) -> void:
	_update_smokes(delta)
	_update_fires(delta)
	_update_tracers(delta)
	_update_atlas_fx(delta)
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
			var bloom: float = 1.0
			var alpha_scale: float = 1.0
			if t_left > 19.25:
				bloom = clampf((20.0 - t_left) / 0.75, 0.22, 1.0)
			elif t_left < 2.4:
				alpha_scale = clampf(t_left / 2.4, 0.0, 1.0)
				bloom = 1.0 + (1.0 - alpha_scale) * 0.14
			node.scale = Vector3.ONE * bloom

			var mmi: MultiMeshInstance3D = s.get("mmi", null)
			if mmi != null and mmi.multimesh != null:
				var mm: MultiMesh = mmi.multimesh
				var agitates: PackedFloat32Array = s["agitates"]
				var seeds: PackedFloat32Array = s["seeds"]
				var domes: PackedFloat32Array = s["domes"]
				var rots: PackedFloat32Array = s["rots"]
				var tints: Array = s["tints"]
				var dirty: bool = alpha_scale < 0.999
				for p_idx in range(mm.instance_count):
					if agitates[p_idx] > 0.0:
						agitates[p_idx] = maxf(0.0, agitates[p_idx] - delta * 0.55)
						dirty = true
					if dirty:
						mm.set_instance_custom_data(p_idx, Color(seeds[p_idx], agitates[p_idx], domes[p_idx], rots[p_idx]))
						var col: Color = tints[p_idx]
						mm.set_instance_color(p_idx, Color(col.r, col.g, col.b, col.a * alpha_scale))


func _update_fires(delta: float) -> void:
	for i in range(active_fires.size() - 1, -1, -1):
		var f: Dictionary = active_fires[i]
		f["timer"] = float(f["timer"]) - delta
		var t_left: float = float(f["timer"])
		if t_left <= 0.0:
			var n: Node3D = f["node"]
			if is_instance_valid(n):
				n.queue_free()
			active_fires.remove_at(i)
			continue
		var elapsed: float = float(f.get("duration", 7.0)) - t_left
		var ign: float = clampf(elapsed / 0.35, 0.05, 1.0)
		var fade_v: float = clampf(t_left / 1.1, 0.0, 1.0)
		for fm in f.get("flame_mats", []):
			var sm := fm as ShaderMaterial
			if sm != null:
				sm.set_shader_parameter("ignition", ign)
				sm.set_shader_parameter("fade", fade_v)
		for hm in f.get("heat_mats", []):
			var shm := hm as ShaderMaterial
			if shm != null:
				shm.set_shader_parameter("ignition", ign)
				shm.set_shader_parameter("fade", fade_v)
		var pool_mat: StandardMaterial3D = f.get("pool_mat", null)
		if pool_mat != null:
			pool_mat.albedo_color.a = 0.55 * fade_v
			pool_mat.emission_energy_multiplier = 2.0 * ign * fade_v

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
				var owner_node: Variant = f["owner"]
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


func _update_atlas_fx(delta: float) -> void:
	for i in range(_atlas_fx_pool.size() - 1, -1, -1):
		var fx: Dictionary = _atlas_fx_pool[i]
		fx["elapsed"] = float(fx["elapsed"]) + delta
		var el: float = float(fx["elapsed"])
		var dur: float = float(fx["duration"])
		var n: Node3D = fx["node"]
		if el >= dur or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_atlas_fx_pool.remove_at(i)
			continue
		var frac: float = clampf(el / dur, 0.0, 1.0)
		var mat: StandardMaterial3D = fx.get("mat", null)
		if mat != null:
			var cols: int = int(fx.get("cols", 4))
			var rows: int = int(fx.get("rows", 4))
			var total_frames: int = cols * rows
			var f_idx: int = mini(total_frames - 1, int(floor(frac * float(total_frames))))
			var gx: int = f_idx % cols
			var gy: int = f_idx / cols
			mat.uv1_scale = Vector3(1.0 / float(cols), 1.0 / float(rows), 1.0)
			mat.uv1_offset = Vector3(float(gx) / float(cols), float(gy) / float(rows), 0.0)
			mat.albedo_color.a = float(fx.get("base_alpha", 1.0)) * (1.0 - frac * frac)
		var s0: float = float(fx.get("scale_start", 1.0))
		var s1: float = float(fx.get("scale_end", 1.8))
		n.scale = Vector3.ONE * lerpf(s0, s1, frac)


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
	kind: String, pos: Vector3, vel: Vector3, thrower: Variant
) -> void:
	var proj := GrenadeProjectile.new()
	round_props_root.add_child(proj)
	proj.setup(kind, pos, vel, thrower, self)


func detonate_grenade(
	kind: String, pos: Vector3, thrower: Variant, thrower_team: String
) -> void:
	var explode_r: float = float(GameData.sound_ranges.get("explode", 60.0))
	AudioManager.play_3d("utility-%s-explode" % kind, pos, explode_r, 2.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var rules: Dictionary = MatchManager.get_rules()
	var ff_enabled: bool = bool(rules.get("friendly_fire", false))

	match kind:
		"he":
			_spawn_explosion_fx(pos, Color(1.0, 0.65, 0.25), true)
			carve_smoke_tunnel(pos - Vector3(0.0, 0.4, 0.0), pos + Vector3(0.0, 2.2, 0.0), 3.4, 1.0)
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
			var smoke_origin: Vector3 = pos + Vector3(0.0, 0.15, 0.0)
			var smoke_root := Node3D.new()
			smoke_root.global_position = smoke_origin
			round_props_root.add_child(smoke_root)
			var smoke_entry: Dictionary = _build_volumetric_smoke(smoke_root, smoke_origin, space)
			smoke_entry["timer"] = 20.0
			active_smokes.append(smoke_entry)

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
			round_props_root.add_child(fire_root)
			var dur: float = 7.0 if kind == "molotov" else 5.5
			var rad: float = 2.7 if kind == "molotov" else 2.2
			var fire_entry: Dictionary = _build_incendiary_fire(fire_root, pos, rad, dur, space)
			fire_entry["owner"] = thrower
			fire_entry["team"] = thrower_team
			active_fires.append(fire_entry)

		"decoy":
			_spawn_explosion_fx(pos, Color(0.95, 0.55, 0.25), false)


func _build_volumetric_smoke(root: Node3D, origin: Vector3, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var count := 96
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = count

	var qm := QuadMesh.new()
	qm.size = Vector2(1.65, 1.65)
	mm.mesh = qm

	var local_pts: Array[Vector3] = []
	var agitates := PackedFloat32Array()
	var seeds := PackedFloat32Array()
	var domes := PackedFloat32Array()
	var rots := PackedFloat32Array()
	var tints: Array[Color] = []
	agitates.resize(count)
	seeds.resize(count)
	domes.resize(count)
	rots.resize(count)

	for i in range(count):
		var dir_xz := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		if dir_xz.length_squared() < 0.001:
			dir_xz = Vector3.FORWARD
		dir_xz = dir_xz.normalized()
		var target_r: float = randf_range(0.1, 3.45) * pow(randf(), 0.45)
		var ray_from := origin + Vector3(0.0, 0.75, 0.0)
		var ray_to := ray_from + dir_xz * target_r
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1 | 4))
		var safe_r: float = target_r
		if not hit.is_empty():
			safe_r = maxf(0.25, ray_from.distance_to(Vector3(hit["position"])) - 0.55)
		var h_frac: float = clampf(1.0 - (safe_r / 3.6) * 0.55 + randf_range(-0.22, 0.25), 0.08, 1.0)
		var y_local: float = 0.45 + h_frac * 2.25 * randf_range(0.45, 1.05)
		var p_local := Vector3(dir_xz.x * safe_r, y_local, dir_xz.z * safe_r)
		var puff_scale: float = lerpf(1.25, 0.88, safe_r / 3.6) * randf_range(0.82, 1.24)
		var xf := Transform3D(Basis().scaled(Vector3.ONE * puff_scale), p_local)
		mm.set_instance_transform(i, xf)
		var shade: float = randf_range(0.84, 1.02)
		var c := Color(shade, shade, shade * 1.02, 0.92)
		mm.set_instance_color(i, c)
		var sd: float = randf_range(0.0, 100.0)
		var rt: float = randf_range(0.0, TAU)
		mm.set_instance_custom_data(i, Color(sd, 0.0, h_frac, rt))
		local_pts.append(p_local)
		agitates[i] = 0.0
		seeds[i] = sd
		domes[i] = h_frac
		rots[i] = rt
		tints.append(c)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 6.0
	if _smoke_shader != null:
		var smat := ShaderMaterial.new()
		smat.shader = _smoke_shader
		smat.set_shader_parameter("noise_tex", _smoke_noise_tex)
		mmi.material_override = smat
	root.add_child(mmi)

	return {
		"node": root,
		"mmi": mmi,
		"pos": origin + Vector3(0.0, 1.25, 0.0),
		"radius": 3.55,
		"local_pts": local_pts,
		"agitates": agitates,
		"seeds": seeds,
		"domes": domes,
		"rots": rots,
		"tints": tints,
	}


func _build_incendiary_fire(
	root: Node3D, origin: Vector3, rad: float, dur: float, space: PhysicsDirectSpaceState3D
) -> Dictionary:
	var pool_mat := StandardMaterial3D.new()
	pool_mat.albedo_color = Color(0.95, 0.25, 0.04, 0.55)
	pool_mat.emission_enabled = true
	pool_mat.emission = Color(1.0, 0.34, 0.04)
	pool_mat.emission_energy_multiplier = 2.0
	pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = rad * 0.9
	cyl.bottom_radius = rad * 1.02
	cyl.height = 0.05
	disc.mesh = cyl
	disc.material_override = pool_mat
	disc.position = Vector3(0.0, 0.03, 0.0)
	root.add_child(disc)

	var flame_mats: Array[ShaderMaterial] = []
	var heat_mats: Array[ShaderMaterial] = []
	var patch_count := 14
	for i in range(patch_count):
		var ang: float = (TAU * float(i) / float(patch_count)) + randf_range(-0.22, 0.22)
		var dist: float = 0.0 if i == 0 else randf_range(0.35, rad * 0.88)
		var probe_xz := origin + Vector3(cos(ang) * dist, 0.85, sin(ang) * dist)
		var g_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(probe_xz, probe_xz + Vector3(0.0, -2.2, 0.0), 1))
		var patch_world: Vector3 = Vector3(g_hit["position"]) if not g_hit.is_empty() else (origin + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist))
		var patch_local := patch_world - origin

		var fm := MeshInstance3D.new()
		fm.mesh = _flame_mesh
		fm.position = patch_local
		fm.rotation.y = randf_range(0.0, TAU)
		fm.scale = Vector3(randf_range(0.85, 1.35), randf_range(0.80, 1.30), randf_range(0.85, 1.35))
		if _flame_shader != null:
			var smat := ShaderMaterial.new()
			smat.shader = _flame_shader
			if _fire_atlas_tex != null:
				smat.set_shader_parameter("original_fire_atlas", _fire_atlas_tex)
			smat.set_shader_parameter("seed", randf_range(0.0, 60.0))
			smat.set_shader_parameter("ignition", 0.08)
			smat.set_shader_parameter("fade", 1.0)
			smat.set_shader_parameter("intensity", 1.35)
			fm.material_override = smat
			flame_mats.append(smat)
		root.add_child(fm)

	if _heat_shader != null:
		for k in range(3):
			var hm_node := MeshInstance3D.new()
			var hq := QuadMesh.new()
			hq.size = Vector2(rad * 1.4, 2.0)
			hm_node.mesh = hq
			hm_node.position = Vector3(randf_range(-0.6, 0.6), 1.1, randf_range(-0.6, 0.6))
			var hmat := ShaderMaterial.new()
			hmat.shader = _heat_shader
			hmat.set_shader_parameter("seed", float(k) * 19.3)
			hmat.set_shader_parameter("ignition", 0.1)
			hmat.set_shader_parameter("fade", 1.0)
			hm_node.material_override = hmat
			heat_mats.append(hmat)
			root.add_child(hm_node)

	return {
		"node": root,
		"pos": origin,
		"radius": rad,
		"timer": dur,
		"duration": dur,
		"pool_mat": pool_mat,
		"flame_mats": flame_mats,
		"heat_mats": heat_mats,
	}


func carve_smoke_tunnel(from: Vector3, to: Vector3, radius: float = 0.36, strength: float = 0.55) -> void:
	if active_smokes.is_empty():
		return
	var ab: Vector3 = to - from
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq < 1e-5:
		return
	for s in active_smokes:
		var node: Node3D = s.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		var s_pos: Vector3 = s["pos"]
		var s_rad: float = float(s["radius"]) + radius + 1.0
		var t_c: float = clampf((s_pos - from).dot(ab) / ab_len_sq, 0.0, 1.0)
		if (from + ab * t_c).distance_to(s_pos) > s_rad:
			continue
		var agitates: PackedFloat32Array = s["agitates"]
		var local_pts: Array = s["local_pts"]
		var mmi: MultiMeshInstance3D = s.get("mmi", null)
		if mmi == null or mmi.multimesh == null:
			continue
		var seeds: PackedFloat32Array = s["seeds"]
		var domes: PackedFloat32Array = s["domes"]
		var rots: PackedFloat32Array = s["rots"]
		var origin_w: Vector3 = node.global_position
		var hit_radius: float = radius + 0.85
		var hit_rad_sq: float = hit_radius * hit_radius
		for idx in range(local_pts.size()):
			var pw: Vector3 = origin_w + Vector3(local_pts[idx]) * node.scale
			var t_p: float = clampf((pw - from).dot(ab) / ab_len_sq, 0.0, 1.0)
			var d_sq: float = (from + ab * t_p).distance_squared_to(pw)
			if d_sq <= hit_rad_sq:
				var falloff: float = 1.0 - sqrt(d_sq) / hit_radius
				agitates[idx] = clampf(maxf(agitates[idx], falloff * strength), 0.0, 1.0)
				mmi.multimesh.set_instance_custom_data(idx, Color(seeds[idx], agitates[idx], domes[idx], rots[idx]))


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
	_spawn_explosion_fx(pos, Color(1.0, 0.6, 0.2), true, 3.2)
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


func try_pickup_nearby(actor: Variant, only_c4_or_primary: bool = true) -> Dictionary:
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
	# Decal persistente de impacto o sangre
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.085, 0.085, 0.010) if material_name == "flesh" else Vector3(0.055, 0.055, 0.010)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.03, 0.03, 0.92) if material_name == "flesh" else Color(0.11, 0.11, 0.12, 0.90)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.mesh = bm
	mi.material_override = mat
	round_props_root.add_child(mi)
	mi.global_position = pos + normal * 0.008
	if absf(normal.y) < 0.999:
		mi.look_at(pos + normal * 2.0, Vector3.UP)
	else:
		mi.rotation_degrees = Vector3(-90.0 if normal.y > 0.0 else 90.0, 0.0, 0.0)
	_tracer_pool.append({"node": mi, "timer": 8.0})

	# Ráfaga animada de polvo / chispas / sangre usando atlas de partículas
	var puff_tex: Texture2D = _blast_atlas_tex if material_name == "metal" else _smoke_atlas_tex
	var puff_col: Color = Color(0.65, 0.08, 0.08, 0.85) if material_name == "flesh" else (Color(1.0, 0.85, 0.45, 0.9) if material_name == "metal" else Color(0.84, 0.80, 0.72, 0.55))
	_spawn_atlas_quad(pos + normal * 0.09, puff_tex, puff_col, 0.28, 0.55, 0.26, material_name == "metal")


func _spawn_explosion_fx(pos: Vector3, col: Color, full_blast: bool = true, scale_mult: float = 1.0) -> void:
	if full_blast:
		_spawn_atlas_quad(pos + Vector3(0.0, 0.85 * scale_mult, 0.0), _fireburst_atlas_tex, Color(1.0, 0.92, 0.78, 0.98), 2.4 * scale_mult, 4.8 * scale_mult, 0.52, true)
		_spawn_atlas_quad(pos + Vector3(0.0, 0.65 * scale_mult, 0.0), _blast_atlas_tex, Color(1.0, 0.75, 0.42, 0.95), 2.2 * scale_mult, 4.4 * scale_mult, 0.42, true)
		_spawn_atlas_quad(pos + Vector3(0.0, 1.15 * scale_mult, 0.0), _smoke_atlas_tex, Color(0.32, 0.30, 0.28, 0.82), 2.2 * scale_mult, 5.4 * scale_mult, 1.05, false)
	else:
		_spawn_atlas_quad(pos + Vector3(0.0, 0.45, 0.0), _fireburst_atlas_tex, Color(col.r, col.g, col.b, 0.90), 1.4, 2.5, 0.22, true)

	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 6.5 * scale_mult
	light.omni_range = 12.0 * scale_mult
	round_props_root.add_child(light)
	light.global_position = pos + Vector3(0.0, 0.6, 0.0)
	_tracer_pool.append({"node": light, "timer": 0.16})


func _spawn_atlas_quad(
	pos: Vector3, tex: Texture2D, col: Color, s0: float, s1: float, dur: float, additive: bool
) -> void:
	var q_node := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	q_node.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = col
	if tex != null:
		mat.albedo_texture = tex
	mat.uv1_scale = Vector3(0.25, 0.25, 1.0)
	q_node.material_override = mat
	round_props_root.add_child(q_node)
	q_node.global_position = pos
	q_node.scale = Vector3.ONE * s0
	_atlas_fx_pool.append({
		"node": q_node,
		"mat": mat,
		"elapsed": 0.0,
		"duration": dur,
		"cols": 4,
		"rows": 4,
		"base_alpha": col.a,
		"scale_start": s0,
		"scale_end": s1,
	})
