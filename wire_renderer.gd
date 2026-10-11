extends RefCounted

var _revision := -1
var _view := Rect2()
var _cache: Dictionary = {}
var _points := PackedVector2Array()
var _dots: MultiMesh
var _dot_color := Color.TRANSPARENT

func prepare(revision: int, view: Rect2) -> void:
	_points.clear()
	if _revision != revision or _view != view:
		_revision = revision
		_view = view
		_cache.clear()

static func clip_interval(start: Vector2, end: Vector2, view: Rect2) -> Vector2:
	var delta := end - start
	var first := 0.0
	var last := 1.0
	for axis in range(2):
		if is_zero_approx(delta[axis]):
			if start[axis] < view.position[axis] or start[axis] > view.end[axis]:
				return Vector2(-1, -1)
			continue
		var a: float = (view.position[axis] - start[axis]) / delta[axis]
		var b: float = (view.end[axis] - start[axis]) / delta[axis]
		first = maxf(first, minf(a, b))
		last = minf(last, maxf(a, b))
		if first > last:
			return Vector2(-1, -1)
	return Vector2(first, last)

static func clip_segments(segments: PackedVector2Array, view: Rect2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(0, segments.size(), 2):
		var start := segments[index]
		var end := segments[index + 1]
		var interval := clip_interval(start, end, view)
		if interval.x < 0:
			continue
		result.append(start.lerp(end, interval.x))
		result.append(start.lerp(end, interval.y))
	return result

func visible_geometry(index: int, geometry: RefCounted) -> Dictionary:
	if _cache.has(index):
		return _cache[index]
	var path: PackedVector2Array = geometry.wire_paths[index]
	var distances: PackedFloat32Array = geometry.wire_distances[index]
	var intervals: Array[Vector3] = []
	for segment in range(1, path.size()):
		if distances[segment] <= distances[segment - 1]:
			continue
		var interval := clip_interval(path[segment - 1], path[segment], _view)
		if interval.x < 0:
			continue
		var first := lerpf(distances[segment - 1], distances[segment], interval.x)
		var last := lerpf(distances[segment - 1], distances[segment], interval.y)
		intervals.append(Vector3(first, last, segment))
	var result := {
		"core": clip_segments(geometry.wire_core_segments[index], _view),
		"border": clip_segments(geometry.wire_border_segments[index], _view),
		"intervals": intervals
	}
	_cache[index] = result
	return result

func draw_wire(canvas: CanvasItem, index: int, geometry: RefCounted, color: Color, border: Color, detailed: bool) -> void:
	var visible := visible_geometry(index, geometry)
	var path: PackedVector2Array = geometry.wire_paths[index]
	if detailed and not visible["border"].is_empty():
		canvas.draw_multiline(visible["border"], border, 10.0)
		for endpoint in [path[0], path[-1]]:
			if _view.has_point(endpoint):
				canvas.draw_circle(endpoint, 5.0, border)
	if not visible["core"].is_empty():
		canvas.draw_multiline(visible["core"], color, 8.0)
		if detailed:
			for endpoint in [path[0], path[-1]]:
				if _view.has_point(endpoint):
					canvas.draw_circle(endpoint, 4.0, color)

func append_signals(index: int, geometry: RefCounted, time: float) -> void:
	var distances: PackedFloat32Array = geometry.wire_distances[index]
	var length: float = distances[-1]
	if length <= 0:
		return
	var count := maxi(1, floori(length / 140.0))
	var spacing := length / count
	var offset := fposmod(time * 250.0, spacing)
	var path: PackedVector2Array = geometry.wire_paths[index]
	var visible := visible_geometry(index, geometry)
	var previous := -1
	for interval: Vector3 in visible["intervals"]:
		var first := maxi(0, ceili((interval.x - offset) / spacing))
		var last := mini(count - 1, floori((interval.y - offset) / spacing))
		var segment := int(interval.z)
		var span: float = distances[segment] - distances[segment - 1]
		for dot in range(maxi(first, previous + 1), last + 1):
			var distance := offset + dot * spacing
			_points.append(path[segment - 1].lerp(path[segment], (distance - distances[segment - 1]) / span))
			previous = dot

func draw_signals(canvas: CanvasItem, color: Color) -> void:
	if _points.is_empty():
		return
	if _dots == null:
		var vertices := PackedVector3Array()
		for index in range(12):
			vertices.append(Vector3.ZERO)
			var a := Vector2.from_angle(TAU * index / 12.0) * 3.0
			var b := Vector2.from_angle(TAU * (index + 1) / 12.0) * 3.0
			vertices.append(Vector3(a.x, a.y, 0))
			vertices.append(Vector3(b.x, b.y, 0))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_dots = MultiMesh.new()
		_dots.transform_format = MultiMesh.TRANSFORM_2D
		_dots.use_colors = true
		_dots.mesh = mesh
	if _dots.instance_count < _points.size():
		var capacity := maxi(64, _dots.instance_count)
		while capacity < _points.size():
			capacity *= 2
		_dots.instance_count = capacity
		_dot_color = Color.TRANSPARENT
	if _dot_color != color:
		for index in range(_dots.instance_count):
			_dots.set_instance_color(index, color)
		_dot_color = color
	_dots.visible_instance_count = _points.size()
	for index in range(_points.size()):
		_dots.set_instance_transform_2d(index, Transform2D(0.0, _points[index]))
	canvas.draw_multimesh(_dots, null)
