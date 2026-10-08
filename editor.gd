extends Node2D

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
	{"id": "MP/Logic/CLOCK", "name": "CLOCK", "inputs": [], "outputs": ["OUT"]},
	{"id": "EDITOR/CLOCK_IN", "name": "CLOCK IN", "inputs": ["CLK"], "outputs": []},
	{"id": "EDITOR/CLOCK_OUT", "name": "CLOCK OUT", "inputs": [], "outputs": ["CLK"]},
	{"id": "MP/Logic/AND", "name": "AND", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/OR", "name": "OR", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/XOR", "name": "XOR", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/NAND", "name": "NAND", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/NOR", "name": "NOR", "inputs": ["A", "B"], "outputs": ["OUT"]},
	{"id": "MP/Logic/NOT", "name": "NOT", "inputs": ["IN"], "outputs": ["OUT"]},
	{"id": "MP/Logic/CONST", "name": "CONST", "inputs": [], "outputs": ["OUT"]},
	{"id": "MP/Logic/EDGE", "name": "EDGE", "inputs": ["IN"], "outputs": ["PULSE"]},
	{"id": "MP/Logic/SR", "name": "SR LATCH", "inputs": ["S", "R"], "outputs": ["Q", "/Q"]},
	{"id": "MP/Logic/DFF", "name": "D FLIP-FLOP", "inputs": ["D", "CLK"], "outputs": ["Q", "/Q"]},
	{"id": "MP/Logic/JK", "name": "JK FLIP-FLOP", "inputs": ["J", "K", "CLK"], "outputs": ["Q", "/Q"]},
	{"id": "MP/Logic/TFF", "name": "T FLIP-FLOP", "inputs": ["T", "CLK"], "outputs": ["Q", "/Q"]}
]

var gates: Array[Dictionary] = []
var wires: Array[Dictionary] = []
var selected_gates: Array[int] = []
var selected_gate := -1
var selected_wire := -1
var dragging_gate := -1
var resizing_gate := -1
var resize_start_position := Vector2.ZERO
var resize_start_size := Vector2.ZERO
var drag_offset := Vector2.ZERO
var drag_group_origins: Dictionary = {}
var pending_output := {"gate": -1, "port": -1}
var tick := 0
var running := false
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
var lamp_color_picker: ColorPickerButton
var save_slot_menu: PopupMenu
var current_save_slot := 1
var undo_history: Array[Dictionary] = []
var drag_undo_snapshot: Dictionary = {}
var drag_undo_recorded := false

func _ready() -> void:
	font = ThemeDB.fallback_font
	save_slot_menu = PopupMenu.new()
	save_slot_menu.id_pressed.connect(_on_save_slot_menu_id_pressed)
	add_child(save_slot_menu)
	tps_window_start_ms = Time.get_ticks_msec()
	lamp_color_picker = ColorPickerButton.new()
	lamp_color_picker.tooltip_text = "Adjust selected lamp color"
	lamp_color_picker.custom_minimum_size = Vector2(54, 28)
	lamp_color_picker.color_changed.connect(_on_lamp_color_changed)
	add_child(lamp_color_picker)
	update_lamp_color_picker()
	queue_redraw()

