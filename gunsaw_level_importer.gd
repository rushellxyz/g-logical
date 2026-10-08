extends RefCounted

const MAX_LEVEL_BYTES := 64 * 1024 * 1024
const MAX_PARTS := 100000
const MAX_WIRES := 1000000
const SCALE := 320.0
const PORT_FIELDS := {
	"MP/Logic/AND": [["inputA", "inputB"], ["output"]],
	"MP/Logic/OR": [["inputA", "inputB"], ["output"]],
	"MP/Logic/XOR": [["inputA", "inputB"], ["output"]],
	"MP/Logic/XNOR": [["inputA", "inputB"], ["output"]],
	"MP/Logic/NAND": [["inputA", "inputB"], ["output"]],
	"MP/Logic/NOR": [["inputA", "inputB"], ["output"]],
	"MP/Logic/NOT": [["input"], ["output"]],
	"MP/Logic/CONST": [[], ["output"]],
	"MP/Logic/CLOCK": [[], ["output"]],
	"MP/Logic/EDGE": [["input"], ["output"]],
	"MP/Logic/SR": [["set", "reset"], ["q", "notQ"]],
	"MP/Logic/DFF": [["d", "clock"], ["q", "notQ"]],
	"MP/Logic/JK": [["j", "k", "clock"], ["q", "notQ"]],
	"MP/Logic/TFF": [["t", "clock"], ["q", "notQ"]]
}

static func import_file(path: String, definitions: Array) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Could not open level: %s." % error_string(FileAccess.get_open_error())}
	if file.get_length() > MAX_LEVEL_BYTES:
		return {"error": "Level file is too large (maximum 64 MB)."}
	return import_text(file.get_as_text(), definitions)

static func import_text(text: String, definitions: Array) -> Dictionary:
	text = text.strip_edges().trim_prefix("\ufeff")
	if text.to_utf8_buffer().size() > MAX_LEVEL_BYTES:
		return {"error": "Level is too large (maximum 64 MB)."}
	if not text.begins_with("{"):
		var decoded := decode_level_code(text)
		if decoded.has("error"):
			return decoded
		text = decoded["text"]
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"error": "Invalid level JSON at line %d." % parser.get_error_line()}
	var level = parser.data
	if not level is Dictionary or not level.get("parts") is Array:
		return {"error": "This is not a Gunsaw level (missing parts array)."}
	if level["parts"].size() > MAX_PARTS:
		return {"error": "Level contains too many objects."}
	var types := {}
	for definition in definitions:
		types[definition["id"]] = definition
	var gates: Array[Dictionary] = []
	var wires: Array[Dictionary] = []
	var sources := {}
	var preserved: Array = []
	var max_activation_id := 0
	for part_index in range(level["parts"].size()):
		var part = level["parts"][part_index]
		if not part is Dictionary or not part.get("path") is String or not valid_vector(part.get("pos")):
			return {"error": "Invalid object at index %d." % part_index}
		if not valid_number(part.get("rot", 0)):
			return {"error": "Invalid rotation at object %d." % part_index}
		var parsed := parse_part(part, types, gates.size() + 1)
		if parsed.has("error"):
			return {"error": "Object %d: %s" % [part_index, parsed["error"]]}
		max_activation_id = maxi(max_activation_id, largest_id(part))
		if parsed.is_empty():
			preserved.append(part.duplicate(true))
			continue
		var gate: Dictionary = parsed["gate"]
		var gate_index := gates.size()
		gates.append(gate)
		for port_index in range(gate["gunsaw_output_ids"].size()):
			var channel: int = gate["gunsaw_output_ids"][port_index]
			if channel >= 0:
				if not sources.has(channel):
					sources[channel] = []
				sources[channel].append({"gate": gate_index, "port": port_index})
	for gate_index in range(gates.size()):
		var gate := gates[gate_index]
		var external_inputs: Array = []
		for port_index in range(gate["gunsaw_input_ids"].size()):
			var channel: int = gate["gunsaw_input_ids"][port_index]
			external_inputs.append(channel if not sources.has(channel) else -1)
			for source in sources.get(channel, []):
				if wires.size() >= MAX_WIRES:
					return {"error": "Level contains too many logic connections."}
				wires.append({"from_gate": source["gate"], "from_port": source["port"], "to_gate": gate_index, "to_port": port_index})
		gate["gunsaw_external_inputs"] = external_inputs
	var source_level: Dictionary = level.duplicate(true)
	source_level["parts"] = preserved
	return {"gates": gates, "wires": wires, "source_level": source_level, "next_id": gates.size() + 1, "next_activation_id": max_activation_id + 1, "preserved_count": preserved.size()}

