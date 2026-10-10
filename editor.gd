extends Node2D

const GunsawLevelImporter = preload("res://gunsaw_level_importer.gd")
const LogicSimulator = preload("res://logic_simulator.gd")
const CanvasGeometry = preload("res://canvas_geometry.gd")
const GateProperties = preload("res://gate_properties.gd")
const RUN_ICON = preload("res://icons/run.svg")
const PAUSE_ICON = preload("res://icons/pause.svg")
const STEP_ICON = preload("res://icons/step.svg")
const RESET_ICON = preload("res://icons/reset.svg")
const SAVE_ICON = preload("res://icons/save.svg")
const LOAD_ICON = preload("res://icons/load.svg")
const IMPORT_ICON = preload("res://icons/import.svg")
const EXPORT_ICON = preload("res://icons/export.svg")

const TOPBAR_HEIGHT := 72.0
const GRID_SIZE := 32.0
const NODE_SIZE := Vector2(170, 92)
const PHYSICAL_UNIT_SIZE := 32.0
const WHITETILE_EXPORT_SCALE := 320.0
const PORT_RADIUS := 7.0
const GATE_TYPES := [
	{"id": "MP/IO/BUTTON", "name": "BUTTON", "inputs": [], "outputs": ["PULSE"]},
	{"id": "MP/IO/LAMP", "name": "LAMP", "inputs": ["IN"], "outputs": []},
	{"id": "EDITOR/COMMENT", "name": "COMMENT", "inputs": [], "outputs": []},
	{"id": "EDITOR/COMPONENT_INPUT", "name": "INPUT", "inputs": [], "outputs": ["OUT"]},
	{"id": "EDITOR/COMPONENT_OUTPUT", "name": "OUTPUT", "inputs": ["IN"], "outputs": []},
	{"id": "MP/Logic/CLOCK", "name": "CLOCK", "inputs": [], "outputs": ["OUT"]},
	{"id": "EDITOR/CLOCK_IN", "name": "CLOCK IN", "inputs": ["CLK"], "outputs": []},
	{"id": "EDITOR/CLOCK_OUT", "name": "CLOCK OUT", "inputs": [], "outputs": ["CLK"]},
	{"id": "MP/Logic/AND", "name": "AND", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/OR", "name": "OR", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/XOR", "name": "XOR", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/XNOR", "name": "XNOR", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/NAND", "name": "NAND", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/NOR", "name": "NOR", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/NOT", "name": "NOT", "inputs": ["IN"], "outputs": ["OUT"]},
	{"id": "MP/Logic/CONST", "name": "CONST", "inputs": [], "outputs": ["OUT"]},
	{"id": "MP/Logic/EDGE", "name": "EDGE", "inputs": ["IN"], "outputs": ["PULSE"]},
	{"id": "MP/Logic/SR", "name": "SR LATCH", "inputs": ["S", "R"], "outputs": ["Q", "/Q"]},
	{"id": "MP/Logic/DFF", "name": "D FLIP-FLOP", "inputs": ["D", "CLK"], "outputs": ["Q", "/Q"]},
	{"id": "MP/Logic/JK", "name": "JK FLIP-FLOP", "inputs": ["J", "K", "CLK"], "outputs": ["Q", "/Q"]},
	{"id": "MP/Logic/TFF", "name": "T FLIP-FLOP", "inputs": ["T", "CLK"], "outputs": ["Q", "/Q"]},
	{"id": "GUNSAW/DELAY", "name": "DELAY", "inputs": ["IN"], "outputs": ["PULSE"]},
	{"id": "GUNSAW/CYCLE", "name": "CYCLE", "inputs": ["TOGGLE"], "outputs": ["PULSE"]}
]

var gates: Array[Dictionary] = []
var wires: Array[Dictionary] = []
var selected_gates: Array[int] = []
var selected_gate := -1
var selected_wire := -1
var wires_visible := true
var dragging_gate := -1
var resizing_gate := -1
var resize_start_position := Vector2.ZERO
var resize_start_size := Vector2.ZERO
var resize_start_mouse := Vector2.ZERO
var resize_edges := Vector2i.ZERO
var drag_offset := Vector2.ZERO
var drag_group_origins: Dictionary = {}
var pending_output := {"gate": -1, "port": -1}
var connecting_wire := false
var tick := 0
var running := false
var simulation_accumulator := 0.0
var next_id := 1
var canvas_offset := Vector2.ZERO
var canvas_zoom := 1.0
var panning := false
var pan_start := Vector2.ZERO
var pan_offset_start := Vector2.ZERO
var button_candidate := -1
var button_press_position := Vector2.ZERO
var active_tool := "SELECT"
var physical_mode := false
var foundry_mode := false
var foundry_layout_mode := "Inline"
var pending_editor_mode := ""
var mode_confirmation: ConfirmationDialog
var component_name_dialog: ConfirmationDialog
var component_name_field: LineEdit
var port_name_dialog: ConfirmationDialog
var port_name_field: LineEdit
var port_name_target := -1
var component_menu: PopupMenu
var foundry_menu_paths: Array[String] = []
var foundry_menu_action := ""
var foundry_inline_button: Button
var foundry_expand_button: Button
var selecting := false
var selection_start := Vector2.ZERO
var selection_current := Vector2.ZERO
var tps_window_start_ms := 0
var ticks_in_tps_window := 0
var ticks_per_second := 0.0
const SAVE_PATH := "user://g-logical-editor.json"
const SAVE_SLOT_COUNT := 5
const MAX_UNDO_STEPS := 100
const EXPORT_PATH := "user://g-logical-level.txt"
var status_text := "Click a gate button, then connect ports."
var font: Font
var toolbar_panel: PanelContainer
var gate_toolbar: HFlowContainer
var run_button: Button
var save_button: Button
var load_button: Button
var physical_button: Button
var editor_mode_button: Button
var foundry_mode_button: Button
var toolbar_height := TOPBAR_HEIGHT
var lamp_color_picker: ColorPickerButton
var save_slot_menu: PopupMenu
var import_menu: PopupMenu
var import_dialog: FileDialog
var gunsaw_source_level: Dictionary = {}
var current_save_slot := 1
var undo_history: Array[Dictionary] = []
var drag_undo_snapshot: Dictionary = {}
var drag_undo_recorded := false
var drawn_status := ""
var drawn_tick := -1
var drawn_tps := -1.0
var drawn_toolbar_height := -1.0
var canvas_geometry := CanvasGeometry.new()
var simulation := LogicSimulator.new()
var compiled_custom_components := false
var compiled_board_gate_count := -1
var compiled_board_wire_count := -1
var gate_properties: GateProperties

func _ready() -> void:
	font = ThemeDB.fallback_font
	save_slot_menu = PopupMenu.new()
	save_slot_menu.id_pressed.connect(_on_save_slot_menu_id_pressed)
	add_child(save_slot_menu)
	component_menu = PopupMenu.new()
	component_menu.id_pressed.connect(_on_component_menu_id_pressed)
	add_child(component_menu)
	mode_confirmation = ConfirmationDialog.new()
	mode_confirmation.title = "Switch editor mode"
	mode_confirmation.confirmed.connect(_confirm_mode_switch)
	add_child(mode_confirmation)
	component_name_dialog = ConfirmationDialog.new()
	component_name_dialog.title = "Save Foundry Component"
	component_name_field = LineEdit.new()
	component_name_field.placeholder_text = "Component name"
	component_name_dialog.add_child(component_name_field)
	component_name_dialog.confirmed.connect(save_foundry_component)
	add_child(component_name_dialog)
	port_name_dialog = ConfirmationDialog.new()
	port_name_dialog.title = "Label component port"
	port_name_field = LineEdit.new()
	port_name_field.placeholder_text = "Port label"
	port_name_dialog.add_child(port_name_field)
	port_name_dialog.confirmed.connect(apply_port_label)
	add_child(port_name_dialog)
	tps_window_start_ms = Time.get_ticks_msec()
	lamp_color_picker = ColorPickerButton.new()
	lamp_color_picker.tooltip_text = "Adjust selected lamp color"
	lamp_color_picker.custom_minimum_size = Vector2(54, 28)
	lamp_color_picker.color_changed.connect(_on_lamp_color_changed)
	build_toolbar()
	gate_properties = GateProperties.new()
	toolbar_panel.get_parent().add_child(gate_properties)
	gate_properties.parameter_changed.connect(func(id: int, field: String, value: Variant): _on_gate_parameter_changed(field, value, id))
	setup_import_dialog()
	get_viewport().size_changed.connect(queue_redraw)
	update_lamp_color_picker()
	queue_redraw()

func _exit_tree() -> void:
	canvas_geometry.stop_routing()

func foundry_directory() -> String:
	var directory := DirAccess.open("user://")
	if directory == null:
		status_text = "Foundry library unavailable: %s." % error_string(DirAccess.get_open_error())
		return ""
	var error := directory.make_dir_recursive("foundry")
	if error != OK and error != ERR_ALREADY_EXISTS:
		status_text = "Foundry library unavailable: %s." % error_string(error)
		return ""
	return "user://foundry"

func foundry_file_name(component_name: String) -> String:
	var safe_name := component_name.strip_edges().validate_filename()
	return safe_name if not safe_name.is_empty() else ""

func open_foundry_save_dialog() -> void:
	if not foundry_mode:
		return
	component_name_field.text = ""
	component_name_dialog.popup_centered(Vector2i(420, 120))

func save_foundry_component() -> void:
	var component_name := component_name_field.text.strip_edges()
	var safe_name := foundry_file_name(component_name)
	if safe_name.is_empty():
		status_text = "Save failed: enter a valid component name."
		return
	var directory := foundry_directory()
	if directory.is_empty():
		return
	var file := FileAccess.open("%s/%s.json" % [directory, safe_name], FileAccess.WRITE)
	if file == null:
		status_text = "Save failed: %s." % error_string(FileAccess.get_open_error())
		return
	var saved_gates := gates.duplicate(true)
	for gate in saved_gates:
		if gate["type_id"] == "EDITOR/WHITETILE":
			gate["size"] = {"x": gate_size(gate).x, "y": gate_size(gate).y}
	LogicSimulator.reset(saved_gates)
	var document := {
		"format": 1,
		"name": component_name,
		"layout": foundry_layout_mode,
		"gates": saved_gates,
		"wires": wires.duplicate(true)
	}
	file.store_string(GunsawLevelImporter.stringify_json(document, "\t"))
	file.close()
	status_text = "Saved Foundry component '%s'." % component_name

func foundry_component_paths() -> Array[String]:
	var directory_path := foundry_directory()
	var result: Array[String] = []
	if directory_path.is_empty():
		return result
	var directory := DirAccess.open(directory_path)
	if directory == null:
		status_text = "Could not list Foundry components: %s." % error_string(DirAccess.get_open_error())
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.get_extension().to_lower() == "json":
			result.append("%s/%s" % [directory_path, entry])
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result

func open_foundry_project_menu() -> void:
	show_foundry_component_menu("open")

func open_custom_component_menu() -> void:
	show_foundry_component_menu("place")

func show_foundry_component_menu(action: String) -> void:
	foundry_menu_action = action
	foundry_menu_paths = foundry_component_paths()
	component_menu.clear()
	for index in range(foundry_menu_paths.size()):
		var path := foundry_menu_paths[index]
		var document = JSON.parse_string(FileAccess.get_file_as_string(path))
		var component_title := str(document.get("name", path.get_file().get_basename())) if document is Dictionary else path.get_file().get_basename()
		component_menu.add_item(component_title, index)
	if foundry_menu_paths.is_empty():
		status_text = "No saved Foundry components."
		return
	component_menu.position = DisplayServer.mouse_get_position()
	component_menu.popup()

func _on_component_menu_id_pressed(index: int) -> void:
	if index < 0 or index >= foundry_menu_paths.size():
		return
	var path := foundry_menu_paths[index]
	var document = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not document is Dictionary or document.get("format", 0) != 1:
		status_text = "Could not open Foundry component: invalid file."
		return
	if foundry_menu_action == "place":
		place_custom_component(document)
	else:
		load_foundry_component(document)

func load_foundry_component(document: Dictionary) -> void:
	if not is_foundry_document_valid(document):
		status_text = "Could not open Foundry component: invalid gate or wire data."
		return
	var loaded_gates: Array[Dictionary] = []
	for gate in document["gates"]:
		var loaded_gate: Dictionary = gate.duplicate(true)
		loaded_gate["position"] = normalized_position(loaded_gate["position"])
		loaded_gates.append(loaded_gate)
	gates = loaded_gates
	wires.clear()
	for wire in document["wires"]:
		wires.append(wire.duplicate(true))
	next_id = 1
	for gate in gates:
		next_id = maxi(next_id, int(gate.get("id", 0)) + 1)
	foundry_layout_mode = "Expand" if document.get("layout", "Inline") == "Expand" else "Inline"
	selected_gates.clear()
	selected_gate = -1
	selected_wire = -1
	tick = 0
	running = false
	LogicSimulator.reset(gates)
	simulation.dirty = true
	canvas_geometry.dirty = true
	update_mode_toolbar()
	rebuild_gate_toolbar()
	status_text = "Opened Foundry component '%s'." % str(document.get("name", "Unnamed"))
	queue_redraw()

func place_custom_component(document: Dictionary) -> void:
	if not is_foundry_document_valid(document):
		status_text = "Could not place Foundry component: invalid gate or wire data."
		return
	var asset_gates: Array = document.get("gates", [])
	var asset_wires: Array = document.get("wires", [])
	LogicSimulator.reset(asset_gates)
	var inputs: Array[Dictionary] = []
	var outputs: Array[Dictionary] = []
	for index in range(asset_gates.size()):
		var asset_gate: Dictionary = asset_gates[index]
		if asset_gate.get("type_id", "") == "EDITOR/COMPONENT_INPUT":
			inputs.append({"gate": index, "label": str(asset_gate["output_names"][0])})
		elif asset_gate.get("type_id", "") == "EDITOR/COMPONENT_OUTPUT":
			outputs.append({"gate": index, "label": str(asset_gate["input_names"][0])})
	var spawn_position := snap_position(screen_to_canvas(get_viewport_rect().size * 0.5) - NODE_SIZE * 0.5)
	var gate := {
		"id": next_id,
		"type_id": "EDITOR/CUSTOM",
		"name": str(document.get("name", "CUSTOM")),
		"position": spawn_position,
		"input_names": inputs.map(func(port: Dictionary): return port["label"]),
		"output_names": outputs.map(func(port: Dictionary): return port["label"]),
		"inputs": [],
		"outputs": [],
		"previous_inputs": [],
		"memory": false,
		"state": true,
		"pulse_pending": false,
		"export": false,
		"custom_layout_mode": str(document.get("layout", "Inline")),
		"custom_gates": asset_gates.duplicate(true),
		"custom_wires": asset_wires.duplicate(true),
		"custom_inputs": inputs,
		"custom_outputs": outputs,
		"custom_origin": Vector2.ZERO,
		"custom_size": NODE_SIZE
	}
	if gate["custom_layout_mode"] == "Expand":
		var min_position := Vector2(INF, INF)
		var max_position := Vector2(-INF, -INF)
		for child_gate in asset_gates:
			var child_position := normalized_position(child_gate["position"])
			min_position = min_position.min(child_position)
			max_position = max_position.max(normalized_position(child_position) + GateProperties.node_size(child_gate, NODE_SIZE))
		gate["custom_origin"] = min_position
		gate["custom_size"] = max_position - min_position + Vector2(32, 64)
		gate["position"] = spawn_position
	for _port in inputs:
		gate["inputs"].append(false)
		gate["previous_inputs"].append(false)
	for _port in outputs:
		gate["outputs"].append(false)
	push_undo_state()
	gates.append(gate)
	next_id += 1
	selected_gates = [gates.size() - 1]
	selected_gate = gates.size() - 1
	selected_wire = -1
	status_text = "Placed custom component '%s'." % gate["name"]
	queue_redraw()

