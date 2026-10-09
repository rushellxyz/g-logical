extends Control

signal parameter_changed(gate_id: int, field: String, value: Variant)

const FIELDS := {
	"MP/Logic/CONST": [["value", "Value", "bool", 1]],
	"MP/Logic/CLOCK": [["period", "Period, s", "number", 1.0, 0.04], ["initialHigh", "Initial HIGH", "bool", 0]],
	"MP/Logic/EDGE": [["mode", "Edge", "choice", 2]],
	"MP/Logic/SR": [["initialQ", "Initial Q", "bool", 0]],
	"MP/Logic/DFF": [["initialQ", "Initial Q", "bool", 0]],
	"MP/Logic/JK": [["initialQ", "Initial Q", "bool", 0]],
	"MP/Logic/TFF": [["initialQ", "Initial Q", "bool", 0]],
	"GUNSAW/DELAY": [["delay", "Delay, s", "number", 0.0, 0.0]],
	"GUNSAW/CYCLE": [["cycleTime", "Cycle, s", "number", 1.0, 0.0]]
}

var _editor: LineEdit
var _gate_id := -1
var _field: Array = []
var _row := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_editor = LineEdit.new()
	_editor.add_theme_font_size_override("font_size", 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#182334")
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_editor.add_theme_stylebox_override("normal", style)
	_editor.tooltip_text = "Enter to apply; Escape to cancel. Changes reset simulation."
	_editor.text_submitted.connect(func(_text: String): commit())
	_editor.focus_exited.connect(commit)
	_editor.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			cancel()
			_editor.accept_event()
	)
	add_child(_editor)
	_editor.hide()

static func node_size(gate: Dictionary, base: Vector2) -> Vector2:
	if gate["type_id"] == "EDITOR/WHITETILE":
		return gate.get("size", Vector2(320, 64))
	if gate["type_id"] == "EDITOR/CUSTOM":
		var custom_size: Vector2 = base
		if gate.get("custom_layout_mode", "Inline") == "Expand":
			var saved_size = gate.get("custom_size", base)
			if saved_size is Vector2:
				custom_size = saved_size
			elif saved_size is Dictionary:
				custom_size = Vector2(float(saved_size.get("x", base.x)), float(saved_size.get("y", base.y)))
			elif saved_size is Array and saved_size.size() == 2:
				custom_size = Vector2(float(saved_size[0]), float(saved_size[1]))
		var port_count: int = maxi(gate.get("input_names", []).size(), gate.get("output_names", []).size())
		custom_size.y = maxf(maxf(custom_size.y, base.y), 50.0 + float(port_count + 1) * 14.0)
		return custom_size
	var count: int = FIELDS.get(gate["type_id"], []).size()
	return base + Vector2(0, 4 + count * 28 if count > 0 else 0)

static func port_y(gate: Dictionary, input: bool, port: int) -> float:
	var inputs: Array = gate.get("inputs", [])
	var outputs: Array = gate.get("outputs", [])
	var count: int = inputs.size() if input else outputs.size()
	var spacing := 42.0 / float(maxi(count, 1))
	if gate.get("type_id", "") == "EDITOR/CUSTOM" and maxi(inputs.size(), outputs.size()) > 4:
		spacing = 14.0
	return 42.0 + (port + 1) * spacing

static func field_rect(gate: Dictionary, row: int) -> Rect2:
	return Rect2(gate["position"] + Vector2(8, 96 + row * 28), Vector2(154, 24))

static func field_at(gate: Dictionary, point: Vector2) -> int:
	var fields: Array = FIELDS.get(gate["type_id"], [])
	for row in range(fields.size()):
		if field_rect(gate, row).has_point(point):
			return row
	return -1

func draw_fields(canvas: CanvasItem, gate: Dictionary, font: Font) -> void:
	var fields: Array = FIELDS.get(gate["type_id"], [])
	var data: Dictionary = gate.get("gunsaw_data", {})
	for row in range(fields.size()):
		var field: Array = fields[row]
		var rect := field_rect(gate, row)
		var value = data.get(field[0], field[3])
		var text := str(value)
		match field[2]:
			"bool": text = "HIGH  1" if int(value) != 0 else "LOW  0"
			"choice": text = ["Rise", "Fall", "Both"][clampi(int(value), 0, 2)]
			"number": text = String.num(float(value), 3)
		canvas.draw_rect(rect, Color("#182334"))
		canvas.draw_rect(rect, Color("#536b89"), false, 1)
		canvas.draw_string(font, rect.position + Vector2(5, 16), field[1], HORIZONTAL_ALIGNMENT_LEFT, 79, 11, Color("#aab8cb"))
		canvas.draw_string(font, rect.position + Vector2(86, 16), text, HORIZONTAL_ALIGNMENT_RIGHT, 62, 12, Color("#f1d28c"))

func activate(gate: Dictionary, row: int) -> void:
	commit()
	var field: Array = FIELDS[gate["type_id"]][row]
	var value = gate.get("gunsaw_data", {}).get(field[0], field[3])
	match field[2]:
		"bool": parameter_changed.emit(gate["id"], field[0], int(int(value) == 0))
		"choice": parameter_changed.emit(gate["id"], field[0], (int(value) + 1) % 3)
		"number":
			_gate_id = gate["id"]
			_field = field
			_row = row
			_editor.text = str(value)
			_editor.show()
			_editor.grab_focus()
			_editor.select_all()

func update_editor(gates: Array, origin: Vector2, zoom: float, toolbar_height: float, physical: bool) -> void:
	if _gate_id < 0:
		return
	if physical or zoom < 0.5:
		cancel()
		return
	for gate in gates:
		if gate["id"] != _gate_id:
			continue
		if _row >= FIELDS.get(gate["type_id"], []).size() or FIELDS[gate["type_id"]][_row][0] != _field[0]:
			cancel()
			return
		var rect := field_rect(gate, _row)
		_editor.position = origin + rect.position * zoom
		_editor.scale = Vector2(zoom, zoom)
		_editor.size = rect.size
		if _editor.position.y < toolbar_height:
			cancel()
		return
	cancel()

func commit() -> void:
	if _gate_id < 0:
		return
	var gate_id := _gate_id
	var field := _field.duplicate()
	var text := _editor.text.strip_edges().replace(",", ".")
	cancel()
	if text.is_valid_float() and is_finite(text.to_float()):
		parameter_changed.emit(gate_id, field[0], maxf(float(field[4]), text.to_float()))

func cancel() -> void:
	_gate_id = -1
	_editor.hide()
	_editor.release_focus()