static func decode_level_code(text: String) -> Dictionary:
	var whitespace := RegEx.new()
	whitespace.compile("\\s+")
	text = whitespace.sub(text, "", true)
	var base64_pattern := RegEx.new()
	base64_pattern.compile("^[A-Za-z0-9+/]+={0,2}$")
	if text.is_empty() or text.length() % 4 != 0 or base64_pattern.search(text) == null:
		return {"error": "Invalid Gunsaw level code (expected Base64 or level JSON)."}
	var compressed := Marshalls.base64_to_raw(text)
	compressed.append_array(PackedByteArray([0, 0]))
	var stream := StreamPeerGZIP.new()
	if stream.start_decompression(true) != OK:
		return {"error": "Could not start level decompression."}
	if stream.put_data(PackedByteArray([0x78, 0x9c])) != OK:
		return {"error": "Could not initialize level decompression."}
	var output := PackedByteArray()
	var offset := 0
	while offset < compressed.size():
		var written := stream.put_partial_data(compressed.slice(offset, mini(offset + 16384, compressed.size())))
		if written[0] != OK:
			return {"error": "Invalid compressed Gunsaw level."}
		offset += int(written[1])
		var available := stream.get_available_bytes()
		if output.size() + available > MAX_LEVEL_BYTES:
			return {"error": "Decompressed level is too large (maximum 64 MB)."}
		if available > 0:
			var chunk := stream.get_data(available)
			if chunk[0] != OK:
				return {"error": "Could not decompress level."}
			output.append_array(chunk[1])
		if int(written[1]) == 0 and available == 0:
			return {"error": "Invalid or truncated compressed level."}
	if output.is_empty():
		return {"error": "Level code is empty or invalid."}
	return {"text": output.get_string_from_utf8()}

static func parse_part(part: Dictionary, types: Dictionary, id: int) -> Dictionary:
	var type_id := ""
	var data := {}
	var input_ids: Array = []
	var output_ids: Array = []
	match part["path"]:
		"Building/Button":
			type_id = "MP/IO/BUTTON"
			output_ids = [part.get("id", 0)]
		"Building/Lamp", "Building/ColorLamp":
			type_id = "MP/IO/LAMP"
			input_ids = [part.get("id", 0)]
		"Building/WhiteTile":
			if not valid_vector(part.get("size")) or float(part.get("rot", 0)) != 0.0:
				return {}
			if float(part["size"]["x"]) <= 0 or float(part["size"]["y"]) <= 0:
				return {}
			type_id = "EDITOR/WHITETILE"
		"MP/CustomProp":
			var payload = JSON.parse_string(str(part.get("team", "")))
			if not payload is Dictionary or not PORT_FIELDS.has(payload.get("type", "")) or int(payload.get("version", 1)) != 1:
				return {}
			type_id = payload["type"]
			var parsed_data = JSON.parse_string(str(payload.get("data", "{}")))
			if not parsed_data is Dictionary:
				return {"error": "Invalid logic component data."}
			data = parsed_data
			for field in ["period", "value", "initialHigh", "initialQ", "mode"]:
				if data.has(field) and not valid_number(data[field]):
					return {"error": "Invalid %s setting." % field}
			for field in PORT_FIELDS[type_id][0]:
				input_ids.append(data.get(field, -1))
			for field in PORT_FIELDS[type_id][1]:
				output_ids.append(data.get(field, -1))
		_:
			return {}
	for channel in input_ids + output_ids:
		if not valid_id(channel):
			return {"error": "Invalid Activation ID."}
	var definition: Dictionary = types.get(type_id, {"name": "WHITE TILE", "inputs": [], "outputs": []})
	var position := Vector2(float(part["pos"]["x"]), -float(part["pos"]["y"])) * SCALE
	var gate := {
		"id": id, "type_id": type_id, "name": definition["name"], "position": position,
		"input_names": definition["inputs"].duplicate(), "output_names": definition["outputs"].duplicate(),
		"inputs": [], "outputs": [], "previous_inputs": [], "memory": int(data.get("initialQ", 0)) != 0,
		"state": true, "lamp_color": str(part.get("team", "FFD23F")).trim_prefix("#"),
		"pulse_pending": false, "text": "", "export": true,
		"gunsaw_part": part.duplicate(true), "gunsaw_data": data,
		"gunsaw_input_ids": input_ids, "gunsaw_output_ids": output_ids
	}
	if type_id == "MP/IO/LAMP" and not Color.html_is_valid(gate["lamp_color"]):
		gate["lamp_color"] = "FFFFFF"
	for _port in definition["inputs"]:
		gate["inputs"].append(false)
		gate["previous_inputs"].append(false)
	for _port in definition["outputs"]:
		gate["outputs"].append(false)
	if type_id == "EDITOR/WHITETILE":
		var size := Vector2(float(part["size"]["x"]), float(part["size"]["y"])) * SCALE
		gate["size"] = size
		gate["position"] = position - Vector2(size.x * 0.5, size.y)
	return {"gate": gate}

