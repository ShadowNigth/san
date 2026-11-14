class_name GrenadeProjectile
extends Node3D

var kind: String = "he"
var thrower: Node = null
var thrower_team: String = "ct"
var velocity := Vector3.ZERO
var fuse_timer: float = 1.6
var decoy_timer: float = 0.0
var decoy_shots: int = 0
var world_ref: Node = null
var _resting: bool = false
var _mesh_node: Node3D = null


func setup(
	p_kind: String,
	p_pos: Vector3,
	p_vel: Vector3,
	p_thrower: Node,
	p_world: Node
) -> void:
	kind = p_kind
	global_position = p_pos
	velocity = p_vel
	thrower = p_thrower
	thrower_team = p_thrower.team if p_thrower != null else "ct"
	world_ref = p_world
	match kind:
		"he":
			fuse_timer = 1.6
		"flash":
			fuse_timer = 1.45
		"smoke":
			fuse_timer = 1.7
		"molotov", "incendiary":
			fuse_timer = 2.0
		"decoy":
			fuse_timer = 15.0
			decoy_timer = 0.35
	_load_model()


func _load_model() -> void:
	var path: String = "res://assets/models/grenades/%s.glb" % kind
	var loaded: PackedScene = null
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is PackedScene:
			loaded = res
	if loaded != null:
		_mesh_node = loaded.instantiate() as Node3D
		if _mesh_node != null:
			add_child(_mesh_node)
			return
	var fallback := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	fallback.mesh = sphere
	add_child(fallback)
	_mesh_node = fallback


func _physics_process(delta: float) -> void:
	if _mesh_node != null and not _resting:
		_mesh_node.rotate_x(delta * 9.0)
		_mesh_node.rotate_y(delta * 6.0)

	if not _resting:
		velocity.y -= GrenadeMath.GRAVITY * delta
		var step: Vector3 = velocity * delta
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + step + step.normalized() * GrenadeMath.GRENADE_RADIUS,
			1
		)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			global_position += step
		else:
			var hit_pos: Vector3 = hit["position"]
			var normal: Vector3 = hit["normal"]
			global_position = hit_pos + normal * GrenadeMath.GRENADE_RADIUS
			if (kind == "molotov" or kind == "incendiary") and GrenadeMath.fire_impact_allowed(normal.y):
				_detonate()
				return
			var b: Dictionary = GrenadeMath.bounce(velocity, normal)
			velocity = b["velocity"]
			_resting = bool(b["resting"])
			if float(b["impact"]) > 1.2:
				AudioManager.play_3d("utility-%s-bounce" % kind, global_position, 24.0, -5.0)
			if kind == "smoke" and _resting:
				_detonate()
				return

	if kind == "decoy" and _resting:
		decoy_timer -= delta
		if decoy_timer <= 0.0 and decoy_shots < 18:
			decoy_shots += 1
			decoy_timer = randf_range(0.35, 0.9)
			var fake_w: int = 0 if thrower_team == "t" else 9
			AudioManager.play_weapon_shot(fake_w, global_position, false, false)

	fuse_timer -= delta
	if fuse_timer <= 0.0:
		_detonate()


func _detonate() -> void:
	if world_ref != null and world_ref.has_method("detonate_grenade"):
		world_ref.detonate_grenade(kind, global_position, thrower, thrower_team)
	queue_free()
