extends RefCounted

const GateProperties = preload("res://gate_properties.gd")
const MAX_DEPTH := 32

func expand(source_gates: Array, source_wires: Array) -> Dictionary:
	var working_gates := source_gates
	var working_wires := source_wires
	var origins := source_gates
	var views: Array[Dictionary] = []
	for depth in range(MAX_DEPTH):
		var has_custom := false
		for index in range(working_gates.size()):
			var gate: Dictionary = working_gates[index]
			if gate["type_id"] != "EDITOR/CUSTOM":
				continue
			has_custom = true
			var inputs: Array = []
			var outputs: Array = []
			for port in range(gate["inputs"].size()):
				var sources: Array = []
				for wire in working_wires:
					if wire["to_gate"] == index and wire["to_port"] == port:
						sources.append({"gate": wire["from_gate"], "port": wire["from_port"]})
				inputs.append(sources)
			for port in range(gate["outputs"].size()):
				outputs.append([{"gate": index, "port": port}])
			views.append({"gate": origins[index], "inputs": inputs, "outputs": outputs})
		if not has_custom:
			break
		var result := expand_once(working_gates, working_wires, [], false, origins)
		for view in views:
			for role in ["inputs", "outputs"]:
				for port in range(view[role].size()):
					var resolved: Array = []
					for source in view[role][port]:
						resolved.append_array(resolve_endpoint(source, working_wires, result))
					view[role][port] = resolved
		working_gates = result["gates"]
		working_wires = result["wires"]
		origins = result["origins"]
	return {"gates": working_gates, "wires": working_wires, "origins": origins, "views": views}

func resolve_endpoint(source: Dictionary, source_wires: Array, result: Dictionary) -> Array:
	var index := int(source["gate"])
	var port := int(source["port"])
	if result["gate_map"][index] >= 0:
		return [{"gate": result["gate_map"][index], "port": port}]
	return resolve_custom_output_sources(index, port, source_wires, result["gate_map"], result["instances"], 0)