func is_foundry_document_valid(document: Dictionary) -> bool:
	var document_gates = document.get("gates", null)
	var document_wires = document.get("wires", null)
	if not document_gates is Array or document_gates.is_empty() or not document_wires is Array:
		return false
	var layout := str(document.get("layout", "Inline"))
	if layout not in ["Inline", "Expand"]:
		return false
	for gate in document_gates:
		if not gate is Dictionary or not gate.has("type_id") or not gate.has("position") or not is_valid_position(gate["position"]):
			return false
		if not gate.get("input_names", null) is Array or not gate.get("output_names", null) is Array:
			return false
		if not gate.get("inputs", null) is Array or not gate.get("outputs", null) is Array or not gate.get("previous_inputs", null) is Array:
			return false
		if gate["inputs"].size() != gate["input_names"].size() or gate["previous_inputs"].size() != gate["input_names"].size() or gate["outputs"].size() != gate["output_names"].size():
			return false
		if gate["type_id"] in ["EDITOR/WHITETILE", "EDITOR/CLOCK_IN", "EDITOR/CLOCK_OUT", "EDITOR/COMMENT", "EDITOR/CUSTOM"]:
			return false
		if gate["type_id"] in ["MP/IO/BUTTON", "MP/IO/LAMP"] and layout != "Expand":
			return false
		var type_is_known := false
		for definition in GATE_TYPES:
			if definition["id"] == gate["type_id"]:
				type_is_known = true
				if definition["inputs"].size() != gate["input_names"].size() or definition["outputs"].size() != gate["output_names"].size():
					return false
				break
		if not type_is_known:
			return false
	for wire in document_wires:
		if not wire is Dictionary:
			return false
		for key in ["from_gate", "from_port", "to_gate", "to_port"]:
			if not wire.has(key):
				return false
		var from_gate := int(wire["from_gate"])
		var to_gate := int(wire["to_gate"])
		if from_gate < 0 or from_gate >= document_gates.size() or to_gate < 0 or to_gate >= document_gates.size():
			return false
		if int(wire["from_port"]) < 0 or int(wire["from_port"]) >= document_gates[from_gate]["output_names"].size():
			return false
		if int(wire["to_port"]) < 0 or int(wire["to_port"]) >= document_gates[to_gate]["input_names"].size():
			return false
	return true

func is_valid_position(value: Variant) -> bool:
	if value is Vector2:
		return true
	if value is Dictionary:
		return value.has("x") and value.has("y")
	if value is Array:
		return value.size() == 2
	if value is String:
		return value.trim_prefix("(").trim_suffix(")").split(",").size() == 2
	return false

func apply_port_label() -> void:
	if port_name_target < 0 or port_name_target >= gates.size():
		return
	var gate: Dictionary = gates[port_name_target]
	var label := port_name_field.text.strip_edges()
	if label.is_empty():
		status_text = "Port label cannot be empty."
		return
	push_undo_state()
	gate["name"] = label
	if gate["type_id"] == "EDITOR/COMPONENT_INPUT":
		gate["output_names"][0] = label
	elif gate["type_id"] == "EDITOR/COMPONENT_OUTPUT":
		gate["input_names"][0] = label
	status_text = "Renamed Foundry port to '%s'." % label
	queue_redraw()

func _process(_delta: float) -> void:
	if canvas_geometry.advance_routing():
		queue_redraw()
	toolbar_height = toolbar_panel.size.y
	update_run_button()
	run_button.button_pressed = running
	if save_button != null and load_button != null:
		save_button.tooltip_text = "Save named Foundry component [Ctrl+S]" if foundry_mode else "Save to slot %d [Ctrl+S]" % current_save_slot
		load_button.tooltip_text = "Open named Foundry component [Ctrl+O]" if foundry_mode else "Load from slot %d [Ctrl+O]" % current_save_slot
	update_ticks_per_second()
	update_lamp_color_picker()
	if running:
		simulation_accumulator = minf(simulation_accumulator + _delta, 0.25)
		var deadline := Time.get_ticks_usec() + 8000
		while simulation_accumulator + 0.000000001 >= LogicSimulator.STEP_SECONDS:
			simulation_accumulator = maxf(0.0, simulation_accumulator - LogicSimulator.STEP_SECONDS)
			simulate_tick()
			if Time.get_ticks_usec() >= deadline:
				break
	else:
		simulation_accumulator = 0.0
	gate_properties.update_editor(gates, canvas_transform_origin(), canvas_zoom, toolbar_height, physical_mode or foundry_mode)
	if drawn_status != status_text or drawn_tick != tick or drawn_tps != ticks_per_second or drawn_toolbar_height != toolbar_height:
		queue_redraw()

func _draw() -> void:
	canvas_geometry.update(gates, wires, NODE_SIZE)
	drawn_status = status_text
	drawn_tick = tick
	drawn_tps = ticks_per_second
	drawn_toolbar_height = toolbar_height
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#111722"))
	draw_rect(Rect2(0, toolbar_height, size.x, maxf(0.0, size.y - toolbar_height)), Color("#542b2b") if foundry_mode else Color("#15271f") if physical_mode else Color("#151c29"))
	draw_set_transform(canvas_transform_origin(), 0.0, Vector2(canvas_zoom, canvas_zoom))
	var canvas_top_left := screen_to_canvas(Vector2(0, toolbar_height))
	var canvas_bottom_right := screen_to_canvas(size)
	var visible_canvas := Rect2(canvas_top_left, canvas_bottom_right - canvas_top_left).abs().grow(16.0 / canvas_zoom)
	var grid_spacing := GRID_SIZE
	while grid_spacing * canvas_zoom < 12.0:
		grid_spacing *= 2.0
	var first_grid_x := floori(canvas_top_left.x / grid_spacing) - 1
	var last_grid_x := ceili(canvas_bottom_right.x / grid_spacing) + 1
	var grid_color := Color("#a34c4c") if foundry_mode else Color("#28543f") if physical_mode else Color("#202a3a")
	for x in range(first_grid_x, last_grid_x + 1):
		var grid_x := x * grid_spacing
		draw_line(Vector2(grid_x, canvas_top_left.y), Vector2(grid_x, canvas_bottom_right.y), grid_color, 1.0 / canvas_zoom)
	var first_grid_y := floori((canvas_top_left.y - TOPBAR_HEIGHT) / grid_spacing) - 1
	var last_grid_y := ceili((canvas_bottom_right.y - TOPBAR_HEIGHT) / grid_spacing) + 1
	for y in range(first_grid_y, last_grid_y + 1):
		var grid_y := TOPBAR_HEIGHT + y * grid_spacing
		draw_line(Vector2(canvas_top_left.x, grid_y), Vector2(canvas_bottom_right.x, grid_y), grid_color, 1.0 / canvas_zoom)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(gates.size()):
		if gates[i]["type_id"] == "EDITOR/WHITETILE" and not physical_mode:
			continue
		if not foundry_mode and gates[i]["type_id"] in ["EDITOR/COMPONENT_INPUT", "EDITOR/COMPONENT_OUTPUT"]:
			continue
		if physical_mode and not is_physical_gate(gates[i]):
			continue
		if not canvas_geometry.gate_bounds[i].intersects(visible_canvas):
			continue
		_draw_gate(gates[i], i)
	if not physical_mode and wires_visible:
		var wire_view := visible_canvas.grow(9.0 / canvas_zoom)
		for i in range(wires.size()):
			if canvas_geometry.wire_bounds[i].intersects(wire_view, true):
				_draw_wire(wires[i], i == selected_wire, i)
	if selecting:
		draw_rect(Rect2(selection_start, selection_current - selection_start).abs(), Color("#6ca9e8", 0.18), true)
		draw_rect(Rect2(selection_start, selection_current - selection_start).abs(), Color("#8bc5f5"), false, 1.0)
	if not physical_mode and pending_output["gate"] >= 0 and get_local_mouse_position().y >= toolbar_height:
		draw_set_transform(canvas_transform_origin(), 0.0, Vector2(canvas_zoom, canvas_zoom))
		var start := port_position(pending_output["gate"], false, pending_output["port"])
		var end := screen_to_canvas(get_local_mouse_position())
		if canvas_geometry.orthogonal:
			var path := canvas_geometry.route(start, end, canvas_geometry.gate_bounds[pending_output["gate"]], Rect2(end, Vector2.ZERO), pending_output["port"], 0)
			draw_circuit_wire(path, Color("#895b29"), 8.0)
		else:
			draw_line(start, end, Color("#99752c"), 3.0 / canvas_zoom)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var routing_label := "CIRCUIT" if canvas_geometry.orthogonal else "STRAIGHT"
	if canvas_geometry.orthogonal and canvas_geometry.routing_index < canvas_geometry.routing_wires.size():
		routing_label += " %d/%d" % [canvas_geometry.routing_index, canvas_geometry.routing_wires.size()]
	if canvas_geometry.orthogonal and canvas_geometry.routing_failures > 0:
		routing_label += "; unrouted: %d" % canvas_geometry.routing_failures
	draw_string(font, Vector2(18, get_viewport_rect().size.y - 18), "Tick %d  |  TPS %.1f  |  Lines [L]: %s  |  Routing [Ctrl+L]: %s  |  %s" % [tick, ticks_per_second, "ON" if wires_visible else "OFF", routing_label, status_text], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#aab8cb"))

func build_toolbar() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	toolbar_panel = PanelContainer.new()
	layer.add_child(toolbar_panel)
	toolbar_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#202b3d")
	background.content_margin_left = 12
	background.content_margin_right = 12
	background.content_margin_top = 10
	background.content_margin_bottom = 10
	toolbar_panel.add_theme_stylebox_override("panel", background)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	toolbar_panel.add_child(rows)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	rows.add_child(header)
	var branding := VBoxContainer.new()
	branding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	branding.add_theme_constant_override("separation", 2)
	header.add_child(branding)
	var title := Label.new()
	title.text = "G-LOGICAL"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#f2f5fb"))
	branding.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Gunsaw logic editor"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#95a5bd"))
	branding.add_child(subtitle)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(tools)
	editor_mode_button = toolbar_button(tools, "EDITOR", func(): request_mode_switch("editor"))
	physical_button = toolbar_button(tools, "PHYSICAL", func(): request_mode_switch("physical"))
	foundry_mode_button = toolbar_button(tools, "FOUNDRY", func(): request_mode_switch("foundry"))
	editor_mode_button.tooltip_text = "Switch to logic editor"
	physical_button.tooltip_text = "Switch to physical mode"
	foundry_mode_button.tooltip_text = "Close current project and enter Foundry"
	editor_mode_button.toggle_mode = true
	physical_button.toggle_mode = true
	foundry_mode_button.toggle_mode = true
	foundry_inline_button = toolbar_button(tools, "INLINE", func(): set_foundry_layout("Inline"))
	foundry_expand_button = toolbar_button(tools, "EXPAND", func(): set_foundry_layout("Expand"))
	foundry_inline_button.toggle_mode = true
	foundry_expand_button.toggle_mode = true
	foundry_inline_button.set_pressed_no_signal(true)
	var select_button := toolbar_button(tools, "SELECT", func():
		active_tool = "SELECT"
		status_text = "Selection tool active."
	)
	select_button.toggle_mode = true
	select_button.set_pressed_no_signal(true)
	select_button.pressed.connect(func(): select_button.set_pressed_no_signal(true))
	update_mode_toolbar()
	tools.add_child(lamp_color_picker)
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_FILL
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 6)
	header.add_child(actions)
	save_button = toolbar_icon_button(actions, SAVE_ICON, "Save to slot %d [Ctrl+S]" % current_save_slot, func():
		if foundry_mode:
			open_foundry_save_dialog()
		else:
			open_save_slot_menu(get_global_mouse_position(), true)
	)
	load_button = toolbar_icon_button(actions, LOAD_ICON, "Load from slot %d [Ctrl+O]" % current_save_slot, func():
		if foundry_mode:
			open_foundry_project_menu()
		else:
			open_save_slot_menu(get_global_mouse_position(), false)
	)
	toolbar_icon_button(actions, IMPORT_ICON, "Import Gunsaw level [Ctrl+I]", func():
		if foundry_mode:
			status_text = "Gunsaw import is unavailable in Foundry mode."
			return
		import_menu.position = DisplayServer.mouse_get_position()
		import_menu.popup()
	)
	var export_button := toolbar_icon_button(actions, EXPORT_ICON, "Export Gunsaw level [Ctrl+E]", export_gunsaw)
	export_button.add_theme_stylebox_override("normal", toolbar_button_style(Color("#486b55")))
	run_button = toolbar_icon_button(actions, RUN_ICON, "Run simulation", func():
		running = not running
		update_run_button()
		status_text = "Simulation running." if running else "Simulation paused."
	)
	run_button.toggle_mode = true
	run_button.add_theme_stylebox_override("pressed", toolbar_button_style(Color("#385e58")))
	toolbar_icon_button(actions, STEP_ICON, "Advance one step [Space]", simulate_tick)
	var reset_button := toolbar_icon_button(actions, RESET_ICON, "Stop simulation and restore initial component states", reset_simulation)
	reset_button.add_theme_stylebox_override("normal", toolbar_button_style(Color("#963e45")))
	reset_button.add_theme_stylebox_override("hover", toolbar_button_style(Color("#b54c54")))
	reset_button.add_theme_stylebox_override("pressed", toolbar_button_style(Color("#752e35")))
	reset_button.tooltip_text = "Stop simulation and restore initial component states."
	gate_toolbar = HFlowContainer.new()
	gate_toolbar.add_theme_constant_override("h_separation", 6)
	gate_toolbar.add_theme_constant_override("v_separation", 6)
	rows.add_child(gate_toolbar)
	rebuild_gate_toolbar()

func toolbar_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(82, 28)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color("#f1f5fa"))
	button.add_theme_color_override("font_hover_color", Color("#f1f5fa"))
	button.add_theme_color_override("font_pressed_color", Color("#f1f5fa"))
	button.add_theme_stylebox_override("normal", toolbar_button_style(Color("#34445d")))
	button.add_theme_stylebox_override("hover", toolbar_button_style(Color("#405571")))
	button.add_theme_stylebox_override("pressed", toolbar_button_style(Color("#4875a5")))
	button.add_theme_stylebox_override("hover_pressed", toolbar_button_style(Color("#4875a5")))
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func toolbar_icon_button(parent: Control, icon: Texture2D, tooltip: String, action: Callable) -> Button:
	var button := toolbar_button(parent, "", action)
	button.icon = icon
	button.custom_minimum_size = Vector2(36, 28)
	button.tooltip_text = tooltip
	return button

