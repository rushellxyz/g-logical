extends RefCounted

var dirty := true
var gate_bounds: Array[Rect2] = []
var wire_bounds: Array[Rect2] = []
var wire_starts := PackedVector2Array()
var wire_ends := PackedVector2Array()

func update(gates: Array, wires: Array, node_size: Vector2) -> void:
	if not dirty and gate_bounds.size() == gates.size() and wire_bounds.size() == wires.size():
		return
	gate_bounds.clear()
	wire_bounds.clear()
	wire_starts.clear()
	wire_ends.clear()
	var input_positions: Array = []
	var output_positions: Array = []
	for gate in gates:
		var position: Vector2 = gate["position"]
		var size: Vector2 = gate.get("size", Vector2(320, 64)) if gate["type_id"] == "EDITOR/WHITETILE" else node_size
		gate_bounds.append(Rect2(position, size))
		input_positions.append(ports(position, gate["inputs"].size(), 0.0))
		output_positions.append(ports(position, gate["outputs"].size(), node_size.x))
	for wire in wires:
		var start: Vector2 = output_positions[wire["from_gate"]][wire["from_port"]]
		var end: Vector2 = input_positions[wire["to_gate"]][wire["to_port"]]
		wire_starts.append(start)
		wire_ends.append(end)
		wire_bounds.append(Rect2(start, end - start).abs())
	dirty = false

func ports(position: Vector2, count: int, x_offset: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for port in range(count):
		result.append(position + Vector2(x_offset, 42.0 + (port + 1) * (42.0 / count)))
	return result
