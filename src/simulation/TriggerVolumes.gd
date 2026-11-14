class_name TriggerVolumes
extends RefCounted

var _buy_zones: Array = []
var _bomb_sites: Array = []
var _callouts: Array = []
var _convex_cache: Dictionary = {}


func configure(buy_zones_data: Dictionary, places_data: Dictionary) -> void:
	_buy_zones = buy_zones_data.get("zones", [])
	_bomb_sites.clear()
	for site_entry in buy_zones_data.get("sites", []):
		var site_idx: int = int(site_entry.get("site", -1))
		var raw_hulls: Array = site_entry.get("hulls", [])
		var fixed_hulls: Array = []
		for h in raw_hulls:
			var copy: Dictionary = h.duplicate(true)
			if site_idx == 0 and copy.has("max"):
				var max_arr: Array = copy["max"].duplicate()
				max_arr[1] = 192.0 * 0.0254
				copy["max"] = max_arr
			fixed_hulls.append(copy)
		_bomb_sites.append({"site": site_idx, "hulls": fixed_hulls})
	_callouts = places_data.get("locations", [])
	_convex_cache.clear()


func in_buy_zone(pos: Vector3, team: String, radius: float = 0.0, height: float = 0.0) -> bool:
	for zone in _buy_zones:
		if str(zone.get("team", "")) == team and touches_box(pos, zone, radius, height):
			return true
	return false


func bomb_site_at(pos: Vector3, radius: float = 0.0, height: float = 0.0) -> int:
	for site_entry in _bomb_sites:
		var site_idx: int = int(site_entry.get("site", -1))
		for box in site_entry.get("hulls", []):
			if touches_box(pos, box, radius, height):
				return site_idx
	return -1


func callout_at(pos: Vector3) -> String:
	var x: float = pos.x
	var y: float = pos.y + 0.9
	var z: float = pos.z
	for loc in _callouts:
		for hull in loc.get("hulls", []):
			var bmin: Array = hull.get("min", [0, 0, 0])
			var bmax: Array = hull.get("max", [0, 0, 0])
			if (
				x < float(bmin[0])
				or x > float(bmax[0])
				or y < float(bmin[1])
				or y > float(bmax[1])
				or z < float(bmin[2])
				or z > float(bmax[2])
			):
				continue
			var planes: Array = hull.get("planes", [])
			var inside: bool = true
			for pl in planes:
				var d: float = (
					float(pl[0]) * x + float(pl[1]) * y + float(pl[2]) * z
				)
				if d > float(pl[3]) + 0.001:
					inside = false
					break
			if inside:
				return str(loc.get("name", "DUST II"))
	return "Dust II"


func touches_box(pos: Vector3, zone: Dictionary, radius: float = 0.0, height: float = 0.0) -> bool:
	if radius < 0.0 or height < 0.0:
		return false
	var bmin: Array = zone.get("min", [0, 0, 0])
	var bmax: Array = zone.get("max", [0, 0, 0])
	var eps: float = 1e-6
	var overlaps_aabb: bool = (
		pos.x + radius >= float(bmin[0]) - eps
		and pos.x - radius <= float(bmax[0]) + eps
		and pos.y + height >= float(bmin[1]) - eps
		and pos.y <= float(bmax[1]) + eps
		and pos.z + radius >= float(bmin[2]) - eps
		and pos.z - radius <= float(bmax[2]) + eps
	)
	if not overlaps_aabb:
		return false
	var planes: Array = zone.get("planes", [])
	if planes.is_empty():
		return true
	var shape: Dictionary = _get_convex_shape(zone)
	var vertices: Array = shape["vertices"]
	var axes: Array = shape["axes"]
	if vertices.is_empty():
		return overlaps_aabb
	var center := Vector3(pos.x, pos.y + height * 0.5, pos.z)
	for axis_var in axes:
		var axis: Vector3 = axis_var
		var vmin: float = INF
		var vmax: float = -INF
		for v_var in vertices:
			var v: Vector3 = v_var
			var val: float = axis.dot(v)
			vmin = minf(vmin, val)
			vmax = maxf(vmax, val)
		var proj: float = axis.dot(center)
		var extent: float = (
			radius * (absf(axis.x) + absf(axis.z)) + (height * 0.5) * absf(axis.y)
		)
		if proj + extent < vmin - eps or proj - extent > vmax + eps:
			return false
	return true


func _get_convex_shape(zone: Dictionary) -> Dictionary:
	var key: int = zone.hash()
	if _convex_cache.has(key):
		return _convex_cache[key]
	var planes: Array = zone.get("planes", [])
	var vertices: Array = []
	var axes: Array = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
	for i in range(planes.size()):
		var a := Vector3(float(planes[i][0]), float(planes[i][1]), float(planes[i][2]))
		var ad: float = float(planes[i][3])
		_add_axis(axes, a)
		for j in range(i + 1, planes.size()):
			var b := Vector3(float(planes[j][0]), float(planes[j][1]), float(planes[j][2]))
			var bd: float = float(planes[j][3])
			var edge: Vector3 = a.cross(b)
			_add_axis(axes, edge.cross(Vector3(1, 0, 0)))
			_add_axis(axes, edge.cross(Vector3(0, 1, 0)))
			_add_axis(axes, edge.cross(Vector3(0, 0, 1)))
			for k in range(j + 1, planes.size()):
				var c := Vector3(float(planes[k][0]), float(planes[k][1]), float(planes[k][2]))
				var cd: float = float(planes[k][3])
				var bc: Vector3 = b.cross(c)
				var det: float = a.dot(bc)
				if absf(det) < 1e-8:
					continue
				var ca: Vector3 = c.cross(a)
				var ab: Vector3 = a.cross(b)
				var v: Vector3 = (bc * ad + ca * bd + ab * cd) / det
				var ok: bool = true
				for pl in planes:
					var pn := Vector3(float(pl[0]), float(pl[1]), float(pl[2]))
					if pn.dot(v) > float(pl[3]) + 1e-5:
						ok = false
						break
				if ok:
					vertices.append(v)
	var shape := {"vertices": vertices, "axes": axes}
	_convex_cache[key] = shape
	return shape


func _add_axis(axes: Array, axis: Vector3) -> void:
	var len_sq: float = axis.length_squared()
	if len_sq < 1e-12:
		return
	var norm: Vector3 = axis / sqrt(len_sq)
	for existing_var in axes:
		var existing: Vector3 = existing_var
		if absf(existing.dot(norm)) > 1.0 - 1e-6:
			return
	axes.append(norm)
