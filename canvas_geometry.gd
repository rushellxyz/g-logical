extends RefCounted

const GateProperties = preload("res://gate_properties.gd")
const WireGeometry = preload("res://wire_geometry.gd")

var dirty := true
var orthogonal := false
var gate_bounds: Array[Rect2] = []
var wire_bounds: Array[Rect2] = []
var wire_starts := PackedVector2Array()
var wire_ends := PackedVector2Array()
var wire_paths: Array[PackedVector2Array] = []
var wire_distances: Array[PackedFloat32Array] = []
var wire_core_segments: Array[PackedVector2Array] = []
var wire_border_segments: Array[PackedVector2Array] = []
var board_router = preload("res://board_wire_router.gd").new()
var routing_index := 0
var routing_wires: Array = []
var routing_thread: Thread
var routing_mutex := Mutex.new()
var routing_cancelled := false
var routing_results: Array[PackedVector2Array] = []
var wire_routed: Array[bool] = []
var routing_failures := 0
var gate_wires: Array[PackedInt32Array] = []
var moving := false

func update(gates: Array, wires: Array, node_size: Vector2) -> void:
	if not dirty and gate_bounds.size() == gates.size() and wire_bounds.size() == wires.size():
		return
	stop_routing()
	moving = false
	gate_wires.clear()
	gate_wires.resize(gates.size())
	gate_bounds.clear()
	wire_bounds.clear()
	wire_starts.clear()
	wire_ends.clear()
	wire_paths.clear()
	wire_routed.clear()
	routing_failures = 0
	wire_distances.clear()
	wire_core_segments.clear()
	wire_border_segments.clear()
	var input_positions: Array = []
	var output_positions: Array = []
	var routing_bounds: Array[Rect2] = []
	for gate in gates:
		var position: Vector2 = gate["position"]
		var size: Vector2 = GateProperties.node_size(gate, node_size)
		gate_bounds.append(Rect2(position, size))
		if gate["type_id"] != "EDITOR/WHITETILE":
			routing_bounds.append(gate_bounds[-1])
		input_positions.append(ports(gate, position, gate["inputs"].size(), 0.0, true))
		output_positions.append(ports(gate, position, gate["outputs"].size(), size.x, false))
	if orthogonal:
		board_router.configure(routing_bounds)
	routing_wires = wires.duplicate(true) if orthogonal else []
	routing_index = 0
	for wire in wires:
		var wire_index := wire_paths.size()
		gate_wires[wire["from_gate"]].append(wire_index)
		if wire["to_gate"] != wire["from_gate"]:
			gate_wires[wire["to_gate"]].append(wire_index)
		var start: Vector2 = output_positions[wire["from_gate"]][wire["from_port"]]
		var end: Vector2 = input_positions[wire["to_gate"]][wire["to_port"]]
		wire_starts.append(start)
		wire_ends.append(end)
		var path := PackedVector2Array([start, end])
		wire_paths.append(path)
		wire_routed.append(not orthogonal)
		wire_core_segments.append(WireGeometry.rendered_segments(path, true) if orthogonal else PackedVector2Array())
		wire_border_segments.append(WireGeometry.rendered_segments(path, false) if orthogonal else PackedVector2Array())
		var distances := PackedFloat32Array([0.0])
		for i in range(1, path.size()):
			distances.append(distances[-1] + path[i - 1].distance_to(path[i]))
		wire_distances.append(distances)
		var bounds := Rect2(start, Vector2.ZERO)
		for point in path:
			bounds = bounds.expand(point)
		wire_bounds.append(bounds)
	dirty = false
	if wires.size() <= 128:
		advance_routing(1000000)
	elif orthogonal:
		routing_cancelled = false
		routing_thread = Thread.new()
		routing_thread.start(build_routes.bind(gate_bounds.duplicate(), wire_starts.duplicate(), wire_ends.duplicate(), routing_wires.duplicate(true), routing_bounds))

