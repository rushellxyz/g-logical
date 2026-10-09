extends RefCounted

const GateProperties = preload("res://gate_properties.gd")

var dirty := true
var orthogonal := false
var gate_bounds: Array[Rect2] = []
var wire_bounds: Array[Rect2] = []
var wire_starts := PackedVector2Array()
var wire_ends := PackedVector2Array()
var wire_paths: Array[PackedVector2Array] = []

func update(gates: Array, wires: Array, node_size: Vector2) -> void:
	if not dirty and gate_bounds.size() == gates.size() and wire_bounds.size() == wires.size():
		return
	gate_bounds.clear()
	wire_bounds.clear()
	wire_starts.clear()
	wire_ends.clear()
	wire_paths.clear()
	var input_positions: Array = []
	var output_positions: Array = []
	for gate in gates:
		var position: Vector2 = gate["position"]
		var size: Vector2 = GateProperties.node_size(gate, node_size)
		gate_bounds.append(Rect2(position, size))
		input_positions.append(ports(gate, position, gate["inputs"].size(), 0.0, true))
		output_positions.append(ports(gate, position, gate["outputs"].size(), size.x, false))
	for wire in wires:
		var start: Vector2 = output_positions[wire["from_gate"]][wire["from_port"]]
		var end: Vector2 = input_positions[wire["to_gate"]][wire["to_port"]]
		wire_starts.append(start)
		wire_ends.append(end)
		var path := route(start, end, gate_bounds[wire["from_gate"]], gate_bounds[wire["to_gate"]], wire["from_port"], wire["to_port"]) if orthogonal else PackedVector2Array([start, end])
		wire_paths.append(path)
		var bounds := Rect2(start, Vector2.ZERO)
		for point in path:
			bounds = bounds.expand(point)
		wire_bounds.append(bounds)
	dirty = false

func route(start: Vector2, end: Vector2, source: Rect2, target: Rect2, output_port: int, input_port: int) -> PackedVector2Array:
	var exit_x := start.x + 24.0 + output_port * 8.0
	var entry_x := end.x - 24.0 - input_port * 8.0
	if exit_x <= entry_x:
		var middle_x := (exit_x + entry_x) * 0.5
		return PackedVector2Array([start, Vector2(middle_x, start.y), Vector2(middle_x, end.y), end])
	var top_y := minf(source.position.y, target.position.y) - 24.0 - output_port * 8.0
	var bottom_y := maxf(source.end.y, target.end.y) + 24.0 + output_port * 8.0
	var lane_y := top_y if absf(start.y - top_y) + absf(end.y - top_y) <= absf(start.y - bottom_y) + absf(end.y - bottom_y) else bottom_y
	return PackedVector2Array([start, Vector2(exit_x, start.y), Vector2(exit_x, lane_y), Vector2(entry_x, lane_y), Vector2(entry_x, end.y), end])

func ports(gate: Dictionary, position: Vector2, count: int, x_offset: float, input: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	for port in range(count):
		result.append(position + Vector2(x_offset, GateProperties.port_y(gate, input, port)))
	return result
