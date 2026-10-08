extends RefCounted

const STEP_SECONDS := 0.02
const MEMORY_TYPES := ["MP/Logic/SR", "MP/Logic/DFF", "MP/Logic/JK", "MP/Logic/TFF"]

static func reset(gates: Array) -> void:
	for gate in gates:
		gate["inputs"].fill(false)
		gate["outputs"].fill(false)
		gate["previous_inputs"].fill(false)
		gate["pulse_pending"] = false
		gate["memory"] = int(gate.get("gunsaw_data", {}).get("initialQ", 0)) != 0
		gate["state"] = true
		for key in ["simulation_clock_elapsed", "simulation_clock_high", "simulation_delay_remaining", "simulation_button_used"]:
			gate.erase(key)

static func step(gates: Array, wires: Array) -> void:
	var next_inputs: Array = []
	var destinations := {}
	for gate in gates:
		var inputs: Array = []
		inputs.resize(gate["inputs"].size())
		inputs.fill(false)
		next_inputs.append(inputs)
	for wire in wires:
		var key := "%d:%d" % [wire["from_gate"], wire["from_port"]]
		if not destinations.has(key):
			destinations[key] = []
		destinations[key].append([wire["to_gate"], wire["to_port"]])
	for gate in gates:
		var inputs: Array = gate["inputs"]
		var previous: Array = gate["previous_inputs"]
		var data: Dictionary = gate.get("gunsaw_data", {})
		var result := false
		match gate["type_id"]:
			"MP/IO/BUTTON":
				result = gate["pulse_pending"] and not gate.get("simulation_button_used", false)
				if result and int(gate.get("gunsaw_part", {}).get("activId", 0)) > 0:
					gate["simulation_button_used"] = true
			"MP/Logic/AND": result = inputs[0] and inputs[1]
			"MP/Logic/OR": result = inputs[0] or inputs[1]
			"MP/Logic/XOR": result = inputs[0] != inputs[1]
			"MP/Logic/XNOR": result = inputs[0] == inputs[1]
			"MP/Logic/NAND": result = not (inputs[0] and inputs[1])
			"MP/Logic/NOR": result = not (inputs[0] or inputs[1])
			"MP/Logic/NOT": result = not inputs[0]
			"MP/Logic/CONST": result = int(data.get("value", 1)) != 0
			"MP/Logic/CLOCK":
				var elapsed := single(float(gate.get("simulation_clock_elapsed", 0.0)) + single(STEP_SECONDS))
				var high: bool = gate.get("simulation_clock_high", int(data.get("initialHigh", 0)) != 0)
				var half_period := maxf(single(STEP_SECONDS), single(float(data.get("period", 1.0)) * 0.5))
				while elapsed >= half_period:
					elapsed = single(elapsed - half_period)
					high = not high
				gate["simulation_clock_elapsed"] = elapsed
				gate["simulation_clock_high"] = high
				result = high
			"MP/Logic/EDGE":
				var mode := int(data.get("mode", 2))
				result = (mode == 0 or mode == 2) and inputs[0] and not previous[0]
				result = result or ((mode == 1 or mode == 2) and not inputs[0] and previous[0])
			"MP/Logic/SR": result = gate["memory"] if inputs[0] == inputs[1] else inputs[0]
			"MP/Logic/DFF": result = inputs[0] if inputs[1] and not previous[1] else gate["memory"]
			"MP/Logic/JK":
				result = gate["memory"]
				if inputs[2] and not previous[2]:
					if inputs[0] and inputs[1]:
						result = not result
					elif inputs[0] or inputs[1]:
						result = inputs[0]
			"MP/Logic/TFF": result = not gate["memory"] if inputs[1] and not previous[1] and inputs[0] else gate["memory"]
		if gate["type_id"] in MEMORY_TYPES:
			gate["memory"] = result
		for port_index in range(gate["outputs"].size()):
			gate["outputs"][port_index] = result if port_index == 0 else not result
		gate["pulse_pending"] = false
		gate["previous_inputs"] = inputs.duplicate()
	var activated := {}
	for gate_index in range(gates.size()):
		var gate: Dictionary = gates[gate_index]
		for port_index in range(gate["outputs"].size()):
			if gate["outputs"][port_index]:
				activate_destinations(gates, destinations.get("%d:%d" % [gate_index, port_index], []), next_inputs, activated)
	for gate_index in range(gates.size()):
		var gate: Dictionary = gates[gate_index]
		if gate["type_id"] != "GUNSAW/DELAY" or not gate.has("simulation_delay_remaining"):
			continue
		var remaining := single(float(gate["simulation_delay_remaining"]) - single(STEP_SECONDS))
		if remaining < 0:
			gate.erase("simulation_delay_remaining")
			gate["outputs"][0] = true
			activate_destinations(gates, destinations.get("%d:0" % gate_index, []), next_inputs, {})
		else:
			gate["simulation_delay_remaining"] = remaining
	for gate_index in range(gates.size()):
		gates[gate_index]["inputs"] = next_inputs[gate_index]
		if gates[gate_index]["type_id"] == "EDITOR/CLOCK_OUT":
			gates[gate_index]["outputs"][0] = false
			for gate in gates:
				if gate["type_id"] == "EDITOR/CLOCK_IN" and gate["inputs"][0]:
					gates[gate_index]["outputs"][0] = true

static func activate_destinations(gates: Array, destinations: Array, next_inputs: Array, activated: Dictionary) -> void:
	for destination in destinations:
		var gate_index: int = destination[0]
		var port_index: int = destination[1]
		var key := "%d:%d" % [gate_index, port_index]
		next_inputs[gate_index][port_index] = true
		if activated.has(key):
			continue
		activated[key] = true
		var gate: Dictionary = gates[gate_index]
		match gate["type_id"]:
			"MP/IO/LAMP":
				var ids: Array = gate.get("gunsaw_input_ids", [])
				if ids.is_empty() or int(ids[0]) > 0:
					gate["state"] = not gate["state"]
			"GUNSAW/DELAY":
				gate["simulation_delay_remaining"] = single(float(gate.get("gunsaw_data", {}).get("delay", 0.0)))

static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]
