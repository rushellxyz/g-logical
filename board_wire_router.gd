extends RefCounted

const WireGeometry = preload("res://wire_geometry.gd")
const CELL := 256.0
const CLEARANCE := 12.0
var obstacles: Array[Rect2] = []
var buckets := {}
var tracks := {}
var track_segments: Array[Vector4] = []
var track_sources := PackedVector2Array()
var track_targets := PackedVector2Array()
var departures := {}
var arrivals := {}
var active_source := Vector2(INF, INF)
var active_target := Vector2(INF, INF)
var cancel_check: Callable
var deadline := 0
var board_bounds := Rect2()

func cancelled() -> bool:
	return (deadline > 0 and Time.get_ticks_usec() >= deadline) or (cancel_check.is_valid() and cancel_check.call())

func configure(bounds: Array[Rect2]) -> void:
	obstacles.clear()
	buckets.clear()
	tracks.clear()
	track_segments.clear()
	track_sources.clear()
	track_targets.clear()
	departures.clear()
	arrivals.clear()
	board_bounds = Rect2() if bounds.is_empty() else bounds[0]
	for bounds_item in bounds:
		board_bounds = board_bounds.merge(bounds_item)
		var rect := bounds_item.grow(CLEARANCE)
		var index := obstacles.size()
		obstacles.append(rect)
		var first := Vector2i((rect.position / CELL).floor())
		var last := Vector2i((rect.end / CELL).floor())
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				var key := Vector2i(x, y)
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(index)