func expand_once(source_gates: Array, source_wires: Array, selected: Array = [], for_edit := false, origins: Array = []) -> Dictionary:
	if origins.is_empty():
		origins = source_gates
	var expanded_origins: Array = []
	var created: Array[int] = []
	var expanded_gates: Array[Dictionary] = []
	var expanded_wires: Array[Dictionary] = []
	var gate_map: Array[int] = []
	var instance_maps: Dictionary = {}
	for gate_index in range(source_gates.size()):
		var gate: Dictionary = source_gates[gate_index]
		if gate["type_id"] != "EDITOR/CUSTOM" or (for_edit and gate_index not in selected):
			gate_map.append(expanded_gates.size())
			expanded_gates.append(gate.duplicate(true))
			expanded_origins.append(origins[gate_index])
			continue
		gate_map.append(-1)
		var child_gates: Array = gate.get("custom_gates", [])
		var child_wires: Array = gate.get("custom_wires", [])
		var child_map: Array[int] = []
		var edit_origin := Vector2(INF, INF)
		for child in child_gates:
			edit_origin = edit_origin.min(normalized_position(child["position"]))
		for child_index in range(child_gates.size()):
			var child: Dictionary = child_gates[child_index]
			if not for_edit and is_interface(child):
				child_map.append(-1)
				continue
			var copy: Dictionary = child.duplicate(true)
			if for_edit and is_interface(copy):
				copy["unpacked_interface"] = true
				copy["export"] = false
				var input: bool = copy["type_id"] == "EDITOR/COMPONENT_INPUT"
				var port := find_custom_port(gate["custom_inputs"] if input else gate["custom_outputs"], child_index)
				for wire in source_wires:
					if (input and wire["to_gate"] == gate_index and wire["to_port"] == port) or (not input and wire["from_gate"] == gate_index and wire["from_port"] == port):
						copy["unpacked_bridge"] = true
						copy["input_names"] = ["IN"] if input else copy["input_names"]
						copy["output_names"] = copy["output_names"] if input else ["OUT"]
						copy["inputs"] = [false]
						copy["outputs"] = [false]
						copy["previous_inputs"] = [false]
						break
			var child_position := normalized_position(copy.get("position", Vector2.ZERO))
			if for_edit:
				var origin := normalized_position(gate.get("custom_origin", edit_origin)) if gate.get("custom_layout_mode") == "Expand" else edit_origin
				copy["position"] = gate["position"] + child_position - origin + Vector2(16, 40)
			elif gate.get("custom_layout_mode", "Inline") == "Inline":
				copy["position"] = gate["position"]
				if copy["type_id"] == "EDITOR/CUSTOM":
					copy["custom_layout_mode"] = "Inline"
			else:
				copy["position"] = gate["position"] + child_position - normalized_position(gate.get("custom_origin", Vector2.ZERO))
			child_map.append(expanded_gates.size())
			created.append(expanded_gates.size())
			expanded_gates.append(copy)
			expanded_origins.append(origins[gate_index]["custom_gates"][child_index])
		var inputs: Array = gate.get("custom_inputs", [])
		var outputs: Array = gate.get("custom_outputs", [])
		var input_targets: Array = []
		var output_sources: Array = []
		var pass_through: Array = []
		input_targets.resize(inputs.size())
		output_sources.resize(outputs.size())
		pass_through.resize(outputs.size())
		for index in range(inputs.size()):
			input_targets[index] = []
		for index in range(outputs.size()):
			output_sources[index] = []
			pass_through[index] = []
		if for_edit:
			for port in range(inputs.size()):
				input_targets[port] = [{"gate": child_map[int(inputs[port]["gate"])], "port": 0}]
			for port in range(outputs.size()):
				output_sources[port] = [{"gate": child_map[int(outputs[port]["gate"])], "port": 0}]
		for child_wire in child_wires:
			var from_index := int(child_wire["from_gate"])
			var to_index := int(child_wire["to_gate"])
			var from_type: String = child_gates[from_index].get("type_id", "")
			var to_type: String = child_gates[to_index].get("type_id", "")
			if for_edit:
				expanded_wires.append({"from_gate": child_map[from_index], "from_port": int(child_wire["from_port"]), "to_gate": child_map[to_index], "to_port": int(child_wire["to_port"])})
				continue
			if from_type == "EDITOR/COMPONENT_INPUT" and is_interface(child_gates[from_index]):
				var parent_port := find_custom_port(inputs, from_index)
				if parent_port >= 0:
					if to_type == "EDITOR/COMPONENT_OUTPUT" and is_interface(child_gates[to_index]):
						var output_port := find_custom_port(outputs, to_index)
						if output_port >= 0:
							pass_through[output_port].append(parent_port)
					elif child_map[to_index] >= 0:
						input_targets[parent_port].append({"gate": child_map[to_index], "port": int(child_wire["to_port"])})
			elif to_type == "EDITOR/COMPONENT_OUTPUT" and is_interface(child_gates[to_index]):
				var parent_port := find_custom_port(outputs, to_index)
				if parent_port >= 0 and child_map[from_index] >= 0:
					output_sources[parent_port].append({"gate": child_map[from_index], "port": int(child_wire["from_port"])})
			elif child_map[from_index] >= 0 and child_map[to_index] >= 0:
				expanded_wires.append({
					"from_gate": child_map[from_index], "from_port": int(child_wire["from_port"]),
					"to_gate": child_map[to_index], "to_port": int(child_wire["to_port"])
				})
		instance_maps[gate_index] = {"inputs": input_targets, "outputs": output_sources, "pass": pass_through, "children": child_map}
	for wire in source_wires:
		var source_gate := int(wire["from_gate"])
		var target_gate := int(wire["to_gate"])
		var sources: Array = []
		var destinations: Array = []
		if gate_map[source_gate] >= 0:
			sources.append({"gate": gate_map[source_gate], "port": int(wire["from_port"])})
		else:
			sources = resolve_custom_output_sources(source_gate, int(wire["from_port"]), source_wires, gate_map, instance_maps, 0)
		if gate_map[target_gate] >= 0:
			destinations.append({"gate": gate_map[target_gate], "port": int(wire["to_port"])})
		else:
			var instance: Dictionary = instance_maps[target_gate]
			var port := int(wire["to_port"])
			destinations = instance["inputs"][port]
		for source in sources:
			for destination in destinations:
				expanded_wires.append({
					"from_gate": source["gate"], "from_port": source["port"],
					"to_gate": destination["gate"], "to_port": destination["port"]
				})
	return {"gates": expanded_gates, "wires": expanded_wires, "gate_map": gate_map, "instances": instance_maps, "origins": expanded_origins, "created": created}

func find_custom_port(ports: Array, child_gate_index: int) -> int:
	for port_index in range(ports.size()):
		if int(ports[port_index]["gate"]) == child_gate_index:
			return port_index
	return -1

func resolve_custom_output_sources(instance_gate: int, output_port: int, source_wires: Array, gate_map: Array, instance_maps: Dictionary, depth: int) -> Array:
	var resolved: Array = []
	if depth > gate_map.size() or not instance_maps.has(instance_gate):
		return resolved
	var instance: Dictionary = instance_maps[instance_gate]
	resolved.append_array(instance["outputs"][output_port])
	for input_port in instance["pass"][output_port]:
		for wire in source_wires:
			if int(wire["to_gate"]) != instance_gate or int(wire["to_port"]) != input_port:
				continue
			var source_gate := int(wire["from_gate"])
			var source_port := int(wire["from_port"])
			if gate_map[source_gate] >= 0:
				resolved.append({"gate": gate_map[source_gate], "port": source_port})
			else:
				resolved.append_array(resolve_custom_output_sources(source_gate, source_port, source_wires, gate_map, instance_maps, depth + 1))
	return resolved