static func valid_vector(value: Variant) -> bool:
	return value is Dictionary and valid_number(value.get("x")) and valid_number(value.get("y"))

static func stringify_json(value: Variant, indent: String = "") -> String:
	var text := JSON.stringify(value, indent)
	if not text.contains("\\v"):
		return text
	var pieces := PackedStringArray()
	var start := 0
	var index := text.find("\\")
	while index >= 0 and index + 1 < text.length():
		if text[index + 1] == "v":
			pieces.append(text.substr(start, index - start))
			pieces.append("\\u000b")
			start = index + 2
		index = text.find("\\", index + 2)
	pieces.append(text.substr(start))
	return "".join(pieces)

static func valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func valid_id(value: Variant) -> bool:
	return valid_number(value) and float(value) == floor(float(value)) and float(value) >= -1 and float(value) < 2147483647

static func largest_id(value: Variant) -> int:
	var result := 0
	if value is Dictionary:
		for key in value:
			if key in ["team", "data"] and value[key] is String:
				var parser := JSON.new()
				if value[key].strip_edges().begins_with("{") and parser.parse(value[key]) == OK:
					result = maxi(result, largest_id(parser.data))
			elif valid_id(value[key]):
				result = maxi(result, int(value[key]))
			elif value[key] is Dictionary or value[key] is Array:
				result = maxi(result, largest_id(value[key]))
	elif value is Array:
		for item in value:
			result = maxi(result, largest_id(item))
	return result

static func merge_exported_part(gate: Dictionary, generated: Dictionary) -> Dictionary:
	if not gate.has("gunsaw_part"):
		return generated
	var part: Dictionary = gate["gunsaw_part"].duplicate(true)
	part["pos"] = generated["pos"]
	match gate["type_id"]:
		"MP/IO/BUTTON":
			part["id"] = generated["id"]
		"MP/IO/LAMP":
			part["id"] = generated["id"]
			if part["path"] == "Building/ColorLamp":
				part["team"] = generated["team"]
		"EDITOR/WHITETILE":
			part["size"] = generated["size"]
		_:
			var payload: Dictionary = JSON.parse_string(part["team"])
			var generated_payload: Dictionary = JSON.parse_string(generated["team"])
			var data: Dictionary = gate["gunsaw_data"].duplicate(true)
			var generated_data: Dictionary = JSON.parse_string(generated_payload["data"])
			var changed := false
			for field in PORT_FIELDS[gate["type_id"]][0] + PORT_FIELDS[gate["type_id"]][1]:
				if int(data.get(field, -1)) != int(generated_data[field]):
					data[field] = int(generated_data[field])
					changed = true
			if changed:
				for field in ["value", "mode", "initialHigh", "initialQ"]:
					if data.has(field):
						data[field] = int(data[field])
				payload["version"] = int(payload.get("version", 1))
				payload["data"] = JSON.stringify(data)
				part["team"] = JSON.stringify(payload)
	return part