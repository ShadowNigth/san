class_name NavGraph
extends RefCounted

var areas: Array = []
var id_to_index: Dictionary = {}
var spawns: Dictionary = {"t": [], "ct": []}
var spawn_angles: Dictionary = {"t": [], "ct": []}
var sites: Array = []
var bounds: Array = [-60.0, -80.0, 50.0, 35.0]

# Grilla espacial de 4 m para lookup rápido
var _cell_size: float = 4.0
var _cells: Dictionary = {}
var _areas_by_place: Dictionary = {}


func configure(nav_data: Dictionary) -> void:
	areas = nav_data.get("areas", [])
	id_to_index.clear()
	_cells.clear()
	_areas_by_place.clear()
	for i in range(areas.size()):
		var area: Dictionary = areas[i]
		id_to_index[int(area.get("id", i))] = i
		var place: String = str(area.get("place", ""))
		if not place.is_empty():
			if not _areas_by_place.has(place):
				_areas_by_place[place] = []
			_areas_by_place[place].append(i)
		var rect: Array = area.get("rect", [0, 0, 0, 0])
		var x0: int = int(floor(float(rect[0]) / _cell_size))
		var z0: int = int(floor(float(rect[1]) / _cell_size))
		var x1: int = int(floor(float(rect[2]) / _cell_size))
		var z1: int = int(floor(float(rect[3]) / _cell_size))
		for gx in range(x0, x1 + 1):
			for gz in range(z0, z1 + 1):
				var key := Vector2i(gx, gz)
				if not _cells.has(key):
					_cells[key] = []
				(_cells[key] as Array).append(i)

	spawns = nav_data.get("spawns", {"t": [], "ct": []})
	spawn_angles = nav_data.get("spawnAngles", {"t": [], "ct": []})
	sites = nav_data.get("sites", [[28.2448, 3.6576, -62.992], [-39.0144, 1.2192, -68.072]])
	bounds = nav_data.get("bounds", [-55.9181, -79.1337, 45.3517, 29.4894])


func get_spawn_position(team: String, index: int) -> Vector3:
	var arr: Array = spawns.get(team, [])
	if arr.is_empty():
		return Vector3(-20.0, 4.0, 20.0) if team == "t" else Vector3(7.0, -2.5, -60.0)
	var p: Array = arr[index % arr.size()]
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func get_spawn_yaw(team: String, index: int) -> float:
	var arr: Array = spawn_angles.get(team, [])
	if arr.is_empty():
		return 0.0 if team == "t" else PI
	return float(arr[index % arr.size()])


func get_site_position(site_index: int) -> Vector3:
	if site_index < 0 or site_index >= sites.size():
		return Vector3.ZERO
	var p: Array = sites[site_index]
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func area_center(idx: int) -> Vector3:
	var c: Array = areas[idx]["center"]
	return Vector3(float(c[0]), float(c[1]), float(c[2]))


func nearest_area(pos: Vector3) -> int:
	if areas.is_empty():
		return -1
	var gx: int = int(floor(pos.x / _cell_size))
	var gz: int = int(floor(pos.z / _cell_size))
	var best_idx: int = -1
	var best_score: float = INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(gx + dx, gz + dz)
			if not _cells.has(key):
				continue
			var bucket: Array = _cells[key]
			for idx_var in bucket:
				var idx: int = int(idx_var)
				var c: Vector3 = area_center(idx)
				var dy: float = absf(c.y - pos.y)
				var d2: float = (c.x - pos.x) * (c.x - pos.x) + (c.z - pos.z) * (c.z - pos.z) + dy * dy * 9.0
				if d2 < best_score:
					best_score = d2
					best_idx = idx
	if best_idx >= 0:
		return best_idx
	for i in range(areas.size()):
		var c: Vector3 = area_center(i)
		var dy: float = absf(c.y - pos.y)
		var d2: float = (c.x - pos.x) * (c.x - pos.x) + (c.z - pos.z) * (c.z - pos.z) + dy * dy * 9.0
		if d2 < best_score:
			best_score = d2
			best_idx = i
	return best_idx


func get_areas_in_place(place_name: String) -> Array:
	return _areas_by_place.get(place_name, [])


