extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func gate(id: int, type_id: String, inputs: Array, outputs: Array, x: float) -> Dictionary:
	return {
		"id": id, "type_id": type_id, "name": type_id, "position": Vector2(x, 0),
		"input_names": inputs, "output_names": outputs,
		"inputs": [], "outputs": [], "previous_inputs": [], "memory": false,
		"state": false, "pulse_pending": false, "export": true
	}

func run_test() -> void:
	var editor = load("res://main.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.gates.append(gate(1, "MP/Logic/DFF", ["D", "CLK"], ["Q", "/Q"], 0))
	editor.gates.append(gate(2, "MP/Logic/OR", ["A", "B"], ["OUT"], 300))
	editor.gates.append(gate(3, "MP/Logic/AND", ["A", "B"], ["OUT"], 600))
	editor.gates[0]["inputs"] = [false, false]
	editor.gates[0]["outputs"] = [false, false]
	editor.gates[0]["previous_inputs"] = [false, false]
	for gate_index in [1, 2]:
		editor.gates[gate_index]["inputs"] = [false, false]
		editor.gates[gate_index]["outputs"] = [false]
		editor.gates[gate_index]["previous_inputs"] = [false, false]
	editor.wires.append_array([
		{"from_gate": 0, "from_port": 1, "to_gate": 1, "to_port": 0},
		{"from_gate": 0, "from_port": 1, "to_gate": 2, "to_port": 0}
	])
	editor.selected_gates.append(0)
	editor.selected_gate = 0
	editor.swap_selected_gates(9)
	editor.canvas_geometry.update(editor.gates, editor.wires, editor.NODE_SIZE)
	assert(editor.gates[0]["type_id"] == "MP/Logic/OR")
	assert(editor.wires[0]["from_port"] == 0 and editor.wires[1]["from_port"] == 0)
	assert(editor.canvas_geometry.wire_starts[0] == editor.port_position(0, false, 0))
	assert(editor.canvas_geometry.wire_starts[1] == editor.port_position(0, false, 0))
	print("Swap wire geometry smoke test passed.")
	quit()