func normalized_position(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary and value.has("x") and value.has("y"):
		return Vector2(float(value["x"]), float(value["y"]))
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is String:
		var parts: PackedStringArray = value.trim_prefix("(").trim_suffix(")").split(",")
		if parts.size() == 2:
			return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO

func valid_ports(gate: Dictionary) -> bool:
	if not gate.get("custom_gates") is Array or not gate.get("custom_wires") is Array:
		return false
	for role in ["inputs", "outputs"]:
		var ports = gate.get("custom_" + role)
		if not ports is Array or ports.size() != gate[role].size():
			return false
		var used: Array[int] = []
		var type := "EDITOR/COMPONENT_INPUT" if role == "inputs" else "EDITOR/COMPONENT_OUTPUT"
		for port in ports:
			if not port is Dictionary or (not port.get("gate") is int and not port.get("gate") is float):
				return false
			var index := int(port["gate"])
			if index < 0 or index >= gate["custom_gates"].size() or index in used:
				return false
			var child = gate["custom_gates"][index]
			if not child is Dictionary or child.get("type_id") != type or not is_interface(child):
				return false
			used.append(index)
		for index in range(gate["custom_gates"].size()):
			var child = gate["custom_gates"][index]
			if child is Dictionary and child.get("type_id") == type and is_interface(child) and index not in used:
				return false
	return true

func child_position(instance: Dictionary, child: Dictionary, position: Vector2) -> Vector2:
	return position + normalized_position(child["position"]) - normalized_position(instance.get("custom_origin", Vector2.ZERO)) + Vector2(16, 40)

func button_at(instance: Dictionary, position: Vector2, point: Vector2) -> Dictionary:
	if instance.get("custom_layout_mode") != "Expand":
		return {}
	var children: Array = instance.get("custom_gates", [])
	for index in range(children.size() - 1, -1, -1):
		var child: Dictionary = children[index]
		var origin := child_position(instance, child, position)
		if child["type_id"] == "EDITOR/CUSTOM":
			var button := button_at(child, origin, point)
			if not button.is_empty():
				return button
		elif child["type_id"] == "MP/IO/BUTTON" and Rect2(origin, GateProperties.node_size(child, Vector2(170, 92))).has_point(point):
			return child
	return {}

func is_interface(gate: Dictionary) -> bool:
	return gate.get("type_id") in ["EDITOR/COMPONENT_INPUT", "EDITOR/COMPONENT_OUTPUT"] and not gate.get("unpacked_bridge", false)

func bridge_sources(index: int, source_gates: Array, incoming: Dictionary, visited: Dictionary = {}) -> Array:
	if visited.has(index):
		return []
	var next_visited := visited.duplicate()
	next_visited[index] = true
	var sources: Array = []
	for wire in incoming.get(index, []):
		var source := int(wire["from_gate"])
		if source_gates[source].get("unpacked_bridge", false):
			sources.append_array(bridge_sources(source, source_gates, incoming, next_visited))
		else:
			sources.append({"gate": source, "port": int(wire["from_port"])})
	return sources

func expand_bridges(source_gates: Array, source_wires: Array, include_bridge_inputs: bool) -> Array:
	var has_bridges := false
	for gate in source_gates:
		if gate.get("unpacked_bridge", false):
			has_bridges = true
			break
	if not has_bridges:
		return source_wires
	var incoming := {}
	for wire in source_wires:
		var target := int(wire["to_gate"])
		if not incoming.has(target):
			incoming[target] = []
		incoming[target].append(wire)
	var expanded: Array = []
	var seen := {}
	for wire in source_wires:
		if not include_bridge_inputs and source_gates[int(wire["to_gate"])].get("unpacked_bridge", false):
			continue
		var sources: Array = [{"gate": int(wire["from_gate"]), "port": int(wire["from_port"])}]
		if source_gates[int(wire["from_gate"])].get("unpacked_bridge", false):
			sources = bridge_sources(int(wire["from_gate"]), source_gates, incoming)
		for source in sources:
			var key := Vector4i(source["gate"], source["port"], int(wire["to_gate"]), int(wire["to_port"]))
			if seen.has(key):
				continue
			seen[key] = true
			expanded.append({"from_gate": source["gate"], "from_port": source["port"], "to_gate": wire["to_gate"], "to_port": wire["to_port"]})
	return expanded