func update_moved_gates(gates: Array, wires: Array, indices: Array, node_size: Vector2) -> void:
	update(gates, wires, node_size)
	var affected: Dictionary = {}
	for index in indices:
		var gate: Dictionary = gates[index]
		var bounds := Rect2(gate["position"], GateProperties.node_size(gate, node_size))
		if gate_bounds[index] == bounds:
			continue
		gate_bounds[index] = bounds
		moving = true
		for wire_index in gate_wires[index]:
			affected[wire_index] = true
	for index in affected:
		var wire: Dictionary = wires[index]
		var source: Dictionary = gates[wire["from_gate"]]
		var target: Dictionary = gates[wire["to_gate"]]
		var start: Vector2 = source["position"] + Vector2(gate_bounds[wire["from_gate"]].size.x, GateProperties.port_y(source, false, wire["from_port"]))
		var end: Vector2 = target["position"] + Vector2(0.0, GateProperties.port_y(target, true, wire["to_port"]))
		wire_starts[index] = start
		wire_ends[index] = end
		var path := PackedVector2Array([start, end])
		wire_paths[index] = path
		wire_routed[index] = not orthogonal
		wire_distances[index] = PackedFloat32Array([0.0, start.distance_to(end)])
		wire_bounds[index] = Rect2(start, Vector2.ZERO).expand(end)
		if orthogonal:
			wire_core_segments[index] = WireGeometry.rendered_segments(path, true)
			wire_border_segments[index] = WireGeometry.rendered_segments(path, false)

func finish_moving() -> void:
	if moving and orthogonal:
		dirty = true
	moving = false

func stop_routing() -> void:
	if routing_thread != null:
		routing_mutex.lock()
		routing_cancelled = true
		routing_mutex.unlock()
		routing_thread.wait_to_finish()
		routing_thread = null
	routing_results.clear()

func build_routes(bounds: Array[Rect2], starts: PackedVector2Array, ends: PackedVector2Array, connections: Array, routing_bounds: Array[Rect2]) -> void:
	var worker = preload("res://board_wire_router.gd").new()
	worker.cancel_check = routing_should_stop
	worker.configure(routing_bounds)
	for i in range(connections.size()):
		routing_mutex.lock()
		var cancelled := routing_cancelled
		routing_mutex.unlock()
		if cancelled:
			return
		var wire: Dictionary = connections[i]
		var path: PackedVector2Array = worker.route(starts[i], ends[i], bounds[wire["from_gate"]], bounds[wire["to_gate"]])
		if routing_should_stop():
			return
		if not path.is_empty():
			worker.reserve(path)
		routing_mutex.lock()
		routing_results.append(path)
		routing_mutex.unlock()

func routing_should_stop() -> bool:
	routing_mutex.lock()
	var result := routing_cancelled
	routing_mutex.unlock()
	return result

func advance_routing(budget_usec := 3000) -> bool:
	if moving:
		return false
	if routing_thread != null and routing_index >= routing_wires.size() and not routing_thread.is_alive():
		stop_routing()
	if dirty or not orthogonal or routing_index >= routing_wires.size():
		return false
	var deadline := Time.get_ticks_usec() + budget_usec
	var changed := false
	while routing_index < routing_wires.size():
		var index := routing_index
		var wire: Dictionary = routing_wires[index]
		var path: PackedVector2Array
		if routing_thread != null:
			var ready := false
			routing_mutex.lock()
			if routing_results.size() > index:
				path = routing_results[index]
				ready = true
			routing_mutex.unlock()
			if not ready:
				break
		else:
			path = route(wire_starts[index], wire_ends[index], gate_bounds[wire["from_gate"]], gate_bounds[wire["to_gate"]], wire["from_port"], wire["to_port"])
		wire_routed[index] = not path.is_empty()
		if path.is_empty():
			routing_failures += 1
			path = PackedVector2Array([wire_starts[index], wire_ends[index]])
		else:
			board_router.reserve(path)
		wire_paths[index] = path
		wire_core_segments[index] = WireGeometry.rendered_segments(path, true)
		wire_border_segments[index] = WireGeometry.rendered_segments(path, false)
		var distances := PackedFloat32Array([0.0])
		var bounds := Rect2(wire_starts[index], Vector2.ZERO)
		for i in range(path.size()):
			bounds = bounds.expand(path[i])
			if i > 0:
				distances.append(distances[-1] + path[i - 1].distance_to(path[i]))
		wire_bounds[index] = bounds
		wire_distances[index] = distances
		routing_index += 1
		changed = true
		if Time.get_ticks_usec() >= deadline:
			break
	if routing_index == routing_wires.size() and routing_thread != null and not routing_thread.is_alive():
		stop_routing()
	return changed

func route(start: Vector2, end: Vector2, source: Rect2, target: Rect2, _output_port: int, _input_port: int) -> PackedVector2Array:
	return board_router.route(start, end, source, target)

func ports(gate: Dictionary, position: Vector2, count: int, x_offset: float, input: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	for port in range(count):
		result.append(position + Vector2(x_offset, GateProperties.port_y(gate, input, port)))
	return result