func intersection(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var low := 0.0
	var high := 1.0
	var delta := b - a
	for axis in range(2):
		if is_zero_approx(delta[axis]):
			if a[axis] <= rect.position[axis] or a[axis] >= rect.end[axis]:
				return false
		else:
			var near := (rect.position[axis] - a[axis]) / delta[axis]
			var far := (rect.end[axis] - a[axis]) / delta[axis]
			low = maxf(low, minf(near, far))
			high = minf(high, maxf(near, far))
			if low >= high:
				return false
	return high > 0.00001 and low < 0.99999

func blocker(a: Vector2, b: Vector2) -> int:
	var cell := Vector2i((a / CELL).floor())
	var last := Vector2i((b / CELL).floor())
	var delta := b - a
	var step := Vector2i(signi(last.x - cell.x), signi(last.y - cell.y))
	var interval := Vector2(INF, INF)
	var next := Vector2(INF, INF)
	for axis in range(2):
		if step[axis] != 0:
			interval[axis] = absf(CELL / delta[axis])
			var boundary := (cell[axis] + (1 if step[axis] > 0 else 0)) * CELL
			next[axis] = (boundary - a[axis]) / delta[axis]
	for i in range(absi(last.x - cell.x) + absi(last.y - cell.y) + 1):
		for index: int in buckets.get(cell, []):
			if intersection(a, b, obstacles[index]):
				return index
		if cell == last:
			break
		var axis := 0 if next.x < next.y else 1
		cell[axis] += step[axis]
		next[axis] += interval[axis]
	return -1

func track(a: Vector2, b: Vector2) -> Vector4:
	var delta := b - a
	if is_zero_approx(delta.y):
		return Vector4(0, a.y, minf(a.x, b.x), maxf(a.x, b.x))
	if is_zero_approx(delta.x):
		return Vector4(1, a.x, minf(a.y, b.y), maxf(a.y, b.y))
	var sign_y := signf(delta.y / delta.x)
	var first := (a.x + sign_y * a.y) / sqrt(2.0)
	var last := (b.x + sign_y * b.y) / sqrt(2.0)
	return Vector4(2 if sign_y > 0 else 3, (a.y - sign_y * a.x) / sqrt(2.0), minf(first, last), maxf(first, last))

func overlap(a: Vector2, b: Vector2) -> float:
	var line := track(a, b)
	var lane := roundi(line.y / CLEARANCE)
	var result := 0.0
	var seen := {}
	for offset in range(-1, 2):
		for cell in range(floori(line.z / CELL), floori(line.w / CELL) + 1):
			for index: int in tracks.get(Vector3i(int(line.x), lane + offset, cell), []):
				if seen.has(index):
					continue
				seen[index] = true
				var occupied := track_segments[index]
				if absf(occupied.y - line.y) < CLEARANCE:
					result += maxf(0, minf(line.w, occupied.w) - maxf(line.z, occupied.z))
	return result

func wire_blocker(a: Vector2, b: Vector2) -> int:
	if a.is_equal_approx(b):
		return -1
	var line := track(a, b)
	var lane := roundi(line.y / CLEARANCE)
	for offset in range(-1, 2):
		for cell in range(floori(line.z / CELL), floori(line.w / CELL) + 1):
			for index: int in tracks.get(Vector3i(int(line.x), lane + offset, cell), []):
				if (active_source.is_finite() and track_sources[index] == active_source) or (active_target.is_finite() and track_targets[index] == active_target):
					continue
				var occupied := track_segments[index]
				if absf(occupied.y - line.y) < CLEARANCE and minf(line.w, occupied.w) - maxf(line.z, occupied.z) > 0.001:
					return index
	return -1

func wire_rect(index: int) -> Rect2:
	var line := track_segments[index]
	var a: Vector2
	var b: Vector2
	match int(line.x):
		0:
			a = Vector2(line.z, line.y)
			b = Vector2(line.w, line.y)
		1:
			a = Vector2(line.y, line.z)
			b = Vector2(line.y, line.w)
		_:
			var slope := 1.0 if line.x == 2 else -1.0
			a = Vector2(line.z - slope * line.y, slope * line.z + line.y) / sqrt(2.0)
			b = Vector2(line.w - slope * line.y, slope * line.w + line.y) / sqrt(2.0)
	return Rect2(a, Vector2.ZERO).expand(b).grow(16)

func shifted_paths(path: PackedVector2Array, segment: int) -> Array[PackedVector2Array]:
	var a := path[segment]
	var b := path[segment + 1]
	var direction := (b - a).sign()
	var normal := Vector2(-direction.y, direction.x) * 16
	var result: Array[PackedVector2Array] = []
	for side in [-1, 1]:
		var candidate := PackedVector2Array()
		for i in range(segment + 1):
			candidate.append(path[i])
		candidate.append(a + normal * side)
		candidate.append(b + normal * side)
		for i in range(segment + 1, path.size()):
			candidate.append(path[i])
		result.append(WireGeometry.compress(candidate))
	return result

func path_length(path: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(path.size() - 1):
		length += path[i].distance_to(path[i + 1])
	return length

func clear_path(path: PackedVector2Array) -> bool:
	for i in range(path.size() - 1):
		if blocker(path[i], path[i + 1]) >= 0 or wire_blocker(path[i], path[i + 1]) >= 0:
			return false
	return true

func simplify(path: PackedVector2Array) -> PackedVector2Array:
	var result := WireGeometry.compress(path)
	var stop_at := Time.get_ticks_usec() + 1500
	var index := 0
	while index < result.size() - 2 and Time.get_ticks_usec() < stop_at:
		var changed := false
		for last in range(mini(result.size() - 1, index + 12), index + 1, -1):
			var original := result.slice(index, last + 1)
			var a := original[0]
			var b := original[-1]
			var backwards := WireGeometry.direct_path(b, a)
			backwards.reverse()
			var alternatives: Array[PackedVector2Array] = [WireGeometry.direct_path(a, b), backwards, WireGeometry.compress(PackedVector2Array([a, Vector2(b.x, a.y), b])), WireGeometry.compress(PackedVector2Array([a, Vector2(a.x, b.y), b]))]
			var replacement := original
			var length := path_length(original)
			for candidate in alternatives:
				var candidate_length := path_length(candidate)
				if candidate_length > length + 0.001 or (is_equal_approx(candidate_length, length) and candidate.size() >= replacement.size()):
					continue
				if clear_path(candidate):
					replacement = candidate
					length = candidate_length
			if replacement != original:
				var shortened := result.slice(0, index)
				shortened.append_array(replacement)
				shortened.append_array(result.slice(last + 1))
				result = WireGeometry.compress(shortened)
				changed = true
				break
		if not changed:
			index += 1
	return result

func reserve(path: PackedVector2Array) -> void:
	departures[path[0]] = departures.get(path[0], 0) + 1
	arrivals[path[-1]] = arrivals.get(path[-1], 0) + 1
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var direction := (b - a).normalized()
		if i == 0:
			a += direction * minf(48, a.distance_to(b))
		if i == path.size() - 2:
			b -= direction * minf(48, a.distance_to(b))
		if a.is_equal_approx(b):
			continue
		var line := track(a, b)
		var index := track_segments.size()
		track_segments.append(line)
		track_sources.append(path[0] if i == 0 and is_zero_approx(b.y - a.y) else Vector2(INF, INF))
		track_targets.append(path[-1] if i == path.size() - 2 and is_zero_approx(b.y - a.y) else Vector2(INF, INF))
		for cell in range(floori(line.z / CELL), floori(line.w / CELL) + 1):
			var key := Vector3i(int(line.x), roundi(line.y / CLEARANCE), cell)
			if not tracks.has(key):
				tracks[key] = []
			tracks[key].append(index)

func route(start: Vector2, end: Vector2, source: Rect2, target: Rect2, retry := 0) -> PackedVector2Array:
	if retry == 0:
		deadline = Time.get_ticks_usec() + 50000
	if cancelled():
		return PackedVector2Array()
	active_source = start
	active_target = end
	var exit := start + Vector2(32 + departures.get(start, 0) * 16, 0)
	var entry := end - Vector2(32 + arrivals.get(end, 0) * 16, 0)
	while exit.x > start.x + 32 and (blocker(start + Vector2(32, 0), exit) >= 0 or wire_blocker(start + Vector2(32, 0), exit) >= 0):
		exit.x -= 16
	while entry.x < end.x - 32 and (blocker(entry, end - Vector2(32, 0)) >= 0 or wire_blocker(entry, end - Vector2(32, 0)) >= 0):
		entry.x += 16
	if retry > 0:
		var offsets := [Vector2(16, -16), Vector2(16, 16), Vector2(24, -24), Vector2(24, 24)]
		if retry <= 4:
			entry = end + Vector2(-offsets[retry - 1].x, offsets[retry - 1].y)
		else:
			exit = start + offsets[retry - 5]
	var candidates: Array[PackedVector2Array] = [WireGeometry.direct_path(exit, entry)]
	var minimum_length := 0.0
	for i in range(candidates[0].size() - 1):
		minimum_length += candidates[0][i].distance_to(candidates[0][i + 1])
	var lanes := [minf(source.position.y, target.position.y) - 32, maxf(source.end.y, target.end.y) + 32, (exit.y + entry.y) * 0.5]
	for lane: float in lanes:
		for offset in [0.0, -16.0, 16.0, -32.0, 32.0]:
			candidates.append(PackedVector2Array([exit, Vector2(exit.x, lane + offset), Vector2(entry.x, lane + offset), entry]))
	if entry.x > exit.x:
		for fraction in [0.25, 0.5, 0.75]:
			var x := lerpf(exit.x, entry.x, fraction)
			candidates.append(PackedVector2Array([exit, Vector2(x, exit.y), Vector2(x, entry.y), entry]))
	for source_y in [source.position.y - 32, source.end.y + 32]:
		for target_y in [target.position.y - 32, target.end.y + 32]:
			for x in [(exit.x + entry.x) * 0.5, exit.x + 16, entry.x - 16, board_bounds.position.x - 32, board_bounds.end.x + 32]:
				candidates.append(PackedVector2Array([exit, Vector2(exit.x, source_y), Vector2(x, source_y), Vector2(x, target_y), Vector2(entry.x, target_y), entry]))
	var best := PackedVector2Array()
	var best_score := INF
	var expanded := {}
	var seen_paths := {}
	var cursor := 0
	while cursor < candidates.size() and cursor < 128:
		if cancelled():
			return PackedVector2Array()
		var path := WireGeometry.compress(candidates[cursor])
		cursor += 1
		if seen_paths.has(path):
			continue
		seen_paths[path] = true
		var score := 0.0
		var hit := -1
		var wire_hit := -1
		for i in range(path.size() - 1):
			hit = blocker(path[i], path[i + 1])
			if hit >= 0:
				break
			wire_hit = wire_blocker(path[i], path[i + 1])
			if wire_hit >= 0:
				candidates.append_array(shifted_paths(path, i))
				break
			score += path[i].distance_to(path[i + 1])
		if hit >= 0:
			if not expanded.has(hit):
				expanded[hit] = true
				var rect := obstacles[hit].grow(4)
				for y in [rect.position.y, rect.end.y]:
					candidates.append(PackedVector2Array([exit, Vector2(exit.x, y), Vector2(entry.x, y), entry]))
				for x in [rect.position.x, rect.end.x]:
					candidates.append(PackedVector2Array([exit, Vector2(x, exit.y), Vector2(x, entry.y), entry]))
			continue
		if wire_hit >= 0:
			continue
		if score < best_score:
			best_score = score
			best = path
			if score <= minimum_length + 0.001:
				break
	if best.is_empty():
		best = visibility_route(exit, entry)
	if best.is_empty():
		if retry < 8 and not cancelled():
			return route(start, end, source, target, retry + 1)
		return PackedVector2Array()
	var result := PackedVector2Array([start])
	result.append_array(simplify(best))
	result.append(end)
	return WireGeometry.compress(result)

func visibility_route(start: Vector2, end: Vector2) -> PackedVector2Array:
	var pending: Array = [[start, PackedVector2Array([start]), 0.0]]
	var visited := {}
	for iteration in range(256):
		if cancelled():
			return PackedVector2Array()
		if pending.is_empty():
			break
		var best := 0
		for i in range(1, pending.size()):
			if pending[i][2] < pending[best][2]:
				best = i
		var state: Array = pending[best]
		pending.remove_at(best)
		var point: Vector2 = state[0]
		if visited.has(point):
			continue
		visited[point] = true
		for horizontal in [true, false]:
			var bend := Vector2(end.x, point.y) if horizontal else Vector2(point.x, end.y)
			var hit := blocker(point, bend)
			if hit < 0:
				hit = blocker(bend, end)
			var wire_hit := -1
			if hit < 0:
				wire_hit = wire_blocker(point, bend)
				if wire_hit < 0:
					wire_hit = wire_blocker(bend, end)
			if hit < 0 and wire_hit < 0:
				var result: PackedVector2Array = state[1].duplicate()
				result.append(bend)
				result.append(end)
				return WireGeometry.compress(result)
			var rect := obstacles[hit].grow(4) if hit >= 0 else wire_rect(wire_hit)
			for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
				for sideways in [true, false]:
					var turn := Vector2(corner.x, point.y) if sideways else Vector2(point.x, corner.y)
					if blocker(point, turn) >= 0 or blocker(turn, corner) >= 0 or wire_blocker(point, turn) >= 0 or wire_blocker(turn, corner) >= 0 or visited.has(corner):
						continue
					var path: PackedVector2Array = state[1].duplicate()
					path.append(turn)
					path.append(corner)
					var cost: float = state[2] - point.distance_to(end) + point.distance_to(turn) + turn.distance_to(corner) + corner.distance_to(end) + (overlap(point, turn) + overlap(turn, corner)) * 1000.0
					pending.append([corner, path, cost])
	return grid_route(start, end)

func heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if heap[parent][0] <= item[0]:
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item

func heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and heap[child + 1][0] < heap[child][0]:
			child += 1
		if last[0] <= heap[child][0]:
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return result

func grid_route(start: Vector2, end: Vector2, step := 16.0, limit := 2000) -> PackedVector2Array:
	if blocker(start, start) >= 0 or blocker(end, end) >= 0:
		return PackedVector2Array()
	var goal := Vector2i(((end - start) / step).round())
	if absi(goal.x) + absi(goal.y) > limit / 4:
		return PackedVector2Array()
	var heap: Array = [[0, 0, Vector2i.ZERO]]
	var costs := {Vector2i.ZERO: 0}
	var parents := {}
	for iteration in range(limit):
		if cancelled():
			return PackedVector2Array()
		if heap.is_empty():
			break
		var state := heap_pop(heap)
		var cell: Vector2i = state[2]
		if state[1] != costs.get(cell, -1):
			continue
		var point := start + Vector2(cell) * step
		if (cell - goal).length_squared() <= 4:
			var tail := WireGeometry.direct_path(point, end)
			var clear := true
			for i in range(tail.size() - 1):
				if blocker(tail[i], tail[i + 1]) >= 0 or wire_blocker(tail[i], tail[i + 1]) >= 0:
					clear = false
					break
			if clear:
				var reverse := PackedVector2Array([point])
				while parents.has(cell):
					cell = parents[cell]
					reverse.append(start + Vector2(cell) * step)
				reverse.reverse()
				reverse.append_array(tail)
				return WireGeometry.compress(reverse)
		for i in range(WireGeometry.DIRECTIONS.size()):
			var next: Vector2i = cell + WireGeometry.DIRECTIONS[i]
			var cost: int = state[1] + WireGeometry.COSTS[i]
			if cost >= costs.get(next, 2147483647):
				continue
			var next_point := start + Vector2(next) * step
			if blocker(point, next_point) >= 0 or wire_blocker(point, next_point) >= 0:
				continue
			costs[next] = cost
			parents[next] = cell
			var distance := goal - next
			heap_push(heap, [cost + (absi(distance.x) + absi(distance.y)) * 10, cost, next])
	return PackedVector2Array()
