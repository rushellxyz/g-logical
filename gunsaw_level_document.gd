extends RefCounted

static func normalize_json(text: String) -> String:
	var tokens := RegEx.new()
	tokens.compile('"(?:\\\\.|[^"\\\\])*"|-?Infinity|NaN')
	var pieces := PackedStringArray()
	var offset := 0
	for token in tokens.search_all(text):
		if token.get_string().begins_with('"'):
			continue
		pieces.append(text.substr(offset, token.get_start() - offset))
		pieces.append("null")
		offset = token.get_end()
	pieces.append(text.substr(offset))
	return "".join(pieces)

static func skip_space(text: String, offset: int) -> int:
	while offset < text.length() and text[offset] in [" ", "\t", "\r", "\n"]:
		offset += 1
	return offset

static func value_end(text: String, offset: int) -> int:
	var depth := 0
	var quoted := false
	var escaped := false
	for index in range(offset, text.length()):
		var character := text[index]
		if quoted:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == '"':
				quoted = false
				if depth == 0:
					return index + 1
		elif character == '"':
			quoted = true
		elif character in ["{", "["]:
			depth += 1
		elif character in ["}", "]"]:
			if depth == 0:
				return index
			depth -= 1
			if depth == 0:
				return index + 1
		elif depth == 0 and character in [",", " ", "\t", "\r", "\n"]:
			return index
	return text.length()

static func capture(text: String) -> Dictionary:
	var offset := skip_space(text, 1)
	while offset < text.length() and text[offset] != "}":
		var key_end := value_end(text, offset)
		var key = JSON.parse_string(text.substr(offset, key_end - offset))
		offset = skip_space(text, skip_space(text, key_end) + 1)
		if key == "parts":
			var array_start := offset
			var array_end := value_end(text, offset)
			var parts: Array[String] = []
			offset = skip_space(text, offset + 1)
			while offset < array_end - 1:
				var end := value_end(text, offset)
				parts.append(text.substr(offset, end - offset))
				offset = skip_space(text, end)
				if text[offset] == ",":
					offset = skip_space(text, offset + 1)
			return {"text": text, "prefix": text.substr(0, array_start + 1), "suffix": text.substr(array_end - 1), "parts": parts, "preserved_indices": []}
		offset = skip_space(text, value_end(text, offset))
		if text[offset] == ",":
			offset = skip_space(text, offset + 1)
	return {}

static func export_text(document: Dictionary, parts: Array, indices: Array, serialize: Callable) -> String:
	var original: Array = document["parts"]
	var replacements := {}
	var added := PackedStringArray()
	var unchanged := parts.size() == original.size()
	for index in range(parts.size()):
		var source: int = indices[index]
		if source >= 0 and source < original.size() and not replacements.has(source):
			var raw: String = original[source]
			if JSON.parse_string(normalize_json(raw)) == parts[index]:
				replacements[source] = raw
			else:
				replacements[source] = patch_value(raw, parts[index], serialize)
				unchanged = false
		else:
			added.append(serialize.call(parts[index]))
			unchanged = false
	if unchanged:
		return document["text"]
	var output := PackedStringArray()
	for index in range(original.size()):
		if replacements.has(index):
			output.append(replacements[index])
	output.append_array(added)
	return document["prefix"] + ",".join(output) + document["suffix"]

static func patch_value(raw: String, value: Variant, serialize: Callable) -> String:
	var original = JSON.parse_string(normalize_json(raw))
	if original == value:
		return raw
	if not original is Dictionary or not value is Dictionary:
		return serialize.call(value)
	var properties := PackedStringArray()
	var remaining: Dictionary = value.duplicate()
	var offset := skip_space(raw, 1)
	while offset < raw.length() and raw[offset] != "}":
		var key_start := offset
		var key_end := value_end(raw, offset)
		var key = JSON.parse_string(raw.substr(offset, key_end - offset))
		var start := skip_space(raw, skip_space(raw, key_end) + 1)
		var end := value_end(raw, start)
		if remaining.has(key):
			properties.append(raw.substr(key_start, start - key_start) + patch_value(raw.substr(start, end - start), remaining[key], serialize))
			remaining.erase(key)
		offset = skip_space(raw, end)
		if raw[offset] == ",":
			offset = skip_space(raw, offset + 1)
	for key in remaining:
		properties.append(serialize.call(key) + ":" + serialize.call(remaining[key]))
	return "{" + ",".join(properties) + "}"