func _process(_delta: float) -> void:
	update_ticks_per_second()
	update_lamp_color_picker()
	if running:
		simulate_tick()
		await get_tree().create_timer(0.18).timeout
	queue_redraw()

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#111722"))
	draw_rect(Rect2(0, TOPBAR_HEIGHT, size.x, size.y - TOPBAR_HEIGHT), Color("#15271f") if physical_mode else Color("#151c29"))
	draw_set_transform(canvas_transform_origin(), 0.0, Vector2(canvas_zoom, canvas_zoom))
	var canvas_top_left := screen_to_canvas(Vector2(0, TOPBAR_HEIGHT))
	var canvas_bottom_right := screen_to_canvas(size)
	var first_grid_x := floori(canvas_top_left.x / GRID_SIZE) - 1
	var last_grid_x := ceili(canvas_bottom_right.x / GRID_SIZE) + 1
	var grid_color := Color("#28543f") if physical_mode else Color("#202a3a")
	for x in range(first_grid_x, last_grid_x + 1):
		var grid_x := x * GRID_SIZE
		draw_line(Vector2(grid_x, canvas_top_left.y), Vector2(grid_x, canvas_bottom_right.y), grid_color, 1.0 / canvas_zoom)
	var first_grid_y := floori((canvas_top_left.y - TOPBAR_HEIGHT) / GRID_SIZE) - 1
	var last_grid_y := ceili((canvas_bottom_right.y - TOPBAR_HEIGHT) / GRID_SIZE) + 1
	for y in range(first_grid_y, last_grid_y + 1):
		var grid_y := TOPBAR_HEIGHT + y * GRID_SIZE
		draw_line(Vector2(canvas_top_left.x, grid_y), Vector2(canvas_bottom_right.x, grid_y), grid_color, 1.0 / canvas_zoom)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(gates.size()):
		if gates[i]["type_id"] == "EDITOR/WHITETILE" and not physical_mode:
			continue
		if physical_mode and not is_physical_gate(gates[i]):
			continue
		_draw_gate(gates[i], i)
	if not physical_mode:
		for i in range(wires.size()):
			_draw_wire(wires[i], i == selected_wire)
	if selecting:
		draw_rect(Rect2(selection_start, selection_current - selection_start).abs(), Color("#6ca9e8", 0.18), true)
		draw_rect(Rect2(selection_start, selection_current - selection_start).abs(), Color("#8bc5f5"), false, 1.0)
	if not physical_mode and pending_output["gate"] >= 0 and get_local_mouse_position().y >= TOPBAR_HEIGHT:
		draw_set_transform(canvas_transform_origin(), 0.0, Vector2(canvas_zoom, canvas_zoom))
		var start := port_position(pending_output["gate"], false, pending_output["port"])
		draw_line(start, screen_to_canvas(get_local_mouse_position()), Color("#f5c451"), 3.0 / canvas_zoom)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(0, 0, size.x, TOPBAR_HEIGHT), Color("#202b3d"))
	draw_string(font, Vector2(18, 27), "G-LOGICAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#f2f5fb"))
	draw_string(font, Vector2(18, 51), "Gunsaw logic editor", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#95a5bd"))
	_draw_toolbar()
	draw_string(font, Vector2(18, get_viewport_rect().size.y - 18), "Tick %d  |  TPS %.1f  |  %s" % [tick, ticks_per_second, status_text], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#aab8cb"))

func _draw_toolbar() -> void:
	var physical_rect := Rect2(88, 12, 84, 28)
	draw_rect(physical_rect, Color("#3d7655") if physical_mode else Color("#34445d"), true)
	draw_string(font, physical_rect.position + Vector2(7, 19), "PHYSICAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f1f5fa"))
	var x := 180.0
	var select_rect := Rect2(x, 12, 82, 28)
	draw_rect(select_rect, Color("#4875a5") if active_tool == "SELECT" else Color("#34445d"), true)
	draw_string(font, select_rect.position + Vector2(8, 19), "SELECT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f1f5fa"))
	x += select_rect.size.x + 6
	if physical_mode:
		var tile_rect := Rect2(x, 12, 108, 28)
		draw_rect(tile_rect, Color("#34445d"), true)
		draw_string(font, tile_rect.position + Vector2(8, 19), "WHITE TILE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f1f5fa"))
		x += tile_rect.size.x + 6
	for i in range(GATE_TYPES.size()):
		var gate_type: Dictionary = GATE_TYPES[i]
		if physical_mode:
			continue
		var rect := Rect2(x, 12, 82 if gate_type["name"].length() < 6 else 108, 28)
		draw_rect(rect, Color("#34445d") if i != selected_gate else Color("#4875a5"), true)
		draw_string(font, rect.position + Vector2(8, 19), gate_type["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f1f5fa"))
		x += rect.size.x + 6
		if x > get_viewport_rect().size.x - 240:
			break
	draw_rect(Rect2(get_viewport_rect().size.x - 220, 12, 92, 28), Color("#385e58") if running else Color("#34445d"), true)
	draw_string(font, Vector2(get_viewport_rect().size.x - 208, 31), "RUN" if running else "PAUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	draw_rect(Rect2(get_viewport_rect().size.x - 120, 12, 105, 28), Color("#34445d"), true)
	draw_string(font, Vector2(get_viewport_rect().size.x - 108, 31), "STEP  [Space]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_rect(Rect2(get_viewport_rect().size.x - 470, 12, 70, 28), Color("#34445d"), true)
	draw_string(font, Vector2(get_viewport_rect().size.x - 458, 31), "SAVE %d" % current_save_slot, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_rect(Rect2(get_viewport_rect().size.x - 395, 12, 70, 28), Color("#34445d"), true)
	draw_string(font, Vector2(get_viewport_rect().size.x - 383, 31), "LOAD %d" % current_save_slot, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_rect(Rect2(get_viewport_rect().size.x - 320, 12, 70, 28), Color("#486b55"), true)
	draw_string(font, Vector2(get_viewport_rect().size.x - 310, 31), "EXPORT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	draw_string(font, Vector2(180, 58), "CLK IN feeds every CLK OUT on export. Select or drag nodes; connect output -> input.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#9eacc0"))

func _draw_gate(gate: Dictionary, gate_index: int) -> void:
	draw_set_transform(canvas_transform_origin(), 0.0, Vector2(canvas_zoom, canvas_zoom))
	var rect := Rect2(gate["position"], gate_size(gate))
	if gate["type_id"] == "EDITOR/WHITETILE":
		draw_rect(rect, Color("#434443"), true)
		draw_rect(rect, Color("#9ca9a0") if gate_index not in selected_gates else Color("#71c28b"), false, 2)
		if gate_index in selected_gates:
			draw_rect(Rect2(rect.end - Vector2(10, 10), Vector2(10, 10)), Color("#71c28b"), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var is_selected: bool = gate_index in selected_gates
	var gate_color := Color("#3d628b") if is_selected else Color("#29364b")
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
	draw_string(font, rect.position + Vector2(10, 19), gate["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#f5f7fb"))
	if gate["type_id"] == "EDITOR/COMMENT":
		draw_string(font, rect.position + Vector2(10, 58), gate["text"], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20, 14, Color("#ffe7a3"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if gate["type_id"] == "MP/IO/BUTTON":
		draw_string(font, rect.position + Vector2(10, 61), "Click to pulse", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c5d0df"))
	elif gate["type_id"] == "MP/IO/LAMP":
		draw_string(font, rect.position + Vector2(10, 61), "ON" if gate["state"] else "OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffe08a") if gate["state"] else Color("#9aa8b8"))
	for i in range(gate["inputs"].size()):
		var pos := port_position(gate_index, true, i)
		var value: bool = gate["inputs"][i]
		draw_circle(pos, PORT_RADIUS, Color("#61d49a") if value else Color("#68778e"))
		draw_string(font, pos + Vector2(12, 4), gate["input_names"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c5d0df"))
	for i in range(gate["outputs"].size()):
		var pos := port_position(gate_index, false, i)
		var value: bool = gate["outputs"][i]
		draw_circle(pos, PORT_RADIUS, Color("#f0c15b") if value else Color("#68778e"))
		draw_string(font, pos + Vector2(-58, 4), gate["output_names"][i], HORIZONTAL_ALIGNMENT_RIGHT, 48, 12, Color("#c5d0df"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func is_physical_gate(gate: Dictionary) -> bool:
	return is_physical_gate_type(gate["type_id"])

func is_physical_gate_type(type_id: String) -> bool:
	return type_id in ["MP/IO/BUTTON", "MP/IO/LAMP", "EDITOR/WHITETILE"]

func gate_size(gate: Dictionary) -> Vector2:
	if gate["type_id"] == "EDITOR/WHITETILE":
		return gate.get("size", Vector2(10, 2) * PHYSICAL_UNIT_SIZE)
	return NODE_SIZE

func _draw_wire(wire: Dictionary, selected: bool) -> void:
	draw_set_transform(canvas_transform_origin(), 0.0, Vector2(canvas_zoom, canvas_zoom))
	var a := port_position(wire["from_gate"], false, wire["from_port"])
	var b := port_position(wire["to_gate"], true, wire["to_port"])
	var high: bool = gates[wire["from_gate"]]["outputs"][wire["from_port"]]
	var wire_color := Color("#f5c451") if high else Color("#71839d")
	if selected:
		wire_color = Color("#f28b82")
	draw_line(a, b, wire_color, 5 if selected else (4 if high else 2))
	draw_circle(a, 4, wire_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func port_position(gate_id: int, input: bool, port: int) -> Vector2:
	var gate: Dictionary = gates[gate_id]
	var count: int = gate["inputs"].size() if input else gate["outputs"].size()
	var y: float = gate["position"].y + 42.0 + (port + 1) * (42.0 / max(count, 1))
	return Vector2(gate["position"].x if input else gate["position"].x + NODE_SIZE.x, y)

func canvas_transform_origin() -> Vector2:
	return canvas_offset + Vector2(0, TOPBAR_HEIGHT * (1.0 - canvas_zoom))

func canvas_to_screen(pos: Vector2) -> Vector2:
	return canvas_transform_origin() + pos * canvas_zoom

func screen_to_canvas(pos: Vector2) -> Vector2:
	return (pos - canvas_transform_origin()) / canvas_zoom

func update_lamp_color_picker() -> void:
	if lamp_color_picker == null:
		return
	lamp_color_picker.position = Vector2(get_viewport_rect().size.x - 550, 12)
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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.alt_pressed and event.shift_pressed and event.keycode == KEY_O:
			open_user_folder()
			return
		if event.ctrl_pressed and event.keycode == KEY_Z:
			undo_last_action()
			return
		if event.ctrl_pressed and event.keycode == KEY_S:
			save_editor()
			return
		if event.ctrl_pressed and event.keycode == KEY_O:
			load_editor()
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
			if event.unicode > 0:
				push_undo_state()
				gates[selected_gate]["text"] += char(event.unicode)
				queue_redraw()
				return
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			delete_selection()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			handle_press(event.position, event.shift_pressed)
		else:
			if selecting:
				finish_box_selection()
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
		var new_zoom: float = clampf(canvas_zoom * zoom_factor, 0.25, 2.0)
		canvas_zoom = new_zoom
		canvas_offset = event.position - zoom_anchor * canvas_zoom - Vector2(0, TOPBAR_HEIGHT * (1.0 - canvas_zoom))
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		handle_delete_press(event.position)
	if event is InputEventMouseMotion and dragging_gate >= 0:
		var dragged_position := snap_position(screen_to_canvas(event.position) - drag_offset)
		var movement: Vector2 = dragged_position - drag_group_origins[dragging_gate]
		if movement != Vector2.ZERO and not drag_undo_recorded:
			push_undo_snapshot(drag_undo_snapshot)
			drag_undo_recorded = true
		for gate_index in selected_gates:
			gates[gate_index]["position"] = snap_position(drag_group_origins[gate_index] + movement)
		queue_redraw()
	if event is InputEventMouseMotion and resizing_gate >= 0:
		var resized_position := screen_to_canvas(event.position)
		var new_size := resized_position - resize_start_position
		var updated_size := Vector2(
			maxf(PHYSICAL_UNIT_SIZE, snapped(new_size.x, PHYSICAL_UNIT_SIZE)),
			maxf(PHYSICAL_UNIT_SIZE, snapped(new_size.y, PHYSICAL_UNIT_SIZE))
		)
		if updated_size != gate_size(gates[resizing_gate]) and not drag_undo_recorded:
			push_undo_snapshot(drag_undo_snapshot)
			drag_undo_recorded = true
		gates[resizing_gate]["size"] = updated_size
		queue_redraw()
	if event is InputEventMouseMotion and selecting:
		selection_current = event.position
		queue_redraw()
	if event is InputEventMouseMotion and panning:
		canvas_offset = pan_offset_start + event.position - pan_start
		clamp_canvas_offset()
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

func handle_press(pos: Vector2, swap_selected := false) -> void:
	if pos.y < TOPBAR_HEIGHT:
		var physical_rect := Rect2(88, 12, 84, 28)
		if physical_rect.has_point(pos):
			physical_mode = not physical_mode
			selected_gates.clear()
			selected_gate = -1
			selected_wire = -1
			pending_output = {"gate": -1, "port": -1}
			selecting = false
			status_text = "Physical mode enabled." if physical_mode else "Editor mode enabled."
			queue_redraw()
			return
		if pos.x >= get_viewport_rect().size.x - 320 and pos.x < get_viewport_rect().size.x - 250:
			export_gunsaw()
			return
		if pos.x >= get_viewport_rect().size.x - 470 and pos.x < get_viewport_rect().size.x - 400:
			open_save_slot_menu(pos, true)
			return
		if pos.x >= get_viewport_rect().size.x - 395 and pos.x < get_viewport_rect().size.x - 325:
			open_save_slot_menu(pos, false)
			return
		if pos.x >= get_viewport_rect().size.x - 220 and pos.x < get_viewport_rect().size.x - 120:
			running = not running
			status_text = "Simulation running." if running else "Simulation paused."
			return
		if pos.x >= get_viewport_rect().size.x - 120:
			simulate_tick()
			return
		var select_rect := Rect2(180, 12, 82, 28)
		if select_rect.has_point(pos):
			active_tool = "SELECT"
			status_text = "Selection tool active."
			queue_redraw()
			return
		if physical_mode:
			var tile_rect := Rect2(268, 12, 108, 28)
			if tile_rect.has_point(pos):
				add_white_tile()
				return
		var button_x := 268.0
		for i in range(GATE_TYPES.size()):
			var gate_type: Dictionary = GATE_TYPES[i]
			if physical_mode:
				continue
			var button_width := 82.0 if gate_type["name"].length() < 6 else 108.0
			if Rect2(button_x, 12, button_width, 28).has_point(pos):
				if swap_selected and not selected_gates.is_empty():
					swap_selected_gates(i)
					return
				add_gate(i)
				return
			button_x += button_width + 6
		return
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
		status_text = "Select an input port to finish the connection."
		return
	for i in range(gates.size() - 1, -1, -1):
		if gates[i]["type_id"] == "EDITOR/WHITETILE" and not physical_mode:
			continue
		if physical_mode and not is_physical_gate(gates[i]):
			continue
		var rect := Rect2(gates[i]["position"], gate_size(gates[i]))
		if rect.has_point(pos):
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
				selected_wire = -1
				var resize_handle := Rect2(rect.end - Vector2(14, 14), Vector2(14, 14))
				if resize_handle.has_point(pos):
					resizing_gate = i
					begin_drag_undo()
					resize_start_position = gates[i]["position"]
					resize_start_size = gate_size(gates[i])
				else:
					dragging_gate = i
					begin_drag_undo()
					drag_offset = pos - gates[i]["position"]
					drag_group_origins = {i: gates[i]["position"]}
				status_text = "Selected WhiteTile. Drag the corner to resize."
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
	var wire_index := find_wire(pos)
	if wire_index >= 0:
		selected_gates.clear()
		selected_gate = -1
		selected_wire = wire_index
		pending_output = {"gate": -1, "port": -1}
		status_text = "Selected wire. Press Delete or right-click to remove it."
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
	for gate_index in selected_gates:
		for wire in wires:
			if wire["from_gate"] == gate_index and wire["from_port"] >= definition["outputs"].size():
				status_text = "Swap blocked: %s has too few output ports." % definition["name"]
				return
			if wire["to_gate"] == gate_index and wire["to_port"] >= definition["inputs"].size():
				status_text = "Swap blocked: %s has too few input ports." % definition["name"]
				return
	push_undo_state()
	for gate_index in selected_gates:
		var gate: Dictionary = gates[gate_index]
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
	status_text = "Swapped %d gate%s to %s. Shift-click toolbar gates to swap again." % [
		selected_gates.size(),
		"" if selected_gates.size() == 1 else "s",
		definition["name"]
	]
	queue_redraw()

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
	pos = screen_to_canvas(pos)
	var port := find_port(pos)
	if port["gate"] >= 0:
		selected_gates = [port["gate"]]
		selected_gate = port["gate"]
		selected_wire = -1
	else:
		var gate_index := find_gate(pos)
		if gate_index >= 0:
			selected_gates = [gate_index]
			selected_gate = gate_index
			selected_wire = -1
		else:
			selected_gate = -1
			selected_wire = find_wire(pos)
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
	if physical_mode:
		return -1
	for i in range(wires.size() - 1, -1, -1):
		var wire: Dictionary = wires[i]
		var start := port_position(wire["from_gate"], false, wire["from_port"])
		var end := port_position(wire["to_gate"], true, wire["to_port"])
		if Geometry2D.get_closest_point_to_segment(pos, start, end).distance_to(pos) <= 9.0:
			return i
	return -1

func find_port(pos: Vector2) -> Dictionary:
	for i in range(gates.size() - 1, -1, -1):
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
	var viewport_size := get_viewport_rect().size
	var view_center := Vector2(viewport_size.x * 0.5, TOPBAR_HEIGHT + (viewport_size.y - TOPBAR_HEIGHT) * 0.5)
	var spawn_position := snap_position(screen_to_canvas(view_center) - NODE_SIZE * 0.5)
	var gate := {
		"id": next_id,
		"type_id": definition["id"],
		"name": definition["name"],
		"position": spawn_position,
		"input_names": definition["inputs"],
		"output_names": definition["outputs"],
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
	status_text = "Placed %s." % definition["name"]
	queue_redraw()

func add_white_tile() -> void:
	var viewport_size := get_viewport_rect().size
	var view_center := Vector2(viewport_size.x * 0.5, TOPBAR_HEIGHT + (viewport_size.y - TOPBAR_HEIGHT) * 0.5)
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
	for wire in get_expanded_wires(source_wires):
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

func get_expanded_wires(source_wires: Array, include_clock_inputs := true) -> Array:
	var expanded: Array = []
	var clock_destinations: Array[Dictionary] = []
	for wire in source_wires:
		var from_gate := int(wire["from_gate"])
		var to_gate := int(wire["to_gate"])
		if gates[from_gate]["type_id"] == "EDITOR/CLOCK_OUT":
			clock_destinations.append(wire)
			continue
		if not include_clock_inputs and gates[to_gate]["type_id"] == "EDITOR/CLOCK_IN":
			continue
		expanded.append(wire.duplicate(true))
	for destination in clock_destinations:
		for source in source_wires:
			var source_target := int(source["to_gate"])
			if gates[source_target]["type_id"] != "EDITOR/CLOCK_IN":
				continue
			expanded.append({
				"from_gate": source["from_gate"],
				"from_port": source["from_port"],
				"to_gate": destination["to_gate"],
				"to_port": destination["to_port"]
			})
	return expanded

func simulate_tick() -> void:
	# Compute all outputs from the inputs captured during the previous tick.
	for gate in gates:
		var inputs: Array = gate["inputs"]
		var result := false
		match gate["type_id"]:
			"EDITOR/CLOCK_OUT": result = clock_bus_output_state()
			"MP/IO/BUTTON": result = gate["pulse_pending"]
			"MP/IO/LAMP":
				if gate["inputs"][0] and not gate["previous_inputs"][0]:
					gate["state"] = not gate["state"]
			"MP/Logic/AND": result = inputs[0] and inputs[1]
			"MP/Logic/OR": result = inputs[0] or inputs[1]
			"MP/Logic/XOR": result = inputs[0] != inputs[1]
			"MP/Logic/NAND": result = not (inputs[0] and inputs[1])
			"MP/Logic/NOR": result = not (inputs[0] or inputs[1])
			"MP/Logic/NOT": result = not inputs[0]
			"MP/Logic/CONST": result = true
			"MP/Logic/CLOCK": result = tick % 2 == 0
			"MP/Logic/EDGE": result = inputs[0] != gate["previous_inputs"][0]
			"MP/Logic/SR": result = gate["memory"] if inputs[0] and inputs[1] else (true if inputs[0] else false if inputs[1] else gate["memory"])
			"MP/Logic/DFF": result = inputs[0] if inputs[1] and not gate["previous_inputs"][1] else gate["memory"]
			"MP/Logic/JK": result = (not gate["memory"]) if inputs[2] and not gate["previous_inputs"][2] and inputs[0] and inputs[1] else (true if inputs[2] and not gate["previous_inputs"][2] and inputs[0] else false if inputs[2] and not gate["previous_inputs"][2] and inputs[1] else gate["memory"])
			"MP/Logic/TFF": result = (not gate["memory"]) if inputs[1] and not gate["previous_inputs"][1] and inputs[0] else gate["memory"]
		if gate["type_id"] in ["MP/Logic/SR", "MP/Logic/DFF", "MP/Logic/JK", "MP/Logic/TFF"]:
			gate["memory"] = result
		for i in range(gate["outputs"].size()):
			gate["outputs"][i] = result if i == 0 else not result
		gate["pulse_pending"] = false
		gate["previous_inputs"] = gate["inputs"].duplicate()
	for gate in gates:
		if gate["type_id"] == "EDITOR/CLOCK_OUT":
			gate["outputs"][0] = clock_bus_output_state()
	# Transfer outputs only after every component has evaluated.
	var next_inputs: Array = []
	for gate in gates:
		next_inputs.append([])
		for _input_value in gate["inputs"]:
			next_inputs[-1].append(false)
	var active_drivers: Dictionary = {}
	for wire in get_expanded_wires(wires):
		var source_is_on: bool = gates[wire["from_gate"]]["outputs"][wire["from_port"]]
		if source_is_on:
			var input_key := "%d:%d" % [wire["to_gate"], wire["to_port"]]
			active_drivers[input_key] = int(active_drivers.get(input_key, 0)) + 1
			if active_drivers[input_key] > 1:
				running = false
				status_text = "Simulation halted: multiple active wires drive the same input."
				queue_redraw()
				return
		next_inputs[wire["to_gate"]][wire["to_port"]] = next_inputs[wire["to_gate"]][wire["to_port"]] or source_is_on
	for i in range(gates.size()):
		gates[i]["inputs"] = next_inputs[i]
	tick += 1
	ticks_in_tps_window += 1
	status_text = "Advanced one frame; outputs will be consumed next tick."
	queue_redraw()

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
	return {
		"gates": gates.duplicate(true),
		"wires": wires.duplicate(true),
		"tick": tick,
		"next_id": next_id,
		"canvas_offset": canvas_offset,
		"selected_gates": selected_gates.duplicate(),
		"selected_gate": selected_gate,
		"selected_wire": selected_wire,
		"pending_output": pending_output.duplicate()
	}

func push_undo_state() -> void:
	push_undo_snapshot(create_undo_snapshot())

func push_undo_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	undo_history.append(snapshot)
	if undo_history.size() > MAX_UNDO_STEPS:
		undo_history.pop_front()

func begin_drag_undo() -> void:
	drag_undo_snapshot = create_undo_snapshot()
	drag_undo_recorded = false

func undo_last_action() -> void:
	if undo_history.is_empty():
		status_text = "Nothing to undo."
		return
	var snapshot: Dictionary = undo_history.pop_back()
	gates.assign(snapshot["gates"])
	wires.assign(snapshot["wires"])
	tick = snapshot["tick"]
	next_id = snapshot["next_id"]
	canvas_offset = snapshot["canvas_offset"]
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
	current_save_slot = clampi(slot, 1, SAVE_SLOT_COUNT)
	var save_path := save_slot_path(current_save_slot)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		status_text = "Save failed: %s." % error_string(FileAccess.get_open_error())
		return
	var saved_gates: Array = gates.duplicate(true)
	for gate in saved_gates:
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
	var document := {
		"format": 1,
		"tick": tick,
		"next_id": next_id,
		"canvas_offset": [canvas_offset.x, canvas_offset.y],
		"gates": saved_gates,
		"wires": wires
	}
	file.store_string(JSON.stringify(document, "\t"))
	file.close()
	status_text = "Editor saved to Slot %d (%s)." % [current_save_slot, save_path]

func load_editor(slot: int = current_save_slot) -> void:
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
		loaded_gate["memory"] = false
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
	status_text = "Editor loaded from Slot %d (%s)." % [current_save_slot, save_path]
	queue_redraw()

func save_slot_path(slot: int) -> String:
	if slot == 1:
		return SAVE_PATH
	return "user://g-logical-editor-slot-%d.json" % slot

func export_gunsaw() -> void:
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
	var next_activation_id := 1
	for gate_index in range(gates.size()):
		var gate: Dictionary = gates[gate_index]
		var gate_outputs: Array = []
		for _output_name in gate["output_names"]:
			if gate["type_id"] == "MP/IO/BUTTON":
				gate_outputs.append(1000 + gate_index)
			else:
				gate_outputs.append(next_activation_id)
				next_activation_id += 1
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
	var exported_count := 0
	for gate_index in range(gates.size()):
		var gate: Dictionary = gates[gate_index]
		if not gate["export"]:
			continue
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
		if gate["type_id"] == "EDITOR/WHITETILE":
			var tile_size := gate_size(gate)
			var tile_position: Vector2 = gate["position"]
			parts.append({
				"pos": {
					"x": (tile_position.x + tile_size.x * 0.5) / WHITETILE_EXPORT_SCALE,
					"y": -(tile_position.y + tile_size.y) / WHITETILE_EXPORT_SCALE
				},
				"rot": 0.0,
				"path": "Building/WhiteTile",
				"id": 0,
				"activId": 0,
				"team": "",
				"size": {"x": tile_size.x / WHITETILE_EXPORT_SCALE, "y": tile_size.y / WHITETILE_EXPORT_SCALE},
				"force": {"x": 0.0, "y": 0.0}
			})
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
	var level := {
		"lightIntensity": 1.0,
		"lightColor": {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
		"hasBackground": false,
		"parts": parts
	}
	var json := JSON.stringify(level)
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

func build_gunsaw_data(gate_index: int, output_ids: Array, export_wires: Array) -> Dictionary:
	var gate: Dictionary = gates[gate_index]
	var input_ids: Array = []
	for input_index in range(gate["input_names"].size()):
		input_ids.append(input_activation_id(gate_index, input_index, output_ids, export_wires))
	var outputs: Array = output_ids[gate_index]
	match gate["type_id"]:
		"MP/Logic/AND", "MP/Logic/OR", "MP/Logic/XOR", "MP/Logic/NAND", "MP/Logic/NOR":
			return {"inputA": input_ids[0], "inputB": input_ids[1], "output": outputs[0]}
		"MP/Logic/NOT":
			return {"input": input_ids[0], "output": outputs[0]}
		"MP/Logic/CONST":
			return {"output": outputs[0], "value": 1}
		"MP/Logic/CLOCK":
			return {"output": outputs[0], "period": 1.0, "initialHigh": 0}
		"MP/Logic/EDGE":
			return {"input": input_ids[0], "output": outputs[0], "mode": 2}
		"MP/Logic/SR":
			return {"set": input_ids[0], "reset": input_ids[1], "q": outputs[0], "notQ": outputs[1], "initialQ": 0}
		"MP/Logic/DFF":
			return {"d": input_ids[0], "clock": input_ids[1], "q": outputs[0], "notQ": outputs[1], "initialQ": 0}
		"MP/Logic/JK":
			return {"j": input_ids[0], "k": input_ids[1], "clock": input_ids[2], "q": outputs[0], "notQ": outputs[1], "initialQ": 0}
		"MP/Logic/TFF":
			return {"t": input_ids[0], "clock": input_ids[1], "q": outputs[0], "notQ": outputs[1], "initialQ": 0}
	return {}

func input_activation_id(gate_index: int, input_index: int, output_ids: Array, source_wires: Array) -> int:
	for wire in source_wires:
		if wire["to_gate"] == gate_index and wire["to_port"] == input_index:
			return output_ids[wire["from_gate"]][wire["from_port"]]
	return -1
