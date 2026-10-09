extends RefCounted

const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
const COSTS := [10, 19, 10, 19, 10, 19, 10, 19]

static func rendered_segments(path: PackedVector2Array, foreground: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(path.size() - 1):
		var delta := path[i + 1] - path[i]
		if delta.is_zero_approx():
			continue
		var diagonal := not is_zero_approx(delta.x) and not is_zero_approx(delta.y)
		var length := absf(delta.x) * 1.41 if diagonal else delta.length()
		var padding := 6.0
		if foreground and is_zero_approx(delta.y):
			padding = 3.0
		elif not foreground and is_zero_approx(delta.x) and delta.y > 0:
			padding = 5.0
		var center := (path[i] + path[i + 1]) * 0.5
		var extent := delta.normalized() * (length + padding) * 0.5
		result.append(center - extent)
		result.append(center + extent)
	return result

static func direct_path(start: Vector2, end: Vector2) -> PackedVector2Array:
	var delta := end - start
	var diagonal := minf(absf(delta.x), absf(delta.y))
	var corner := end - Vector2(signf(delta.x), signf(delta.y)) * diagonal
	var result := PackedVector2Array([start])
	if not corner.is_equal_approx(start) and not corner.is_equal_approx(end):
		result.append(corner)
	result.append(end)
	return result

static func compress(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		if not result.is_empty() and result[-1].is_equal_approx(point):
			continue
		while result.size() >= 2:
			var incoming := result[-1] - result[-2]
			var outgoing := point - result[-1]
			if not is_zero_approx(incoming.cross(outgoing)):
				break
			result.remove_at(result.size() - 1)
		if result.is_empty() or not result[-1].is_equal_approx(point):
			result.append(point)
	return result

static func route_grid(start: Vector2i, end: Vector2i, blocked: Dictionary = {}, fast := true) -> PackedVector2Array:
	if start == end:
		return PackedVector2Array([Vector2(start), Vector2(end)])
	if fast:
		var direct := direct_path(Vector2(start), Vector2(end))
		var clear := true
		for point: Vector2i in blocked:
			if point == start or point == end:
				continue
			for i in range(direct.size() - 1):
				if Geometry2D.get_closest_point_to_segment(Vector2(point), direct[i], direct[i + 1]).is_equal_approx(Vector2(point)):
					clear = false
					break
			if not clear:
				break
		if clear:
			return direct
	var positions: Array[Vector2i] = [end]
	var costs := PackedInt32Array([0])
	var parents := PackedInt32Array([-1])
	var indices := {end: 0}
	var open: Array = []
	var current := 0
	var current_cost := 0
	for iteration in range(3000):
		for direction in range(DIRECTIONS.size()):
			var point: Vector2i = positions[current] + DIRECTIONS[direction]
			if point == start:
				var result := PackedVector2Array([Vector2(start)])
				var index := current
				while index >= 0:
					result.append(Vector2(positions[index]))
					index = parents[index]
				return compress(result)
			if blocked.has(point):
				continue
			var cost: int = current_cost + COSTS[direction]
			var index: int = indices.get(point, -1)
			if index >= 0 and costs[index] <= cost:
				continue
			if index < 0:
				index = positions.size()
				indices[point] = index
				positions.append(point)
				costs.append(cost)
				parents.append(current)
			else:
				costs[index] = cost
				parents[index] = current
			var distance: Vector2i = start - point
			open.append([index, cost, cost + (absi(distance.x) + absi(distance.y)) * 10])
		if open.is_empty() or open.size() > 5000:
			break
		var best := 0
		for i in range(1, open.size()):
			if open[i][2] < open[best][2]:
				best = i
		current = open[best][0]
		current_cost = open[best][1]
		open[best] = open[-1]
		open.pop_back()
	return PackedVector2Array()

static func route(start: Vector2, end: Vector2, source: Rect2, target: Rect2) -> PackedVector2Array:
	if end.x > start.x:
		return direct_path(start, end)
	var step := 16.0
	var origin := start + Vector2(32, 0)
	var entry := end - Vector2(32, 0)
	if not source.position.is_equal_approx(target.position):
		var top := minf(source.position.y, target.position.y) - 32
		var bottom := maxf(source.end.y, target.end.y) + 32
		var lane := top if absf(start.y - top) + absf(end.y - top) <= absf(start.y - bottom) + absf(end.y - bottom) else bottom
		return compress(PackedVector2Array([start, origin, Vector2(origin.x, lane), Vector2(entry.x, lane), entry, end]))
	var goal := Vector2i(roundi((entry.x - origin.x) / step), roundi((entry.y - origin.y) / step))
	var blocked := {}
	for bounds in [source.grow(4), target.grow(4)]:
		var first := Vector2i(ceili((bounds.position.x - origin.x) / step), ceili((bounds.position.y - origin.y) / step))
		var last := Vector2i(floori((bounds.end.x - origin.x) / step), floori((bounds.end.y - origin.y) / step))
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				blocked[Vector2i(x, y)] = true
	blocked.erase(Vector2i.ZERO)
	blocked.erase(goal)
	var path := route_grid(Vector2i.ZERO, goal, blocked)
	var result := PackedVector2Array([start, origin])
	if path.is_empty():
		var lane := minf(source.position.y, target.position.y) - 32
		result.append(Vector2(origin.x, lane))
		result.append(Vector2(entry.x, lane))
	else:
		for point in path:
			result.append(origin + point * step)
		var bridge := direct_path(result[-1], entry)
		result.append_array(bridge)
	result.append(entry)
	result.append(end)
	return compress(result)