func find_path(from: Vector3, to: Vector3, avoid_points: Array = []) -> PackedVector3Array:
	var result := PackedVector3Array()
	if areas.is_empty():
		result.append(to)
		return result
	var start_idx: int = nearest_area(from)
	var goal_idx: int = nearest_area(to)
	if start_idx < 0 or goal_idx < 0:
		result.append(to)
		return result
	if start_idx == goal_idx:
		result.append(to)
		return result

	var n: int = areas.size()
	var g_cost := PackedFloat32Array()
	g_cost.resize(n)
	g_cost.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	closed.fill(0)

	var goal_pos: Vector3 = area_center(goal_idx)
	g_cost[start_idx] = 0.0

	var heap_nodes: Array[int] = [start_idx]
	var heap_scores: Array[float] = [area_center(start_idx).distance_to(goal_pos)]

	var iterations: int = 0
	var max_iters: int = mini(n * 4, 8000)

	while not heap_nodes.is_empty() and iterations < max_iters:
		iterations += 1
		var current: int = heap_nodes[0]
		var last_node: int = heap_nodes.pop_back()
		var last_score: float = heap_scores.pop_back()
		if not heap_nodes.is_empty():
			heap_nodes[0] = last_node
			heap_scores[0] = last_score
			_heap_down(heap_nodes, heap_scores, 0)

		if closed[current] == 1:
			continue
		closed[current] = 1

		if current == goal_idx:
			break

		var cur_area: Dictionary = areas[current]
		var cur_pos: Vector3 = area_center(current)
		var links: Array = cur_area.get("links", [])
		for link_id_var in links:
			var link_id: int = int(link_id_var)
			if not id_to_index.has(link_id):
				continue
			var nb: int = int(id_to_index[link_id])
			if closed[nb] == 1:
				continue
			var nb_pos: Vector3 = area_center(nb)
			var step_cost: float = cur_pos.distance_to(nb_pos)
			if absf(nb_pos.y - cur_pos.y) > 0.6:
				step_cost *= 1.35
			for ap in avoid_points:
				if nb_pos.distance_squared_to(ap) < 16.0:
					step_cost += 12.0
			var tentative: float = g_cost[current] + step_cost
			if tentative < g_cost[nb]:
				g_cost[nb] = tentative
				prev[nb] = current
				var f_score: float = tentative + nb_pos.distance_to(goal_pos)
				heap_nodes.append(nb)
				heap_scores.append(f_score)
				_heap_up(heap_nodes, heap_scores, heap_nodes.size() - 1)

	if prev[goal_idx] == -1 and start_idx != goal_idx:
		result.append(to)
		return result

	var rev_indices: Array[int] = []
	var cur: int = goal_idx
	while cur != -1:
		rev_indices.append(cur)
		if cur == start_idx:
			break
		cur = prev[cur]
	rev_indices.reverse()

	for i in range(rev_indices.size()):
		var a_idx: int = rev_indices[i]
		if i > 0 and i < rev_indices.size():
			var prev_idx: int = rev_indices[i - 1]
			var portals: Dictionary = areas[prev_idx].get("portals", {})
			var target_id_str: String = str(int(areas[a_idx].get("id", -1)))
			if portals.has(target_id_str):
				var pp: Array = portals[target_id_str]
				result.append(Vector3(float(pp[0]), float(pp[1]), float(pp[2])))
		result.append(area_center(a_idx))
	result.append(to)
	return result


func _heap_up(nodes: Array[int], scores: Array[float], idx: int) -> void:
	var i: int = idx
	while i > 0:
		var parent: int = (i - 1) >> 1
		if scores[i] >= scores[parent]:
			break
		var tn: int = nodes[i]
		var ts: float = scores[i]
		nodes[i] = nodes[parent]
		scores[i] = scores[parent]
		nodes[parent] = tn
		scores[parent] = ts
		i = parent


func _heap_down(nodes: Array[int], scores: Array[float], idx: int) -> void:
	var i: int = idx
	var size: int = nodes.size()
	while true:
		var left: int = (i << 1) + 1
		var right: int = left + 1
		var smallest: int = i
		if left < size and scores[left] < scores[smallest]:
			smallest = left
		if right < size and scores[right] < scores[smallest]:
			smallest = right
		if smallest == i:
			break
		var tn: int = nodes[i]
		var ts: float = scores[i]
		nodes[i] = nodes[smallest]
		scores[i] = scores[smallest]
		nodes[smallest] = tn
		scores[smallest] = ts
		i = smallest