func update_run_button() -> void:
	run_button.icon = PAUSE_ICON if running else RUN_ICON
	run_button.tooltip_text = "Pause simulation" if running else "Run simulation"

func _on_gate_parameter_changed(field: String, value: Variant, gate_id: int = -1) -> void:
	var gate_index := selected_gate
	if gate_id >= 0:
		gate_index = -1
		for i in range(gates.size()):
			if gates[i]["id"] == gate_id:
				gate_index = i
				break
	if gate_index < 0 or gate_index >= gates.size():
		return
	var gate: Dictionary = gates[gate_index]
	var fields: Array = GateProperties.FIELDS.get(gate["type_id"], [])
	var allowed := false
	for definition in fields:
		if definition[0] == field:
			allowed = true
			if definition[2] == "number":
				if not is_finite(float(value)):
					return
				value = maxf(float(definition[4]), float(value))
			elif definition[2] == "bool":
				value = int(int(value) != 0)
			else:
				value = clampi(int(value), 0, 2)
	if not allowed or gate.get("gunsaw_data", {}).get(field) == value:
		return
	push_undo_state()
	if not gate.has("gunsaw_data"):
		gate["gunsaw_data"] = {}
	gate["gunsaw_data"][field] = value
	reset_simulation()
	status_text = "Updated %s: %s. Simulation reset." % [gate["name"], field]

func toolbar_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func toggle_physical_mode() -> void:
	physical_mode = not physical_mode
	foundry_mode = false
	selected_gates.clear()
	selected_gate = -1
	selected_wire = -1
	pending_output = {"gate": -1, "port": -1}
	selecting = false
	status_text = "Physical mode enabled." if physical_mode else "Editor mode enabled."
	update_mode_toolbar()
	rebuild_gate_toolbar()
	queue_redraw()

func request_mode_switch(target_mode: String) -> void:
	if target_mode == "foundry":
		if foundry_mode:
			return
		if gates.is_empty():
			switch_mode(target_mode)
		else:
			pending_editor_mode = target_mode
			mode_confirmation.dialog_text = "Entering Foundry closes the current project. Continue?"
			mode_confirmation.popup_centered()
	elif foundry_mode:
		if gates.is_empty():
			switch_mode(target_mode)
			return
		pending_editor_mode = target_mode
		mode_confirmation.dialog_text = "Leaving Foundry closes the current project. Continue?"
		mode_confirmation.popup_centered()
	elif target_mode == "editor" or target_mode == "physical":
		physical_mode = target_mode == "physical"
		update_mode_toolbar()
		rebuild_gate_toolbar()
		status_text = "Physical mode enabled." if physical_mode else "Editor mode enabled."
		queue_redraw()

func _confirm_mode_switch() -> void:
	switch_mode(pending_editor_mode)
	pending_editor_mode = ""

func switch_mode(target_mode: String) -> void:
	running = false
	gunsaw_source_level.clear()
	physical_mode = target_mode == "physical"
	foundry_mode = target_mode == "foundry"
	gates.clear()
	wires.clear()
	selected_gates.clear()
	selected_gate = -1
	selected_wire = -1
	next_id = 1
	canvas_offset = Vector2.ZERO
	canvas_zoom = 1.0
	tick = 0
	pending_output = {"gate": -1, "port": -1}
	dragging_gate = -1
	resizing_gate = -1
	selecting = false
	panning = false
	undo_history.clear()
	simulation.dirty = true
	if foundry_mode:
		foundry_inline_button.set_pressed_no_signal(foundry_layout_mode == "Inline")
		foundry_expand_button.set_pressed_no_signal(foundry_layout_mode == "Expand")
		status_text = "Foundry mode. Save named components to use them in Editor mode."
	else:
		status_text = "Editor mode enabled." if target_mode == "editor" else "Physical mode enabled."
	update_mode_toolbar()
	rebuild_gate_toolbar()
	queue_redraw()

func update_mode_toolbar() -> void:
	if editor_mode_button == null:
		return
	if save_button != null and load_button != null:
		save_button.tooltip_text = "Save named Foundry component [Ctrl+S]" if foundry_mode else "Save to slot %d [Ctrl+S]" % current_save_slot
		load_button.tooltip_text = "Open named Foundry component [Ctrl+O]" if foundry_mode else "Load from slot %d [Ctrl+O]" % current_save_slot
	editor_mode_button.button_pressed = not physical_mode and not foundry_mode
	physical_button.button_pressed = physical_mode
	foundry_mode_button.button_pressed = foundry_mode
	foundry_inline_button.visible = foundry_mode
	foundry_expand_button.visible = foundry_mode
	physical_button.add_theme_stylebox_override("pressed", toolbar_button_style(Color("#3d7655")))
	foundry_mode_button.add_theme_stylebox_override("pressed", toolbar_button_style(Color("#854343")))

func set_foundry_layout(layout: String) -> void:
	if layout == "Inline":
		for gate in gates:
			if gate["type_id"] in ["MP/IO/BUTTON", "MP/IO/LAMP"]:
				foundry_inline_button.set_pressed_no_signal(foundry_layout_mode == "Inline")
				foundry_expand_button.set_pressed_no_signal(foundry_layout_mode == "Expand")
				status_text = "Remove all BUTTON and LAMP components before switching to Inline."
				queue_redraw()
				return
	foundry_layout_mode = layout
	foundry_inline_button.set_pressed_no_signal(layout == "Inline")
	foundry_expand_button.set_pressed_no_signal(layout == "Expand")
	rebuild_gate_toolbar()
	status_text = "Foundry layout mode: %s." % layout
	queue_redraw()

func rebuild_gate_toolbar() -> void:
	for child in gate_toolbar.get_children():
		gate_toolbar.remove_child(child)
		child.queue_free()
	if physical_mode:
		toolbar_button(gate_toolbar, "WHITE TILE", add_white_tile)
		return
	for i in range(GATE_TYPES.size()):
		var type_id: String = GATE_TYPES[i]["id"]
		if foundry_mode:
			if type_id in ["EDITOR/COMMENT", "EDITOR/CLOCK_IN", "EDITOR/CLOCK_OUT", "EDITOR/WHITETILE"]:
				continue
			if type_id in ["MP/IO/BUTTON", "MP/IO/LAMP"] and foundry_layout_mode != "Expand":
				continue
		elif type_id in ["EDITOR/COMPONENT_INPUT", "EDITOR/COMPONENT_OUTPUT"]:
			continue
		var button := toolbar_button(gate_toolbar, GATE_TYPES[i]["name"], func():
			if Input.is_key_pressed(KEY_SHIFT) and not selected_gates.is_empty():
				swap_selected_gates(i)
			else:
				add_gate(i)
		)
		button.custom_minimum_size.x = 82 if GATE_TYPES[i]["name"].length() < 6 else 108
		button.tooltip_text = "Click to add; Shift-click to swap selected gates."
	if not foundry_mode:
		var custom_button := toolbar_button(gate_toolbar, "CUSTOM", open_custom_component_menu)
		custom_button.tooltip_text = "Place a saved Foundry component."

func _draw_gate(gate: Dictionary, gate_index: int) -> void:
	if not compiled_custom_components:
		simulation.sync_gate(gate_index)
	draw_set_transform(canvas_transform_origin(), 0.0, Vector2(canvas_zoom, canvas_zoom))
	var rect := Rect2(gate["position"], gate_size(gate))
	if gate["type_id"] == "EDITOR/WHITETILE":
		draw_rect(rect, Color("#434443"), true)
		draw_rect(rect, Color("#9ca9a0") if gate_index not in selected_gates else Color("#71c28b"), false, 2)
		if gate_index in selected_gates:
			for edge_x in [0.0, rect.size.x * 0.5, rect.size.x]:
				for edge_y in [0.0, rect.size.y * 0.5, rect.size.y]:
					draw_rect(Rect2(rect.position + Vector2(edge_x, edge_y) - Vector2(4, 4), Vector2(8, 8)), Color("#71c28b"), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var is_selected: bool = gate_index in selected_gates
	var gate_color := Color("#3d628b") if is_selected else Color("#29364b")
	if gate["type_id"] == "EDITOR/CUSTOM":
		gate_color = Color("#5a426e") if is_selected else Color("#3b2d49")
	elif gate["type_id"] in ["EDITOR/COMPONENT_INPUT", "EDITOR/COMPONENT_OUTPUT"]:
		gate_color = Color("#563d70") if is_selected else Color("#3d2d50")
	if gate["type_id"] == "EDITOR/COMMENT":
		gate_color = Color("#51452d") if not is_selected else Color("#806d3d")
	elif gate["type_id"] == "EDITOR/CLOCK_IN":
		gate_color = Color("#394a68") if not is_selected else Color("#5476a8")
	elif gate["type_id"] == "EDITOR/CLOCK_OUT":
		gate_color = Color("#514c32") if not is_selected else Color("#827546")
	if gate["type_id"] == "MP/IO/LAMP" and gate["state"]:
		var lamp_color := Color(gate.get("lamp_color", "#FFD23F"))
		gate_color = lamp_color.lightened(0.1) if is_selected else lamp_color.darkened(0.25)
	draw_rect(rect, gate_color, true)
	draw_rect(rect, Color("#77a9d8") if is_selected else Color("#485b75"), false, 2)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 28)), Color("#344963"), true)
	if canvas_zoom >= 0.5:
		draw_string(font, rect.position + Vector2(10, 19), gate["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#f5f7fb"))
	if gate["type_id"] == "EDITOR/COMMENT":
		if canvas_zoom >= 0.5:
			draw_string(font, rect.position + Vector2(10, 58), gate["text"], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20, 14, Color("#ffe7a3"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if gate["type_id"] == "EDITOR/CUSTOM" and gate.get("custom_layout_mode", "Inline") == "Expand" and canvas_zoom >= 0.25:
		var child_gates: Array = gate.get("custom_gates", [])
		var child_origin: Vector2 = normalized_position(gate.get("custom_origin", Vector2.ZERO))
		for child_gate in child_gates:
			if not is_custom_child_visible(child_gate):
				continue
			if child_gate.get("type_id", "") in ["EDITOR/COMPONENT_INPUT", "EDITOR/COMPONENT_OUTPUT"]:
				continue
			var child_position: Vector2 = gate["position"] + normalized_position(child_gate.get("position", Vector2.ZERO)) - child_origin + Vector2(16, 40)
			draw_custom_child_gate(child_gate, child_position)
	if gate["type_id"] == "MP/IO/BUTTON" and canvas_zoom >= 0.5:
		draw_string(font, rect.position + Vector2(10, 61), "Click to pulse", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c5d0df"))
	elif gate["type_id"] == "MP/IO/LAMP" and canvas_zoom >= 0.5:
		draw_string(font, rect.position + Vector2(10, 61), "ON" if gate["state"] else "OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffe08a") if gate["state"] else Color("#9aa8b8"))
	for i in range(gate["inputs"].size()):
		var pos := port_position(gate_index, true, i)
		var value: bool = gate["inputs"][i]
		draw_circle(pos, PORT_RADIUS, Color("#61d49a") if value else Color("#68778e"))
		if canvas_zoom >= 0.5:
			draw_string(font, pos + Vector2(12, 4), gate["input_names"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c5d0df"))
	for i in range(gate["outputs"].size()):
		var pos := port_position(gate_index, false, i)
		var value: bool = gate["outputs"][i]
		draw_circle(pos, PORT_RADIUS, Color("#f0c15b") if value else Color("#68778e"))
		if canvas_zoom >= 0.5:
			draw_string(font, pos + Vector2(-58, 4), gate["output_names"][i], HORIZONTAL_ALIGNMENT_RIGHT, 48, 12, Color("#c5d0df"))
	if canvas_zoom >= 0.5:
		gate_properties.draw_fields(self, gate, font)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func is_physical_gate(gate: Dictionary) -> bool:
	if gate["type_id"] == "EDITOR/CUSTOM":
		if gate.get("custom_layout_mode", "Inline") != "Expand":
			return false
		for child_gate in gate.get("custom_gates", []):
			if is_physical_gate(child_gate):
				return true
		return false
	return is_physical_gate_type(gate["type_id"])

func is_custom_child_visible(gate: Dictionary) -> bool:
	return not physical_mode or is_physical_gate(gate)

func is_physical_gate_type(type_id: String) -> bool:
	return type_id in ["MP/IO/BUTTON", "MP/IO/LAMP", "EDITOR/WHITETILE"]

func gate_size(gate: Dictionary) -> Vector2:
	return GateProperties.node_size(gate, NODE_SIZE)

func white_tile_resize_edges(rect: Rect2, point: Vector2) -> Vector2i:
	var handle_radius := 12.0
	if not rect.grow(handle_radius).has_point(point):
		return Vector2i.ZERO
	var edges := Vector2i.ZERO
	if absf(point.x - rect.position.x) <= handle_radius:
		edges.x = -1
	elif absf(point.x - rect.end.x) <= handle_radius:
		edges.x = 1
	if absf(point.y - rect.position.y) <= handle_radius:
		edges.y = -1
	elif absf(point.y - rect.end.y) <= handle_radius:
		edges.y = 1
	return edges

func custom_child_port_position(instance: Dictionary, child: Dictionary, port: int, input: bool, origin: Vector2) -> Vector2:
	var child_type: String = child.get("type_id", "")
	var child_position: Vector2 = instance["position"] + normalized_position(child.get("position", Vector2.ZERO)) - origin + Vector2(16, 40)
	if child_type == "EDITOR/COMPONENT_INPUT":
		return Vector2.INF if input else child_position + Vector2(NODE_SIZE.x, 84)
	if child_type == "EDITOR/COMPONENT_OUTPUT":
		return child_position + Vector2(0, 84) if input else Vector2.INF
	var count: int = child.get("input_names", []).size() if input else child.get("output_names", []).size()
	var y := child_position.y + 42.0 + (port + 1) * (42.0 / float(maxi(count, 1)))
	return Vector2(child_position.x if input else child_position.x + NODE_SIZE.x, y)

func draw_custom_child_gate(gate: Dictionary, child_position: Vector2) -> void:
	var rect := Rect2(child_position, GateProperties.node_size(gate, NODE_SIZE))
	var gate_type: String = gate.get("type_id", "")
	var is_lamp := gate_type == "MP/IO/LAMP"
	var is_button := gate_type == "MP/IO/BUTTON"
	var body_color := Color("#29364b")
	if is_lamp and gate.get("state", true):
		var lamp_color := Color(gate.get("lamp_color", "#FFD23F"))
		body_color = lamp_color.darkened(0.25)
	elif is_button:
		body_color = Color("#42566f")
	draw_rect(rect, body_color, true)
	draw_rect(rect, Color("#647b99"), false, 1)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 24)), Color("#344963"), true)
	draw_string(font, rect.position + Vector2(6, 17), str(gate.get("name", "GATE")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 11, Color("#f5f7fb"))
	if is_button:
		draw_string(font, rect.position + Vector2(8, 54), "BUTTON", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 11, Color("#d8e1ee"))
	elif is_lamp:
		draw_string(font, rect.position + Vector2(8, 54), "ON" if gate.get("state", true) else "OFF", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 11, Color("#ffe08a") if gate.get("state", true) else Color("#9aa8b8"))
	for port in range(gate.get("input_names", []).size()):
		var count: int = gate["input_names"].size()
		var port_y := rect.position.y + 42.0 + (port + 1) * (42.0 / float(maxi(count, 1)))
		draw_circle(Vector2(rect.position.x, port_y), 4.0, Color("#68778e"))
		draw_string(font, Vector2(rect.position.x + 7, port_y + 4), str(gate["input_names"][port]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 9, Color("#c5d0df"))
	for port in range(gate.get("output_names", []).size()):
		var count: int = gate["output_names"].size()
		var port_y := rect.position.y + 42.0 + (port + 1) * (42.0 / float(maxi(count, 1)))
		draw_circle(Vector2(rect.end.x, port_y), 4.0, Color("#68778e"))
		draw_string(font, Vector2(rect.end.x - 56, port_y + 4), str(gate["output_names"][port]), HORIZONTAL_ALIGNMENT_RIGHT, 48, 9, Color("#c5d0df"))

func _draw_wire(wire: Dictionary, selected: bool, wire_index: int) -> void:
	var a: Vector2 = canvas_geometry.wire_starts[wire_index]
	var b: Vector2 = canvas_geometry.wire_ends[wire_index]
	draw_set_transform(canvas_transform_origin(), 0.0, Vector2(canvas_zoom, canvas_zoom))
	var high: bool = simulation.output_high(wire["from_gate"], wire["from_port"]) if not simulation.dirty and not compiled_custom_components else gates[wire["from_gate"]]["outputs"][wire["from_port"]]
	var wire_color := Color("#99752c") if high else Color("#4b596e")
	if selected:
		wire_color = Color("#f28b82")
	if canvas_geometry.orthogonal:
		if not canvas_geometry.wire_routed[wire_index]:
			var unresolved := wire_index < canvas_geometry.routing_index
			var color := Color("#f28b82") if selected else (Color("#c9a66b", 0.5) if unresolved else Color("#71839d", 0.3))
			if unresolved:
				draw_dashed_line(a, b, color, 3.0 if selected else 1.0, 12)
			else:
				draw_line(a, b, color, 3.0 if selected else 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		wire_color = Color("#a47438") if high else Color("#895b29")
		if selected:
			wire_color = Color("#f28b82")
		draw_circuit_wire(canvas_geometry.wire_paths[wire_index], wire_color, 8.0, canvas_geometry.wire_core_segments[wire_index], canvas_geometry.wire_border_segments[wire_index])
		if high and canvas_zoom >= 0.5:
			draw_wire_signals(canvas_geometry.wire_paths[wire_index], canvas_geometry.wire_distances[wire_index])
	else:
		draw_line(a, b, wire_color, 5 if selected else (4 if high else 2))
		draw_circle(a, 4, wire_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_circuit_wire(path: PackedVector2Array, color: Color, width: float, core := PackedVector2Array(), background := PackedVector2Array()) -> void:
	if path.size() < 2:
		return
	if core.is_empty():
		core = CanvasGeometry.WireGeometry.rendered_segments(path, true)
	if background.is_empty():
		background = CanvasGeometry.WireGeometry.rendered_segments(path, false)
	if canvas_zoom >= 0.5:
		var border := Color("#59401f") if color == Color("#895b29") else color.darkened(0.25)
		if color == Color("#a47438"):
			border = Color("#6d5028")
		draw_multiline(background, border, width + 2.0)
		draw_circle(path[0], (width + 2.0) * 0.5, border)
		draw_circle(path[-1], (width + 2.0) * 0.5, border)
	draw_multiline(core, color, width)
	if canvas_zoom >= 0.5:
		draw_circle(path[0], width * 0.5, color)
		draw_circle(path[-1], width * 0.5, color)

func draw_wire_signals(path: PackedVector2Array, distances: PackedFloat32Array) -> void:
	var length: float = distances[-1]
	if length <= 0:
		return
	var count := maxi(1, floori(length / 140.0))
	var spacing := length / count
	var offset := fmod(tick * LogicSimulator.STEP_SECONDS * 250.0, spacing)
	var segment := 1
	for i in range(count):
		var distance := offset + spacing * i
		while segment < distances.size() - 1 and distances[segment] < distance:
			segment += 1
		var span: float = distances[segment] - distances[segment - 1]
		if span > 0:
			var point := path[segment - 1].lerp(path[segment], (distance - distances[segment - 1]) / span)
			draw_circle(point, 3.0, Color("#39ff14"))

func port_position(gate_id: int, input: bool, port: int) -> Vector2:
	var gate: Dictionary = gates[gate_id]
	var y: float = gate["position"].y + GateProperties.port_y(gate, input, port)
	return Vector2(gate["position"].x if input else gate["position"].x + gate_size(gate).x, y)

func canvas_transform_origin() -> Vector2:
	return canvas_offset + Vector2(0, TOPBAR_HEIGHT * (1.0 - canvas_zoom))

func canvas_to_screen(pos: Vector2) -> Vector2:
	return canvas_transform_origin() + pos * canvas_zoom

func screen_to_canvas(pos: Vector2) -> Vector2:
	return (pos - canvas_transform_origin()) / canvas_zoom

func update_lamp_color_picker() -> void:
	if lamp_color_picker == null:
		return
	var is_lamp_selected: bool = selected_gate >= 0 and selected_gate < gates.size() and gates[selected_gate]["type_id"] == "MP/IO/LAMP"
	lamp_color_picker.visible = is_lamp_selected
	if is_lamp_selected and lamp_color_picker.color.to_html(false) != gates[selected_gate].get("lamp_color", "FFD23F"):
		lamp_color_picker.color = Color(gates[selected_gate].get("lamp_color", "#FFD23F"))

func _on_lamp_color_changed(color: Color) -> void:
	if selected_gate < 0 or selected_gate >= gates.size() or gates[selected_gate]["type_id"] != "MP/IO/LAMP":
		return
	if gates[selected_gate]["lamp_color"] == color.to_html(false):
		return
	push_undo_state()
	gates[selected_gate]["lamp_color"] = color.to_html(false)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.alt_pressed and event.shift_pressed and event.keycode == KEY_O:
			open_user_folder()
			return
		if event.ctrl_pressed and event.keycode == KEY_Z:
			undo_last_action()
			return
		if event.ctrl_pressed and event.keycode == KEY_S:
			if foundry_mode:
				open_foundry_save_dialog()
			else:
				save_editor()
			return
		if event.ctrl_pressed and event.keycode == KEY_O:
			if foundry_mode:
				open_foundry_project_menu()
			else:
				load_editor()
			return
		if event.ctrl_pressed and event.keycode == KEY_I:
			if foundry_mode:
				status_text = "Gunsaw import is unavailable in Foundry mode."
				return
			if event.shift_pressed:
				apply_gunsaw_import(GunsawLevelImporter.import_text(DisplayServer.clipboard_get(), GATE_TYPES))
			else:
				import_dialog.popup_centered_ratio(0.7)
			return
		if event.ctrl_pressed and event.keycode == KEY_E:
			export_gunsaw()
			return
		if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_D:
			duplicate_selection(true)
			return
		if event.ctrl_pressed and event.keycode == KEY_D:
			duplicate_selection()
			return
		if event.keycode == KEY_SPACE:
			simulate_tick()
			return
		if selected_gate >= 0 and selected_gate < gates.size() and gates[selected_gate]["type_id"] == "EDITOR/COMMENT":
			if event.keycode == KEY_BACKSPACE:
				var comment_text: String = gates[selected_gate]["text"]
				if comment_text.is_empty():
					return
				push_undo_state()
				gates[selected_gate]["text"] = comment_text.left(maxi(0, comment_text.length() - 1))
				queue_redraw()
				return
			if event.keycode == KEY_ENTER:
				status_text = "Comment editing finished."
				return
			if event.unicode > 0 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
				push_undo_state()
				gates[selected_gate]["text"] += char(event.unicode)
				queue_redraw()
				return
		if (event.physical_keycode == KEY_L or event.keycode == KEY_L) and not event.alt_pressed and not event.meta_pressed:
			if not event.echo:
				if event.ctrl_pressed:
					canvas_geometry.orthogonal = not canvas_geometry.orthogonal
					canvas_geometry.dirty = true
					status_text = "Line routing: %s [Ctrl+L]." % ("circuit" if canvas_geometry.orthogonal else "straight")
				else:
					wires_visible = not wires_visible
					if not wires_visible:
						selected_wire = -1
				queue_redraw()
			return
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			delete_selection()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			handle_press(event.position, event.shift_pressed, event.double_click)
		else:
			if connecting_wire and pending_output["gate"] >= 0 and not physical_mode and event.position.y >= toolbar_height:
				var port := find_port(screen_to_canvas(event.position))
				if port["gate"] >= 0 and port["input"]:
					connect_wire(pending_output["gate"], pending_output["port"], port["gate"], port["port"])
			connecting_wire = false
			if selecting:
				finish_box_selection()
			canvas_geometry.finish_moving()
			queue_redraw()
			if button_candidate >= 0 and button_press_position.distance_to(event.position) <= 8.0:
				gates[button_candidate]["pulse_pending"] = true
				selected_gate = button_candidate
				status_text = "Button pulse queued for the next tick."
			button_candidate = -1
			dragging_gate = -1
			resizing_gate = -1
			drag_group_origins.clear()
			drag_undo_snapshot.clear()
			drag_undo_recorded = false
			selecting = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			panning = true
			pan_start = event.position
			pan_offset_start = canvas_offset
		else:
			panning = false
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var zoom_anchor := screen_to_canvas(event.position)
		var zoom_factor := 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
		var new_zoom: float = canvas_zoom * zoom_factor
		if new_zoom <= 0.0 or not is_finite(new_zoom):
			return
		canvas_zoom = new_zoom
		canvas_offset = event.position - zoom_anchor * canvas_zoom - Vector2(0, TOPBAR_HEIGHT * (1.0 - canvas_zoom))
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		handle_delete_press(event.position)
	if event is InputEventMouseMotion and dragging_gate >= 0:
		var dragged_position := snap_position(screen_to_canvas(event.position) - drag_offset)
		var movement: Vector2 = dragged_position - drag_group_origins[dragging_gate]
		if movement != Vector2.ZERO and not drag_undo_recorded:
			push_undo_snapshot(drag_undo_snapshot, false)
			drag_undo_recorded = true
		for gate_index in selected_gates:
			gates[gate_index]["position"] = snap_position(drag_group_origins[gate_index] + movement)
		canvas_geometry.update_moved_gates(gates, wires, selected_gates, NODE_SIZE)
		queue_redraw()
	if event is InputEventMouseMotion and resizing_gate >= 0:
		var mouse_delta := screen_to_canvas(event.position) - resize_start_mouse
		var snapped_delta := Vector2(snapped(mouse_delta.x, PHYSICAL_UNIT_SIZE), snapped(mouse_delta.y, PHYSICAL_UNIT_SIZE))
		var updated_position := resize_start_position
		var updated_size := resize_start_size
		if resize_edges.x < 0:
			updated_size.x = maxf(PHYSICAL_UNIT_SIZE, resize_start_size.x - snapped_delta.x)
			updated_position.x = resize_start_position.x + resize_start_size.x - updated_size.x
		elif resize_edges.x > 0:
			updated_size.x = maxf(PHYSICAL_UNIT_SIZE, resize_start_size.x + snapped_delta.x)
		if resize_edges.y < 0:
			updated_size.y = maxf(PHYSICAL_UNIT_SIZE, resize_start_size.y - snapped_delta.y)
			updated_position.y = resize_start_position.y + resize_start_size.y - updated_size.y
		elif resize_edges.y > 0:
			updated_size.y = maxf(PHYSICAL_UNIT_SIZE, resize_start_size.y + snapped_delta.y)
		if (updated_size != gate_size(gates[resizing_gate]) or updated_position != gates[resizing_gate]["position"]) and not drag_undo_recorded:
			push_undo_snapshot(drag_undo_snapshot, false)
			drag_undo_recorded = true
		gates[resizing_gate]["position"] = updated_position
		gates[resizing_gate]["size"] = updated_size
		canvas_geometry.dirty = true
		canvas_geometry.update(gates, wires, NODE_SIZE)
		queue_redraw()
	if event is InputEventMouseMotion and selecting:
		selection_current = event.position
		queue_redraw()
	if event is InputEventMouseMotion and panning:
		canvas_offset = pan_offset_start + event.position - pan_start
		clamp_canvas_offset()
		queue_redraw()
	if event is InputEventMouseMotion and pending_output["gate"] >= 0:
		queue_redraw()

func setup_import_dialog() -> void:
	import_menu = PopupMenu.new()
	import_menu.add_item("From file... [Ctrl+I]", 0)
	import_menu.add_item("From clipboard [Ctrl+Shift+I]", 1)
	import_menu.id_pressed.connect(func(id: int):
		if id == 0:
			import_dialog.popup_centered_ratio(0.7)
		else:
			apply_gunsaw_import(GunsawLevelImporter.import_text(DisplayServer.clipboard_get(), GATE_TYPES))
	)
	add_child(import_menu)
	import_dialog = FileDialog.new()
	import_dialog.title = "Import Gunsaw level"
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.filters = PackedStringArray(["*.txt,*.json; Gunsaw levels", "*; All files"])
	import_dialog.use_native_dialog = true
	import_dialog.file_selected.connect(func(path: String):
		apply_gunsaw_import(GunsawLevelImporter.import_file(path, GATE_TYPES))
	)
	add_child(import_dialog)

func apply_gunsaw_import(result: Dictionary) -> void:
	gate_properties.cancel()
	if result.has("error"):
		status_text = "Import failed: %s" % result["error"]
		queue_redraw()
		return
	push_undo_state()
	running = false
	physical_mode = false
	physical_button.button_pressed = false
	rebuild_gate_toolbar()
	gates.assign(result["gates"])
	wires.assign(result["wires"])
	gunsaw_source_level = result["source_level"]
	next_id = result["next_id"]
	tick = 0
	selected_gates.clear()
	selected_gate = -1
	selected_wire = -1
	pending_output = {"gate": -1, "port": -1}
	dragging_gate = -1
	resizing_gate = -1
	button_candidate = -1
	selecting = false
	panning = false
	drag_group_origins.clear()
	drag_undo_snapshot.clear()
	drag_undo_recorded = false
	canvas_zoom = 1.0
	canvas_offset = Vector2.ZERO
	if not gates.is_empty():
		var bounds := Rect2(gates[0]["position"], gate_size(gates[0]))
		for gate in gates:
			bounds = bounds.merge(Rect2(gate["position"], gate_size(gate)))
		var viewport_size := get_viewport_rect().size
		var available := Vector2(maxf(1.0, viewport_size.x - 64), maxf(1.0, viewport_size.y - toolbar_height - 80))
		canvas_zoom = clampf(minf(available.x / bounds.size.x, available.y / bounds.size.y), 0.25, 1.0)
		var center := Vector2(viewport_size.x * 0.5, toolbar_height + (viewport_size.y - toolbar_height) * 0.5)
		canvas_offset = center - bounds.get_center() * canvas_zoom - Vector2(0, TOPBAR_HEIGHT * (1.0 - canvas_zoom))
	status_text = "Imported %d components and %d wires; %d other objects preserved for export. Ctrl+Z to undo." % [gates.size(), wires.size(), result["preserved_count"]]
	queue_redraw()

func open_user_folder() -> void:
	var user_folder := ProjectSettings.globalize_path("user://")
	var result := OS.shell_open(user_folder)
	if result != OK:
		status_text = "Could not open user folder: %s." % error_string(result)
		return
	status_text = "Opened user folder: %s." % user_folder

func open_save_slot_menu(_pos: Vector2, saving: bool) -> void:
	save_slot_menu.clear()
	for slot in range(1, SAVE_SLOT_COUNT + 1):
		var action_id := slot if saving else slot + 10
		save_slot_menu.add_item("%s Slot %d" % ["Save to" if saving else "Load", slot], action_id)
	save_slot_menu.position = DisplayServer.mouse_get_position()
	save_slot_menu.popup()

func _on_save_slot_menu_id_pressed(action_id: int) -> void:
	if action_id >= 1 and action_id <= SAVE_SLOT_COUNT:
		save_editor(action_id)
	elif action_id >= 11 and action_id < 11 + SAVE_SLOT_COUNT:
		load_editor(action_id - 10)

func handle_press(pos: Vector2, _swap_selected := false, double_click := false) -> void:
	connecting_wire = false
	if pos.y < toolbar_height:
		return
	gate_properties.commit()
	if physical_mode:
		var physical_port := find_port(screen_to_canvas(pos))
		if physical_port["gate"] >= 0 and not physical_port["input"]:
			pending_output = {"gate": -1, "port": -1}
			status_text = "Physical mode does not support wires."
			return
	pos = screen_to_canvas(pos)
	var port := find_port(pos)
	if port["gate"] >= 0:
		if port["input"]:
			if pending_output["gate"] >= 0:
				connect_wire(pending_output["gate"], pending_output["port"], port["gate"], port["port"])
			return
		pending_output = {"gate": port["gate"], "port": port["port"]}
		connecting_wire = true
		status_text = "Click an input port or drag to it to finish the connection."
		queue_redraw()
		return
	if not physical_mode and canvas_zoom >= 0.5:
		for i in range(gates.size() - 1, -1, -1):
			if gates[i]["type_id"] == "EDITOR/WHITETILE":
				continue
			var field := GateProperties.field_at(gates[i], pos)
			if field < 0:
				if Rect2(gates[i]["position"], gate_size(gates[i])).has_point(pos):
					break
				continue
			selected_gate = i
			selected_gates = [i]
			selected_wire = -1
			pending_output = {"gate": -1, "port": -1}
			gate_properties.activate(gates[i], field)
			gate_properties.update_editor(gates, canvas_transform_origin(), canvas_zoom, toolbar_height, physical_mode or foundry_mode)
			queue_redraw()
			return
	var wire_index := find_wire(pos)
	if wire_index >= 0:
		selected_gates.clear()
		selected_gate = -1
		selected_wire = wire_index
		pending_output = {"gate": -1, "port": -1}
		status_text = "Selected wire. Press Delete or right-click to remove it."
		queue_redraw()
		return
	for i in range(gates.size() - 1, -1, -1):
		if gates[i]["type_id"] == "EDITOR/WHITETILE" and not physical_mode:
			continue
		if physical_mode and not is_physical_gate(gates[i]):
			continue
		var rect := Rect2(gates[i]["position"], gate_size(gates[i]))
		if rect.has_point(pos):
			if gates[i]["type_id"] == "EDITOR/CUSTOM" and gates[i].get("custom_layout_mode", "Inline") == "Expand":
				var child_gates: Array = gates[i].get("custom_gates", [])
				var child_origin: Vector2 = normalized_position(gates[i].get("custom_origin", Vector2.ZERO))
				for child_index in range(child_gates.size()):
					var child_gate: Dictionary = child_gates[child_index]
					if child_gate.get("type_id", "") != "MP/IO/BUTTON":
						continue
					var child_position: Vector2 = gates[i]["position"] + normalized_position(child_gate.get("position", Vector2.ZERO)) - child_origin + Vector2(16, 40)
					if Rect2(child_position, GateProperties.node_size(child_gate, NODE_SIZE)).has_point(pos):
						child_gate["pulse_pending"] = true
						selected_gates = [i]
						selected_gate = i
						status_text = "Internal button pulse queued for the next tick."
						queue_redraw()
						return
			if foundry_mode and double_click and gates[i]["type_id"] in ["EDITOR/COMPONENT_INPUT", "EDITOR/COMPONENT_OUTPUT"]:
				port_name_target = i
				port_name_field.text = gates[i]["name"]
				port_name_dialog.popup_centered(Vector2i(420, 120))
				selected_gates = [i]
				selected_gate = i
				selected_wire = -1
				return
			if i not in selected_gates:
				selected_gates = [i]
			if gates[i]["type_id"] == "MP/IO/BUTTON":
				selected_gate = i
				selected_wire = -1
				dragging_gate = i
				begin_drag_undo()
				drag_offset = pos - gates[i]["position"]
				drag_group_origins.clear()
				for gate_index in selected_gates:
					drag_group_origins[gate_index] = gates[gate_index]["position"]
				button_candidate = i if selected_gates.size() == 1 else -1
				button_press_position = canvas_to_screen(pos)
				status_text = "Selected %d gate%s." % [selected_gates.size(), "" if selected_gates.size() == 1 else "s"]
				queue_redraw()
				return
			if gates[i]["type_id"] == "EDITOR/COMMENT":
				selected_gate = i
				selected_wire = -1
				dragging_gate = i
				begin_drag_undo()
				drag_offset = pos - gates[i]["position"]
				drag_group_origins.clear()
				for gate_index in selected_gates:
					drag_group_origins[gate_index] = gates[gate_index]["position"]
				status_text = "Selected %d gate%s." % [selected_gates.size(), "" if selected_gates.size() == 1 else "s"]
				queue_redraw()
				return
			if physical_mode and gates[i]["type_id"] == "EDITOR/WHITETILE":
				selected_gate = i
				selected_gates = [i]
				selected_wire = -1
				var edges := white_tile_resize_edges(rect, pos)
				if edges != Vector2i.ZERO:
					resizing_gate = i
					begin_drag_undo()
					resize_start_position = gates[i]["position"]
					resize_start_size = gate_size(gates[i])
					resize_start_mouse = pos
					resize_edges = edges
				else:
					dragging_gate = i
					begin_drag_undo()
					drag_offset = pos - gates[i]["position"]
					drag_group_origins = {i: gates[i]["position"]}
				status_text = "Selected WhiteTile. Drag an edge or corner to resize."
				queue_redraw()
				return
			selected_gate = i
			selected_wire = -1
			dragging_gate = i
			begin_drag_undo()
			drag_offset = pos - gates[i]["position"]
			drag_group_origins.clear()
			for gate_index in selected_gates:
				drag_group_origins[gate_index] = gates[gate_index]["position"]
			status_text = "Selected %d gate%s." % [selected_gates.size(), "" if selected_gates.size() == 1 else "s"]
			queue_redraw()
			return
	if active_tool == "SELECT":
		selected_gates.clear()
		selected_gate = -1
		selected_wire = -1
		selecting = true
		selection_start = canvas_to_screen(pos)
		selection_current = selection_start
		pending_output = {"gate": -1, "port": -1}
		queue_redraw()
		return
	selected_gates.clear()
	selected_gate = -1
	selected_wire = -1
	pending_output = {"gate": -1, "port": -1}

func swap_selected_gates(type_index: int) -> void:
	var definition: Dictionary = GATE_TYPES[type_index]
	var output_port_maps: Dictionary = {}
	var input_port_maps: Dictionary = {}
	for gate_index in selected_gates:
		var used_outputs: Array[int] = []
		var used_inputs: Array[int] = []
		for wire in wires:
			if wire["from_gate"] == gate_index and int(wire["from_port"]) not in used_outputs:
				used_outputs.append(int(wire["from_port"]))
			if wire["to_gate"] == gate_index and int(wire["to_port"]) not in used_inputs:
				used_inputs.append(int(wire["to_port"]))
		used_outputs.sort()
		used_inputs.sort()
		if used_outputs.size() > definition["outputs"].size():
			status_text = "Swap blocked: %s has too few output ports for the connected outputs." % definition["name"]
			return
		if used_inputs.size() > definition["inputs"].size():
			status_text = "Swap blocked: %s has too few input ports for the connected inputs." % definition["name"]
			return
		var output_map: Dictionary = {}
		for index in range(used_outputs.size()):
			output_map[used_outputs[index]] = index
		var input_map: Dictionary = {}
		for index in range(used_inputs.size()):
			input_map[used_inputs[index]] = index
		output_port_maps[gate_index] = output_map
		input_port_maps[gate_index] = input_map
	var swapped_gates: Array[Dictionary] = gates.duplicate(true)
	var swapped_wires: Array[Dictionary] = wires.duplicate(true)
	for gate_index in selected_gates:
		var gate: Dictionary = swapped_gates[gate_index]
		for key in ["gunsaw_part", "gunsaw_data", "gunsaw_input_ids", "gunsaw_output_ids", "gunsaw_external_inputs", "gunsaw_index", "gunsaw_position", "gunsaw_size", "gunsaw_lamp_color"]:
			gate.erase(key)
		gate["type_id"] = definition["id"]
		gate["name"] = definition["name"]
		gate["input_names"] = definition["inputs"].duplicate()
		gate["output_names"] = definition["outputs"].duplicate()
		gate["inputs"] = []
		gate["outputs"] = []
		gate["previous_inputs"] = []
		for _input_name in definition["inputs"]:
			gate["inputs"].append(false)
			gate["previous_inputs"].append(false)
		for _output_name in definition["outputs"]:
			gate["outputs"].append(false)
		gate["memory"] = false
		gate["pulse_pending"] = false
		gate["text"] = "Comment"
		gate["export"] = definition["id"] != "EDITOR/COMMENT"
		if definition["id"] == "MP/IO/LAMP":
			gate["state"] = true
			gate["lamp_color"] = "FFD23F"
		else:
			gate["state"] = false
	for wire_index in range(swapped_wires.size()):
		var original_wire: Dictionary = wires[wire_index]
		var wire: Dictionary = swapped_wires[wire_index]
		var source_gate := int(original_wire["from_gate"])
		var source_port := int(original_wire["from_port"])
		var target_gate := int(original_wire["to_gate"])
		var target_port := int(original_wire["to_port"])
		if output_port_maps.has(source_gate):
			if not output_port_maps[source_gate].has(source_port):
				status_text = "Swap blocked: a connected output port is invalid."
				return
			source_port = int(output_port_maps[source_gate][source_port])
		if input_port_maps.has(target_gate):
			if not input_port_maps[target_gate].has(target_port):
				status_text = "Swap blocked: a connected input port is invalid."
				return
			target_port = int(input_port_maps[target_gate][target_port])
		wire["from_port"] = source_port
		wire["to_port"] = target_port
	if not are_wire_endpoints_valid(swapped_gates, swapped_wires):
		status_text = "Swap blocked: a wire endpoint would be invalid."
		return
	push_undo_state()
	gates.assign(swapped_gates)
	wires.assign(swapped_wires)
	canvas_geometry.dirty = true
	simulation.dirty = true
	status_text = "Swapped %d gate%s to %s. Shift-click toolbar gates to swap again." % [
		selected_gates.size(),
		"" if selected_gates.size() == 1 else "s",
		definition["name"]
	]
	queue_redraw()

func are_wire_endpoints_valid(source_gates: Array, source_wires: Array) -> bool:
	for wire in source_wires:
		var from_gate := int(wire.get("from_gate", -1))
		var to_gate := int(wire.get("to_gate", -1))
		if from_gate < 0 or from_gate >= source_gates.size() or to_gate < 0 or to_gate >= source_gates.size():
			return false
		var source: Dictionary = source_gates[from_gate]
		var target: Dictionary = source_gates[to_gate]
		var from_port := int(wire.get("from_port", -1))
		var to_port := int(wire.get("to_port", -1))
		if from_port < 0 or from_port >= source["outputs"].size() or to_port < 0 or to_port >= target["inputs"].size():
			return false
	return true

func finish_box_selection() -> void:
	var selection_rect := Rect2(selection_start, selection_current - selection_start).abs()
	selected_gates.clear()
	for i in range(gates.size()):
		if gates[i]["type_id"] == "EDITOR/WHITETILE" and not physical_mode:
			continue
		var gate_rect := Rect2(canvas_to_screen(gates[i]["position"]), gate_size(gates[i]) * canvas_zoom)
		if selection_rect.intersects(gate_rect):
			selected_gates.append(i)
	if selected_gates.is_empty():
		selected_gate = -1
		status_text = "No gates selected."
	else:
		selected_gate = selected_gates[0]
		status_text = "Selected %d gate%s." % [selected_gates.size(), "" if selected_gates.size() == 1 else "s"]
	selected_wire = -1
	queue_redraw()

func handle_delete_press(pos: Vector2) -> void:
	if pos.y < toolbar_height:
		return
	pos = screen_to_canvas(pos)
	var port := find_port(pos)
	var wire_index := find_wire(pos) if port["gate"] < 0 else -1
	if wire_index >= 0:
		selected_gates.clear()
		selected_gate = -1
		selected_wire = wire_index
	else:
		var gate_index: int = port["gate"] if port["gate"] >= 0 else find_gate(pos)
		selected_gates.clear()
		selected_gate = gate_index
		selected_wire = -1
		if gate_index >= 0:
			selected_gates = [gate_index]
	delete_selection()

func find_gate(pos: Vector2) -> int:
	for i in range(gates.size() - 1, -1, -1):
		if gates[i]["type_id"] == "EDITOR/WHITETILE" and not physical_mode:
			continue
		if physical_mode and not is_physical_gate(gates[i]):
			continue
		if Rect2(gates[i]["position"], gate_size(gates[i])).has_point(pos):
			return i
	return -1

func find_wire(pos: Vector2) -> int:
	if not wires_visible:
		return -1
	if physical_mode:
		return -1
	canvas_geometry.update(gates, wires, NODE_SIZE)
	for i in range(wires.size() - 1, -1, -1):
		if not canvas_geometry.wire_bounds[i].grow(9.0).has_point(pos):
			continue
		var path: PackedVector2Array = canvas_geometry.wire_paths[i]
		for segment in range(path.size() - 1):
			if Geometry2D.get_closest_point_to_segment(pos, path[segment], path[segment + 1]).distance_to(pos) <= 9.0:
				return i
	return -1

func find_port(pos: Vector2) -> Dictionary:
	canvas_geometry.update(gates, wires, NODE_SIZE)
	for i in range(gates.size() - 1, -1, -1):
		if not canvas_geometry.gate_bounds[i].grow(12.0).has_point(pos):
			continue
		var gate: Dictionary = gates[i]
		if physical_mode and not is_physical_gate(gate):
			continue
		for p in range(gate["inputs"].size()):
			if port_position(i, true, p).distance_to(pos) <= 12:
				return {"gate": i, "port": p, "input": true}
		for p in range(gate["outputs"].size()):
			if port_position(i, false, p).distance_to(pos) <= 12:
				return {"gate": i, "port": p, "input": false}
	return {"gate": -1}

func add_gate(type_index: int) -> void:
	var definition: Dictionary = GATE_TYPES[type_index]
	if physical_mode:
		status_text = "Physical mode does not allow placing gates."
		return
	if foundry_mode:
		if definition["id"] in ["EDITOR/COMMENT", "EDITOR/CLOCK_IN", "EDITOR/CLOCK_OUT", "EDITOR/WHITETILE"]:
			status_text = "%s is not available in Foundry." % definition["name"]
			return
		if definition["id"] in ["MP/IO/BUTTON", "MP/IO/LAMP"] and foundry_layout_mode != "Expand":
			status_text = "BUTTON and LAMP are available only in Expand mode."
			return
	var viewport_size := get_viewport_rect().size
	var view_center := Vector2(viewport_size.x * 0.5, toolbar_height + (viewport_size.y - toolbar_height) * 0.5)
	var spawn_position := snap_position(screen_to_canvas(view_center) - NODE_SIZE * 0.5)
	var gate := {
		"id": next_id,
		"type_id": definition["id"],
		"name": definition["name"],
		"position": spawn_position,
		"input_names": definition["inputs"].duplicate(),
		"output_names": definition["outputs"].duplicate(),
		"inputs": [],
		"outputs": [],
		"memory": false,
		"state": true,
		"lamp_color": "FFD23F",
		"pulse_pending": false,
		"text": "Comment",
		"export": definition["id"] not in ["EDITOR/COMMENT", "EDITOR/CLOCK_IN", "EDITOR/CLOCK_OUT"],
		"previous_inputs": []
	}
	push_undo_state()
	next_id += 1
	for _name in definition["inputs"]:
		gate["inputs"].append(false)
		gate["previous_inputs"].append(false)
	for _name in definition["outputs"]:
		gate["outputs"].append(false)
	gates.append(gate)
	clamp_canvas_offset()
	selected_gates = [gates.size() - 1]
	selected_gate = gates.size() - 1
	selected_wire = -1
	active_tool = "SELECT"
	status_text = "Placed %s. Double-click to rename." % definition["name"] if foundry_mode and definition["id"] in ["EDITOR/COMPONENT_INPUT", "EDITOR/COMPONENT_OUTPUT"] else "Placed %s." % definition["name"]
	queue_redraw()

func add_white_tile() -> void:
	var viewport_size := get_viewport_rect().size
	var view_center := Vector2(viewport_size.x * 0.5, toolbar_height + (viewport_size.y - toolbar_height) * 0.5)
	var tile := {
		"id": next_id,
		"type_id": "EDITOR/WHITETILE",
		"name": "WHITE TILE",
		"position": snap_position(screen_to_canvas(view_center) - Vector2(5, 1) * PHYSICAL_UNIT_SIZE),
		"size": Vector2(10, 2) * PHYSICAL_UNIT_SIZE,
		"input_names": [],
		"output_names": [],
		"inputs": [],
		"outputs": [],
		"memory": false,
		"state": false,
		"pulse_pending": false,
		"text": "",
		"export": true,
		"previous_inputs": []
	}
	push_undo_state()
	next_id += 1
	gates.append(tile)
	selected_gates = [gates.size() - 1]
	selected_gate = gates.size() - 1
	selected_wire = -1
	status_text = "Placed WhiteTile."
	queue_redraw()

func delete_selection() -> void:
	if not selected_gates.is_empty():
		push_undo_state()
		var removed_gates := selected_gates.duplicate()
		removed_gates.sort()
		for i in range(wires.size() - 1, -1, -1):
			var wire := wires[i]
			if wire["from_gate"] in removed_gates or wire["to_gate"] in removed_gates:
				wires.remove_at(i)
				continue
			var removed_before_from := 0
			var removed_before_to := 0
			for removed_gate in removed_gates:
				if removed_gate < wire["from_gate"]:
					removed_before_from += 1
				if removed_gate < wire["to_gate"]:
					removed_before_to += 1
			wire["from_gate"] -= removed_before_from
			wire["to_gate"] -= removed_before_to
		for i in range(removed_gates.size() - 1, -1, -1):
			gates.remove_at(removed_gates[i])
		selected_gate = -1
		selected_gates.clear()
		selected_wire = -1
		dragging_gate = -1
		drag_group_origins.clear()
		status_text = "Selected components deleted."
	elif selected_wire >= 0 and selected_wire < wires.size():
		push_undo_state()
		wires.remove_at(selected_wire)
		selected_wire = -1
		status_text = "Wire deleted."
	else:
		return
	pending_output = {"gate": -1, "port": -1}
	queue_redraw()

func duplicate_selection(include_external_outputs := false) -> void:
	if selected_gates.is_empty():
		status_text = "Select one or more gates to duplicate."
		return
	var previous_next_id := next_id
	var undo_snapshot := create_undo_snapshot()
	var source_gates := selected_gates.duplicate()
	source_gates.sort()
	var gate_map: Dictionary = {}
	var duplicated_gates: Array[int] = []
	var duplicate_offset := Vector2(GRID_SIZE * 2.0, GRID_SIZE * 2.0)
	for source_index in source_gates:
		var duplicate_gate: Dictionary = gates[source_index].duplicate(true)
		duplicate_gate["id"] = next_id
		duplicate_gate.erase("gunsaw_output_ids")
		duplicate_gate.erase("gunsaw_index")
		if duplicate_gate.has("gunsaw_part") and duplicate_gate["gunsaw_part"]["path"] == "MP/CustomProp":
			var payload: Dictionary = JSON.parse_string(duplicate_gate["gunsaw_part"]["team"])
			payload["uid"] = "editor-%d" % next_id
			duplicate_gate["gunsaw_part"]["team"] = JSON.stringify(payload)
		duplicate_gate["position"] = duplicate_gate["position"] + duplicate_offset
		next_id += 1
		gate_map[source_index] = gates.size()
		gates.append(duplicate_gate)
		duplicated_gates.append(gates.size() - 1)
	var duplicated_wire_count := 0
	var source_wires: Array = wires.duplicate(true)
	var duplicated_wires: Array = []
	for wire in source_wires:
		var from_gate := resolve_gate_index(wire["from_gate"])
		var to_gate := resolve_gate_index(wire["to_gate"])
		var duplicate_from_gate: int = int(gate_map.get(from_gate, -1))
		var duplicate_to_gate: int = int(gate_map.get(to_gate, -1))
		if duplicate_from_gate < 0 or (duplicate_to_gate < 0 and not include_external_outputs):
			continue
		var duplicate_wire: Dictionary = wire.duplicate(true)
		duplicate_wire["from_gate"] = duplicate_from_gate
		duplicate_wire["to_gate"] = to_gate if duplicate_to_gate < 0 else duplicate_to_gate
		duplicated_wires.append(duplicate_wire)
		duplicated_wire_count += 1
	var proposed_wires: Array = wires.duplicate(true)
	proposed_wires.append_array(duplicated_wires)
	if has_invalid_connection_topology(proposed_wires):
		for _i in range(duplicated_gates.size()):
			gates.pop_back()
		next_id = previous_next_id
		status_text = "Duplication blocked: it would create multiple outputs connected to multiple inputs."
		queue_redraw()
		return
	push_undo_snapshot(undo_snapshot)
	wires.append_array(duplicated_wires)
	selected_gates = duplicated_gates
	selected_gate = duplicated_gates[0]
	selected_wire = -1
	var connection_label := "connection" if not include_external_outputs else "connection/output"
	status_text = "Duplicated %d gate%s and %d %s%s." % [
		duplicated_gates.size(),
		"" if duplicated_gates.size() == 1 else "s",
		duplicated_wire_count,
		connection_label,
		"" if duplicated_wire_count == 1 else "s"
	]
	queue_redraw()

func resolve_gate_index(endpoint: Variant) -> int:
	var endpoint_index := int(endpoint)
	if endpoint_index >= 0 and endpoint_index < gates.size():
		return endpoint_index
	for gate_index in range(gates.size()):
		if int(gates[gate_index].get("id", -1)) == endpoint_index:
			return gate_index
	return -1

func connect_wire(from_gate: int, from_port: int, to_gate: int, to_port: int) -> void:
	if physical_mode:
		pending_output = {"gate": -1, "port": -1}
		status_text = "Physical mode does not support wires."
		return
	if gates[from_gate]["type_id"] == "EDITOR/CLOCK_OUT" and gates[to_gate]["type_id"] == "EDITOR/CLOCK_IN":
		pending_output = {"gate": -1, "port": -1}
		status_text = "Connect a regular gate output to CLOCK IN, not CLOCK OUT."
		return
	if creates_multiple_output_input_connection(from_gate, from_port, to_gate, to_port):
		pending_output = {"gate": -1, "port": -1}
		status_text = "Connection blocked: multiple outputs to multiple inputs cannot be exported."
		queue_redraw()
		return
	push_undo_state()
	wires.append({"from_gate": from_gate, "from_port": from_port, "to_gate": to_gate, "to_port": to_port})
	pending_output = {"gate": -1, "port": -1}
	status_text = "Connected. Multiple wires may share this input."
	queue_redraw()

func creates_multiple_output_input_connection(from_gate: int, from_port: int, to_gate: int, to_port: int) -> bool:
	var candidate_wires: Array = wires.duplicate(true)
	candidate_wires.append({"from_gate": from_gate, "from_port": from_port, "to_gate": to_gate, "to_port": to_port})
	return has_invalid_connection_topology(candidate_wires)

func has_invalid_connection_topology(source_wires: Array) -> bool:
	var adjacency: Dictionary = {}
	var topology_wires := source_wires
	var topology_gates: Array = gates
	if has_custom_components():
		var flattened := expand_custom_components(source_wires)
		topology_wires = flattened["wires"]
		topology_gates = flattened["gates"]
	for wire in get_expanded_wires(topology_wires, true, topology_gates):
		add_connection_edge(adjacency, "o:%d:%d" % [wire["from_gate"], wire["from_port"]], "i:%d:%d" % [wire["to_gate"], wire["to_port"]])
	var visited: Dictionary = {}
	for start_node in adjacency:
		if visited.has(start_node):
			continue
		var pending: Array[String] = [start_node]
		var output_count := 0
		var input_count := 0
		while not pending.is_empty():
			var node: String = pending.pop_front()
			if visited.has(node):
				continue
			visited[node] = true
			if node.begins_with("o:"):
				output_count += 1
			else:
				input_count += 1
			for neighbor in adjacency[node]:
				if not visited.has(neighbor):
					pending.append(neighbor)
		if output_count > 1 and input_count > 1:
			return true
	return false

func add_connection_edge(adjacency: Dictionary, output_node: String, input_node: String) -> void:
	if not adjacency.has(output_node):
		adjacency[output_node] = []
	if not adjacency.has(input_node):
		adjacency[input_node] = []
	adjacency[output_node].append(input_node)
	adjacency[input_node].append(output_node)

func get_expanded_wires(source_wires: Array, include_clock_inputs := true, source_gates: Array = []) -> Array:
	if source_gates.is_empty():
		source_gates = gates
	var expanded: Array = []
	var clock_destinations: Array[Dictionary] = []
	for wire in source_wires:
		var from_gate := int(wire["from_gate"])
		var to_gate := int(wire["to_gate"])
		if source_gates[from_gate]["type_id"] == "EDITOR/CLOCK_OUT":
			clock_destinations.append(wire)
			continue
		if not include_clock_inputs and source_gates[to_gate]["type_id"] == "EDITOR/CLOCK_IN":
			continue
		expanded.append(wire.duplicate(true))
	for destination in clock_destinations:
		for source in source_wires:
			var source_target := int(source["to_gate"])
			if source_gates[source_target]["type_id"] != "EDITOR/CLOCK_IN":
				continue
			expanded.append({
				"from_gate": source["from_gate"],
				"from_port": source["from_port"],
				"to_gate": destination["to_gate"],
				"to_port": destination["to_port"]
			})
	return expanded

func reset_simulation() -> void:
	gate_properties.cancel()
	running = false
	run_button.button_pressed = false
	update_run_button()
	tick = 0
	ticks_in_tps_window = 0
	ticks_per_second = 0.0
	tps_window_start_ms = Time.get_ticks_msec()
	button_candidate = -1
	simulation_accumulator = 0.0
	simulation.dirty = true
	LogicSimulator.reset(gates)
	for gate in gates:
		if gate["type_id"] == "EDITOR/CUSTOM":
			LogicSimulator.reset(gate["custom_gates"])
	status_text = "Simulation reset."
	queue_redraw()

func simulate_tick() -> void:
	if simulation.dirty or compiled_board_gate_count != gates.size() or compiled_board_wire_count != wires.size():
		compiled_custom_components = has_custom_components()
		compiled_board_gate_count = gates.size()
		compiled_board_wire_count = wires.size()
	if compiled_custom_components:
		simulate_custom_tick()
	else:
		if simulation.dirty or simulation.gate_count != gates.size() or simulation.wire_count != wires.size():
			simulation.compile(gates, get_expanded_wires(wires), wires.size())
		simulation.advance()
	tick += 1
	ticks_in_tps_window += 1
	status_text = "Advanced one logic tick (20 ms)."
	queue_redraw()

func simulate_custom_tick() -> void:
	var flattened := expand_custom_components()
	var simulation_gates: Array = flattened["gates"]
	var simulation_wires: Array = get_expanded_wires(flattened["wires"], true, simulation_gates)
	if simulation.dirty or simulation.gate_count != simulation_gates.size() or simulation.wire_count != simulation_wires.size():
		simulation.compile(simulation_gates, simulation_wires, simulation_wires.size())
	for gate_index in range(gates.size()):
		var flat_index: int = flattened["gate_map"][gate_index]
		if flat_index >= 0:
			simulation._gates[flat_index]["pulse_pending"] = gates[gate_index].get("pulse_pending", false)
		elif gates[gate_index]["type_id"] == "EDITOR/CUSTOM":
			var child_map: Array = flattened["instances"][gate_index]["children"]
			var children: Array = gates[gate_index]["custom_gates"]
			for child_index in range(child_map.size()):
				if child_map[child_index] >= 0:
					simulation._gates[child_map[child_index]]["pulse_pending"] = children[child_index].get("pulse_pending", false)
	simulation.advance()
	simulation.sync_all()
	for gate_index in range(gates.size()):
		var flat_index: int = flattened["gate_map"][gate_index]
		if flat_index >= 0:
			copy_simulation_state(simulation._gates[flat_index], gates[gate_index])
		elif gates[gate_index]["type_id"] == "EDITOR/CUSTOM":
			var child_map: Array = flattened["instances"][gate_index]["children"]
			var children: Array = gates[gate_index]["custom_gates"]
			for child_index in range(child_map.size()):
				if child_map[child_index] >= 0:
					copy_simulation_state(simulation._gates[child_map[child_index]], children[child_index])
	for gate_index in range(gates.size()):
		if gates[gate_index]["type_id"] == "EDITOR/CUSTOM":
			for port in range(gates[gate_index]["inputs"].size()):
				var high := false
				for wire in wires:
					if wire["to_gate"] == gate_index and wire["to_port"] == port:
						high = high or gates[wire["from_gate"]]["outputs"][wire["from_port"]]
				gates[gate_index]["inputs"][port] = high
			var custom_ports: Array = flattened["custom_outputs"].get(gate_index, [])
			for port in range(gates[gate_index]["outputs"].size()):
				var sources: Array = custom_ports[port]
				var high := false
				for source in sources:
					high = high or simulation._gates[source["gate"]]["outputs"][source["port"]]
				var pass_ports: Array = flattened["custom_pass"].get(gate_index, [])[port]
				for input_port in pass_ports:
					high = high or gates[gate_index]["inputs"][input_port]
				gates[gate_index]["outputs"][port] = high

func copy_simulation_state(source: Dictionary, target: Dictionary) -> void:
	for key in ["inputs", "outputs", "previous_inputs", "memory", "state", "pulse_pending"]:
		if source.has(key) and target.has(key):
			target[key] = source[key].duplicate(true) if source[key] is Array else source[key]
	for key in ["simulation_clock_elapsed", "simulation_clock_high", "simulation_delay_remaining", "simulation_cycle_remaining", "simulation_button_used"]:
		if source.has(key):
			target[key] = source[key]
		else:
			target.erase(key)

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

func normalize_custom_component_geometry(gate: Dictionary) -> void:
	if gate.get("type_id", "") != "EDITOR/CUSTOM":
		return
	var child_gates: Array = gate.get("custom_gates", [])
	for child_gate in child_gates:
		if not child_gate is Dictionary:
			continue
		if child_gate.has("position"):
			child_gate["position"] = normalized_position(child_gate["position"])
		if child_gate.get("type_id", "") == "EDITOR/WHITETILE" and child_gate.has("size"):
			child_gate["size"] = normalized_position(child_gate["size"])
		normalize_custom_component_geometry(child_gate)
	var layout: String = str(gate.get("custom_layout_mode", "Inline"))
	if layout != "Expand" or child_gates.is_empty():
		if gate.has("custom_origin"):
			gate["custom_origin"] = normalized_position(gate["custom_origin"])
		if gate.has("custom_size"):
			gate["custom_size"] = normalized_position(gate["custom_size"])
		return
	var min_position := Vector2(INF, INF)
	var max_position := Vector2(-INF, -INF)
	for child_gate in child_gates:
		var child_position: Vector2 = normalized_position(child_gate.get("position", Vector2.ZERO))
		min_position = min_position.min(child_position)
		max_position = max_position.max(child_position + GateProperties.node_size(child_gate, NODE_SIZE))
	gate["custom_origin"] = min_position
	gate["custom_size"] = max_position - min_position + Vector2(32, 64)

func serialize_custom_component_geometry(gate: Dictionary) -> void:
	if gate.get("type_id", "") != "EDITOR/CUSTOM":
		return
	var custom_origin: Vector2 = normalized_position(gate.get("custom_origin", Vector2.ZERO))
	var custom_size: Vector2 = normalized_position(gate.get("custom_size", NODE_SIZE))
	gate["custom_origin"] = {"x": custom_origin.x, "y": custom_origin.y}
	gate["custom_size"] = {"x": custom_size.x, "y": custom_size.y}
	var child_gates: Array = gate.get("custom_gates", [])
	for child_gate in child_gates:
		if not child_gate is Dictionary:
			continue
		var child_position: Vector2 = normalized_position(child_gate.get("position", Vector2.ZERO))
		child_gate["position"] = {"x": child_position.x, "y": child_position.y}
		if child_gate.get("type_id", "") == "EDITOR/WHITETILE":
			var child_size: Vector2 = GateProperties.node_size(child_gate, NODE_SIZE)
			child_gate["size"] = {"x": child_size.x, "y": child_size.y}
		serialize_custom_component_geometry(child_gate)

func expand_custom_components(source_wires: Array = []) -> Dictionary:
	if source_wires.is_empty():
		source_wires = wires
	var expanded_gates: Array[Dictionary] = []
	var expanded_wires: Array[Dictionary] = []
	var gate_map: Array[int] = []
	var instance_maps: Dictionary = {}
	var custom_outputs: Dictionary = {}
	var custom_pass: Dictionary = {}
	for gate_index in range(gates.size()):
		var gate: Dictionary = gates[gate_index]
		if gate["type_id"] != "EDITOR/CUSTOM":
			gate_map.append(expanded_gates.size())
			expanded_gates.append(gate.duplicate(true))
			continue
		gate_map.append(-1)
		var child_gates: Array = gate.get("custom_gates", [])
		var child_wires: Array = gate.get("custom_wires", [])
		var child_map: Array[int] = []
		for child_index in range(child_gates.size()):
			var child: Dictionary = child_gates[child_index]
			if child.get("type_id", "") in ["EDITOR/COMPONENT_INPUT", "EDITOR/COMPONENT_OUTPUT"]:
				child_map.append(-1)
				continue
			var copy: Dictionary = child.duplicate(true)
			var child_position := normalized_position(copy.get("position", Vector2.ZERO))
			if gate.get("custom_layout_mode", "Inline") == "Inline":
				copy["position"] = gate["position"]
			else:
				copy["position"] = gate["position"] + child_position - normalized_position(gate.get("custom_origin", Vector2.ZERO))
			child_map.append(expanded_gates.size())
			expanded_gates.append(copy)
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
		for child_wire in child_wires:
			var from_index := int(child_wire["from_gate"])
			var to_index := int(child_wire["to_gate"])
			var from_type: String = child_gates[from_index].get("type_id", "")
			var to_type: String = child_gates[to_index].get("type_id", "")
			if from_type == "EDITOR/COMPONENT_INPUT":
				var parent_port := find_custom_port(inputs, from_index)
				if parent_port >= 0:
					if to_type == "EDITOR/COMPONENT_OUTPUT":
						var output_port := find_custom_port(outputs, to_index)
						if output_port >= 0:
							pass_through[output_port].append(parent_port)
					elif child_map[to_index] >= 0:
						input_targets[parent_port].append({"gate": child_map[to_index], "port": int(child_wire["to_port"])})
			elif to_type == "EDITOR/COMPONENT_OUTPUT":
				var parent_port := find_custom_port(outputs, to_index)
				if parent_port >= 0 and child_map[from_index] >= 0:
					output_sources[parent_port].append({"gate": child_map[from_index], "port": int(child_wire["from_port"])})
			elif child_map[from_index] >= 0 and child_map[to_index] >= 0:
				expanded_wires.append({
					"from_gate": child_map[from_index], "from_port": int(child_wire["from_port"]),
					"to_gate": child_map[to_index], "to_port": int(child_wire["to_port"])
				})
		instance_maps[gate_index] = {"inputs": input_targets, "outputs": output_sources, "pass": pass_through, "children": child_map}
		custom_outputs[gate_index] = output_sources
		custom_pass[gate_index] = pass_through
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
	return {"gates": expanded_gates, "wires": expanded_wires, "gate_map": gate_map, "instances": instance_maps, "custom_outputs": custom_outputs, "custom_pass": custom_pass}

func find_custom_port(ports: Array, child_gate_index: int) -> int:
	for port_index in range(ports.size()):
		if int(ports[port_index]["gate"]) == child_gate_index:
			return port_index
	return -1

func resolve_custom_output_sources(instance_gate: int, output_port: int, source_wires: Array, gate_map: Array, instance_maps: Dictionary, depth: int) -> Array:
	var resolved: Array = []
	if depth > gates.size() or not instance_maps.has(instance_gate):
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

func has_custom_components() -> bool:
	for gate in gates:
		if gate["type_id"] == "EDITOR/CUSTOM":
			return true
	return false

func update_ticks_per_second() -> void:
	var now_ms := Time.get_ticks_msec()
	var elapsed_ms := now_ms - tps_window_start_ms
	if elapsed_ms < 1000:
		return
	ticks_per_second = float(ticks_in_tps_window) * 1000.0 / float(elapsed_ms)
	ticks_in_tps_window = 0
	tps_window_start_ms = now_ms

func clock_bus_output_state() -> bool:
	for wire in wires:
		if gates[wire["to_gate"]]["type_id"] != "EDITOR/CLOCK_IN":
			continue
		if gates[wire["from_gate"]]["outputs"][wire["from_port"]]:
			return true
	return false

func snap_position(pos: Vector2) -> Vector2:
	return Vector2(round(pos.x / GRID_SIZE) * GRID_SIZE, round(pos.y / GRID_SIZE) * GRID_SIZE)

func clamp_canvas_offset() -> void:
	return

func create_undo_snapshot() -> Dictionary:
	simulation.sync_all()
	return {
		"gunsaw_source_level": gunsaw_source_level.duplicate(true),
		"gates": gates.duplicate(true),
		"wires": wires.duplicate(true),
		"tick": tick,
		"next_id": next_id,
		"canvas_offset": canvas_offset,
		"canvas_zoom": canvas_zoom,
		"physical_mode": physical_mode,
		"selected_gates": selected_gates.duplicate(),
		"selected_gate": selected_gate,
		"selected_wire": selected_wire,
		"pending_output": pending_output.duplicate()
	}

func push_undo_state() -> void:
	push_undo_snapshot(create_undo_snapshot())

func push_undo_snapshot(snapshot: Dictionary, invalidate: bool = true) -> void:
	if invalidate:
		simulation.dirty = true
		canvas_geometry.dirty = true
	if snapshot.is_empty():
		return
	undo_history.append(snapshot.duplicate())
	if undo_history.size() > MAX_UNDO_STEPS:
		undo_history.pop_front()

func begin_drag_undo() -> void:
	var transforms: Array = []
	for index in selected_gates:
		var transform := {"index": index, "position": gates[index]["position"]}
		if gates[index].has("size"):
			transform["size"] = gates[index]["size"]
		transforms.append(transform)
	drag_undo_snapshot = {"gate_transforms": transforms}
	drag_undo_recorded = false

func undo_last_action() -> void:
	gate_properties.cancel()
	if undo_history.is_empty():
		status_text = "Nothing to undo."
		return
	var snapshot: Dictionary = undo_history.pop_back()
	if snapshot.has("gate_transforms"):
		for transform in snapshot["gate_transforms"]:
			var gate: Dictionary = gates[transform["index"]]
			gate["position"] = transform["position"]
			if transform.has("size"):
				gate["size"] = transform["size"]
		canvas_geometry.dirty = true
		canvas_geometry.moving = false
		dragging_gate = -1
		resizing_gate = -1
		drag_group_origins.clear()
		drag_undo_snapshot.clear()
		drag_undo_recorded = false
		status_text = "Undid last action."
		queue_redraw()
		return
	simulation.dirty = true
	canvas_geometry.dirty = true
	gunsaw_source_level = snapshot.get("gunsaw_source_level", {}).duplicate(true)
	gates.assign(snapshot["gates"])
	wires.assign(snapshot["wires"])
	tick = snapshot["tick"]
	next_id = snapshot["next_id"]
	canvas_offset = snapshot["canvas_offset"]
	canvas_zoom = snapshot.get("canvas_zoom", canvas_zoom)
	if physical_mode != snapshot.get("physical_mode", physical_mode):
		physical_mode = snapshot["physical_mode"]
		physical_button.button_pressed = physical_mode
		rebuild_gate_toolbar()
	selected_gates.clear()
	for gate_index in snapshot["selected_gates"]:
		selected_gates.append(gate_index)
	selected_gate = snapshot["selected_gate"]
	selected_wire = snapshot["selected_wire"]
	pending_output = snapshot["pending_output"].duplicate()
	dragging_gate = -1
	resizing_gate = -1
	drag_group_origins.clear()
	drag_undo_snapshot.clear()
	drag_undo_recorded = false
	selecting = false
	status_text = "Undid last action."
	queue_redraw()

func save_editor(slot: int = current_save_slot) -> void:
	gate_properties.commit()
	current_save_slot = clampi(slot, 1, SAVE_SLOT_COUNT)
	var save_path := save_slot_path(current_save_slot)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		status_text = "Save failed: %s." % error_string(FileAccess.get_open_error())
		return
	var saved_gates: Array = gates.duplicate(true)
	for gate in saved_gates:
		var saved_position: Vector2 = gate["position"]
		gate["position"] = {"x": saved_position.x, "y": saved_position.y}
		var import_state := {}
		for key in ["gunsaw_part", "gunsaw_data"]:
			if gate.has(key):
				import_state[key] = gate[key]
		if not import_state.is_empty():
			gate["gunsaw_import_state"] = Marshalls.raw_to_base64(var_to_bytes(import_state))
		var inputs: Array = []
		var outputs: Array = []
		var previous_inputs: Array = []
		for _input_name in gate["input_names"]:
			inputs.append(false)
			previous_inputs.append(false)
		for _output_name in gate["output_names"]:
			outputs.append(false)
		gate["inputs"] = inputs
		gate["outputs"] = outputs
		gate["previous_inputs"] = previous_inputs
		gate["memory"] = false
		if gate["type_id"] == "MP/IO/LAMP":
			gate["state"] = true
		if gate["type_id"] == "EDITOR/WHITETILE":
			var tile_size: Vector2 = gate_size(gate)
			gate["size"] = {"x": tile_size.x, "y": tile_size.y}
		gate["pulse_pending"] = false
		if gate["type_id"] == "EDITOR/CUSTOM":
			serialize_custom_component_geometry(gate)
			LogicSimulator.reset(gate["custom_gates"])
	LogicSimulator.reset(saved_gates)
	var document := {
		"format": 1,
		"tick": tick,
		"next_id": next_id,
		"canvas_offset": [canvas_offset.x, canvas_offset.y],
		"gunsaw_source_level": gunsaw_source_level,
		"gates": saved_gates,
		"wires": wires
	}
	file.store_string(GunsawLevelImporter.stringify_json(document, "\t"))
	file.close()
	status_text = "Editor saved to Slot %d (%s)." % [current_save_slot, save_path]

func load_editor(slot: int = current_save_slot) -> void:
	gate_properties.cancel()
	current_save_slot = clampi(slot, 1, SAVE_SLOT_COUNT)
	var save_path := save_slot_path(current_save_slot)
	if not FileAccess.file_exists(save_path):
		status_text = "No saved editor project found."
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		status_text = "Load failed: %s." % error_string(FileAccess.get_open_error())
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or parsed.get("format", 0) != 1:
		status_text = "Load failed: unsupported editor project."
		return
	if not parsed.has("gates") or not parsed.has("wires") or not parsed.has("canvas_offset"):
		status_text = "Load failed: incomplete editor project."
		return
	if not parsed["gates"] is Array or not parsed["wires"] is Array:
		status_text = "Load failed: invalid component or wire data."
		return
	push_undo_state()
	gates.clear()
	for loaded_gate in parsed["gates"]:
		if not loaded_gate is Dictionary:
			status_text = "Load failed: invalid component data."
			return
		if loaded_gate.has("gunsaw_import_state"):
			var import_state = bytes_to_var(Marshalls.base64_to_raw(loaded_gate["gunsaw_import_state"]))
			if not import_state is Dictionary:
				status_text = "Load failed: invalid imported component state."
				return
			for key in ["gunsaw_part", "gunsaw_data"]:
				if import_state.has(key):
					loaded_gate[key] = import_state[key]
			loaded_gate.erase("gunsaw_import_state")
		if not loaded_gate.has("position"):
			status_text = "Load failed: component has no position."
			return
		var loaded_position = loaded_gate["position"]
		if loaded_position is Dictionary and loaded_position.has("x") and loaded_position.has("y"):
			loaded_gate["position"] = Vector2(float(loaded_position["x"]), float(loaded_position["y"]))
		elif loaded_position is Array and loaded_position.size() == 2:
			loaded_gate["position"] = Vector2(float(loaded_position[0]), float(loaded_position[1]))
		elif loaded_position is String:
			var coordinates: PackedStringArray = loaded_position.trim_prefix("(").trim_suffix(")").split(",")
			if coordinates.size() != 2:
				status_text = "Load failed: invalid component position."
				return
			loaded_gate["position"] = Vector2(float(coordinates[0]), float(coordinates[1]))
		else:
			status_text = "Load failed: invalid component position."
			return
		normalize_custom_component_geometry(loaded_gate)
		if loaded_gate["type_id"] == "EDITOR/WHITETILE":
			var loaded_size = loaded_gate.get("size", {"x": 320.0, "y": 64.0})
			if loaded_size is Dictionary and loaded_size.has("x") and loaded_size.has("y"):
				loaded_gate["size"] = Vector2(float(loaded_size["x"]), float(loaded_size["y"]))
			elif loaded_size is Array and loaded_size.size() == 2:
				loaded_gate["size"] = Vector2(float(loaded_size[0]), float(loaded_size[1]))
			else:
				loaded_gate["size"] = Vector2(10, 2) * PHYSICAL_UNIT_SIZE
		if loaded_gate["type_id"] == "MP/IO/LAMP":
			loaded_gate["state"] = true
			loaded_gate["lamp_color"] = str(loaded_gate.get("lamp_color", "FFD23F")).trim_prefix("#")
		loaded_gate["memory"] = int(loaded_gate.get("gunsaw_data", {}).get("initialQ", 0)) != 0
		var loaded_outputs: Array = []
		var loaded_inputs: Array = []
		var loaded_previous_inputs: Array = []
		for _input_name in loaded_gate["input_names"]:
			loaded_inputs.append(false)
			loaded_previous_inputs.append(false)
		for _output_name in loaded_gate["output_names"]:
			loaded_outputs.append(false)
		loaded_gate["inputs"] = loaded_inputs
		loaded_gate["outputs"] = loaded_outputs
		loaded_gate["previous_inputs"] = loaded_previous_inputs
		loaded_gate["pulse_pending"] = false
		gates.append(loaded_gate)
	wires.clear()
	for loaded_wire in parsed["wires"]:
		if not loaded_wire is Dictionary:
			status_text = "Load failed: invalid wire data."
			return
		wires.append(loaded_wire)
	LogicSimulator.reset(gates)
	tick = int(parsed.get("tick", 0))
	next_id = int(parsed.get("next_id", 1))
	var saved_offset: Array = parsed["canvas_offset"]
	if saved_offset.size() != 2:
		status_text = "Load failed: invalid canvas position."
		return
	canvas_offset = Vector2(float(saved_offset[0]), float(saved_offset[1]))
	selected_gates.clear()
	selected_gate = -1
	selected_wire = -1
	dragging_gate = -1
	pending_output = {"gate": -1, "port": -1}
	clamp_canvas_offset()
	gunsaw_source_level = parsed.get("gunsaw_source_level", {}).duplicate(true)
	var source_document: Dictionary = gunsaw_source_level.get("_gunsaw_document", {})
	if not source_document.is_empty():
		var preserved: Array = []
		for index in source_document["preserved_indices"]:
			preserved.append(JSON.parse_string(GunsawLevelImporter.LevelDocument.normalize_json(source_document["parts"][int(index)])))
		gunsaw_source_level["parts"] = preserved
	status_text = "Editor loaded from Slot %d (%s)." % [current_save_slot, save_path]
	queue_redraw()

func save_slot_path(slot: int) -> String:
	if slot == 1:
		return SAVE_PATH
	return "user://g-logical-editor-slot-%d.json" % slot

func export_gunsaw() -> void:
	if foundry_mode:
		status_text = "Gunsaw export is unavailable in Foundry mode. Save the component to use it in Editor mode."
		return
	gate_properties.commit()
	if has_custom_components():
		var flattened := expand_custom_components()
		var export_gates: Array[Dictionary] = flattened["gates"]
		var export_wires_data: Array[Dictionary] = flattened["wires"]
		if has_invalid_connection_topology(wires):
			status_text = "Export blocked: custom components create a multiple-output/multiple-input connection."
			return
		var saved_gates := gates
		var saved_wires := wires
		gates = export_gates
		wires = export_wires_data
		export_gunsaw()
		gates = saved_gates
		wires = saved_wires
		simulation.dirty = true
		queue_redraw()
		return
	var has_clock_out_connections := false
	var has_invalid_clock_source := false
	var clock_sources: Dictionary = {}
	for wire in wires:
		if gates[wire["from_gate"]]["type_id"] == "EDITOR/CLOCK_OUT":
			has_clock_out_connections = true
		if gates[wire["to_gate"]]["type_id"] == "EDITOR/CLOCK_IN":
			if gates[wire["from_gate"]]["type_id"] in ["EDITOR/CLOCK_IN", "EDITOR/CLOCK_OUT"]:
				has_invalid_clock_source = true
			else:
				var source_key := "%d:%d" % [wire["from_gate"], wire["from_port"]]
				clock_sources[source_key] = true
	if has_clock_out_connections and (has_invalid_clock_source or clock_sources.size() != 1):
		status_text = "Export blocked: connect exactly one regular gate output to CLOCK IN before using CLOCK OUT."
		return
	var export_wires := get_expanded_wires(wires, false)
	var output_ids: Array = []
	var next_activation_id := maxi(1, GunsawLevelImporter.largest_id(gunsaw_source_level) + 1)
	for gate in gates:
		next_activation_id = maxi(next_activation_id, GunsawLevelImporter.largest_id(gate.get("gunsaw_part", {})) + 1)
	for gate_index in range(gates.size()):
		var gate: Dictionary = gates[gate_index]
		var gate_outputs: Array = []
		for port_index in range(gate["output_names"].size()):
			var imported_ids: Array = gate.get("gunsaw_output_ids", [])
			var channel: int = int(imported_ids[port_index]) if port_index < imported_ids.size() else -1
			var connected := false
			for wire in export_wires:
				if wire["from_gate"] == gate_index and wire["from_port"] == port_index:
					connected = true
					break
			if channel < 0 and (connected or port_index >= imported_ids.size()):
				channel = next_activation_id
				next_activation_id += 1
			gate_outputs.append(channel)
		output_ids.append(gate_outputs)
	# Outputs that feed the same input must share one activation ID in the
	# exported level so every connection is represented.
	var original_output_ids: Array = output_ids.duplicate(true)
	for wire in export_wires:
		var source_id: int = original_output_ids[wire["from_gate"]][wire["from_port"]]
		for other_wire in export_wires:
			if other_wire["to_gate"] == wire["to_gate"] and other_wire["to_port"] == wire["to_port"]:
				output_ids[other_wire["from_gate"]][other_wire["from_port"]] = source_id

	var parts: Array = []
	var exported_gate_indices: Array[int] = []
	var exported_count := 0
	for gate_index in range(gates.size()):
		var gate: Dictionary = gates[gate_index]
		if not gate["export"]:
			continue
		exported_gate_indices.append(gate_index)
		if gate["type_id"] == "MP/IO/BUTTON":
			parts.append({
				"pos": {"x": gate["position"].x / 320.0, "y": -gate["position"].y / 320.0},
				"rot": 0.0,
				"path": "Building/Button",
				"id": output_ids[gate_index][0],
				"activId": 0,
				"team": "",
				"size": {"x": 0.0, "y": 0.0},
				"force": {"x": 0.0, "y": 0.0}
			})
			exported_count += 1
			continue
		if gate["type_id"] == "MP/IO/LAMP":
			parts.append({
				"pos": {"x": gate["position"].x / 320.0, "y": -gate["position"].y / 320.0},
				"rot": 0.0,
				"path": "Building/ColorLamp",
				"id": input_activation_id(gate_index, 0, output_ids, export_wires),
				"activId": 0,
				"team": "#" + str(gate.get("lamp_color", "FFD23F")).trim_prefix("#"),
				"size": {"x": 0.0, "y": 0.0},
				"force": {"x": 1.0, "y": 0.0}
			})
			exported_count += 1
			continue
		if gate["type_id"] in ["GUNSAW/DELAY", "GUNSAW/CYCLE"]:
			var cyclic: bool = gate["type_id"] == "GUNSAW/CYCLE"
			parts.append({
				"pos": {"x": gate["position"].x / 320.0, "y": -gate["position"].y / 320.0},
				"rot": 0.0, "path": "Building/Triggers/TimedTrigger" if cyclic else "Building/Triggers/DelayTrigger",
				"id": input_activation_id(gate_index, 0, output_ids, export_wires),
				"activId": output_ids[gate_index][0], "team": "",
				"size": {"x": 0.0, "y": 0.0},
				"force": {"x": float(gate.get("gunsaw_data", {}).get("cycleTime", 1.0) if cyclic else gate.get("gunsaw_data", {}).get("delay", 0.0)), "y": 0.0}
			})
			exported_count += 1
			continue
		if gate["type_id"] == "EDITOR/WHITETILE":
			parts.append(white_tile_export_part(gate))
			exported_count += 1
			continue
		var data := build_gunsaw_data(gate_index, output_ids, export_wires)
		if data.is_empty():
			status_text = "Export blocked: unsupported component %s." % gate["name"]
			return
		var payload := {
			"version": 1,
			"uid": str(gate["id"]),
			"type": gate["type_id"],
			"data": JSON.stringify(data)
		}
		parts.append({
			"pos": {"x": gate["position"].x / 320.0, "y": -gate["position"].y / 320.0},
			"rot": 0.0,
			"path": "MP/CustomProp",
			"id": 0,
			"activId": 0,
			"team": JSON.stringify(payload),
			"size": {"x": 0.0, "y": 0.0},
			"force": {"x": 0.0, "y": 0.0}
		})
		exported_count += 1
	for part_index in range(parts.size()):
		parts[part_index] = GunsawLevelImporter.merge_exported_part(gates[exported_gate_indices[part_index]], parts[part_index])
	var level := {
		"lightIntensity": 1.0,
		"lightColor": {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
		"hasBackground": false,
		"parts": parts
	}
	if not gunsaw_source_level.is_empty():
		var preserved_parts: Array = gunsaw_source_level.get("parts", []).duplicate(true)
		preserved_parts.append_array(parts)
		level = gunsaw_source_level.duplicate(true)
		level["parts"] = preserved_parts
	var document: Dictionary = gunsaw_source_level.get("_gunsaw_document", {})
	var json: String
	if not document.is_empty():
		var source_indices: Array = document["preserved_indices"].duplicate()
		for index in exported_gate_indices:
			source_indices.append(gates[index].get("gunsaw_index", -1))
		json = GunsawLevelImporter.LevelDocument.export_text(document, level["parts"], source_indices, GunsawLevelImporter.stringify_json)
	else:
		json = GunsawLevelImporter.stringify_json(level)
	var zlib_compressed: PackedByteArray = json.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	if zlib_compressed.size() < 6:
		status_text = "Export failed: compression produced invalid data."
		return
	# Gunsaw's .NET DeflateStream expects raw Deflate, while Godot includes
	# a two-byte zlib header and four-byte Adler-32 trailer.
	var compressed: PackedByteArray = zlib_compressed.slice(2, zlib_compressed.size() - 4)
	var encoded := Marshalls.raw_to_base64(compressed)
	var file := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if file == null:
		status_text = "Export failed: %s." % error_string(FileAccess.get_open_error())
		return
	file.store_string(encoded)
	file.close()
	DisplayServer.clipboard_set(encoded)
	status_text = "Exported %d props to clipboard and %s." % [exported_count, EXPORT_PATH]

func white_tile_export_part(gate: Dictionary) -> Dictionary:
	var tile_size := gate_size(gate)
	var tile_position: Vector2 = gate["position"]
	return {
		"pos": {
			"x": (tile_position.x + tile_size.x * 0.5) / WHITETILE_EXPORT_SCALE,
			"y": -(tile_position.y + tile_size.y * 0.5) / WHITETILE_EXPORT_SCALE
		},
		"rot": 0.0,
		"path": "Building/WhiteTile",
		"id": 0,
		"activId": 0,
		"team": "",
		"size": {"x": tile_size.x / WHITETILE_EXPORT_SCALE, "y": tile_size.y / WHITETILE_EXPORT_SCALE},
		"force": {"x": 0.0, "y": 0.0}
	}

func build_gunsaw_data(gate_index: int, output_ids: Array, export_wires: Array) -> Dictionary:
	var gate: Dictionary = gates[gate_index]
	var input_ids: Array = []
	for input_index in range(gate["input_names"].size()):
		input_ids.append(input_activation_id(gate_index, input_index, output_ids, export_wires))
	var outputs: Array = output_ids[gate_index]
	match gate["type_id"]:
		"MP/Logic/AND", "MP/Logic/OR", "MP/Logic/XOR", "MP/Logic/XNOR", "MP/Logic/NAND", "MP/Logic/NOR":
			return {"inputA": input_ids[0], "inputB": input_ids[1], "output": outputs[0]}
		"MP/Logic/NOT":
			return {"input": input_ids[0], "output": outputs[0]}
		"MP/Logic/CONST":
			return {"output": outputs[0], "value": int(gate.get("gunsaw_data", {}).get("value", 1))}
		"MP/Logic/CLOCK":
			return {"output": outputs[0], "period": float(gate.get("gunsaw_data", {}).get("period", 1.0)), "initialHigh": int(gate.get("gunsaw_data", {}).get("initialHigh", 0))}
		"MP/Logic/EDGE":
			return {"input": input_ids[0], "output": outputs[0], "mode": int(gate.get("gunsaw_data", {}).get("mode", 2))}
		"MP/Logic/SR":
			return {"set": input_ids[0], "reset": input_ids[1], "q": outputs[0], "notQ": outputs[1], "initialQ": int(gate.get("gunsaw_data", {}).get("initialQ", 0))}
		"MP/Logic/DFF":
			return {"d": input_ids[0], "clock": input_ids[1], "q": outputs[0], "notQ": outputs[1], "initialQ": int(gate.get("gunsaw_data", {}).get("initialQ", 0))}
		"MP/Logic/JK":
			return {"j": input_ids[0], "k": input_ids[1], "clock": input_ids[2], "q": outputs[0], "notQ": outputs[1], "initialQ": int(gate.get("gunsaw_data", {}).get("initialQ", 0))}
		"MP/Logic/TFF":
			return {"t": input_ids[0], "clock": input_ids[1], "q": outputs[0], "notQ": outputs[1], "initialQ": int(gate.get("gunsaw_data", {}).get("initialQ", 0))}
	return {}

func input_activation_id(gate_index: int, input_index: int, output_ids: Array, source_wires: Array) -> int:
	for wire in source_wires:
		if wire["to_gate"] == gate_index and wire["to_port"] == input_index:
			return output_ids[wire["from_gate"]][wire["from_port"]]
	var external_ids: Array = gates[gate_index].get("gunsaw_external_inputs", [])
	if input_index < external_ids.size():
		return int(external_ids[input_index])
	return -1
