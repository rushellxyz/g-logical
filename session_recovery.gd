extends Node

const FORMAT := 1
const MAGIC := "G-LOGICAL SESSION 1"
const INTERVAL := 10.0

signal save_failed(message: String)

var storage_path := "user://g-logical-session.dat"
var capture: Callable
var restore: Callable
var sessions: Dictionary = {}
var last_mode := "editor"
var pending := false
var elapsed := 0.0
var changed := false
var dialog: ConfirmationDialog
var choices: OptionButton
var writer: Thread
var queued_document: Dictionary = {}

func initialize(capture_callback: Callable, restore_callback: Callable) -> void:
	capture = capture_callback
	restore = restore_callback
	var document := read_document(storage_path)
	if document.is_empty():
		document = read_document(storage_path + ".bak")
	sessions = document.get("sessions", {})
	last_mode = str(document.get("last_mode", "editor"))
	for mode in sessions.keys():
		if mode not in ["editor", "foundry"] or not sessions[mode] is Dictionary or not sessions[mode].get("snapshot") is Dictionary:
			sessions.erase(mode)
	pending = not sessions.is_empty()
	if pending:
		build_dialog()
		dialog.popup_centered()

func build_dialog() -> void:
	dialog = ConfirmationDialog.new()
	dialog.title = "Restore previous session?"
	dialog.ok_button_text = "Restore"
	dialog.cancel_button_text = "Start new"
	dialog.exclusive = true
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 420
	box.add_theme_constant_override("separation", 12)
	dialog.add_child(box)
	var hint := Label.new()
	hint.text = "An autosaved session is available.\nChoose a workspace to restore."
	box.add_child(hint)
	choices = OptionButton.new()
	box.add_child(choices)
	for mode in ["editor", "foundry"]:
		if not sessions.has(mode):
			continue
		var saved_at := str(sessions[mode].get("saved_at", ""))
		choices.add_item("%s — %s" % [mode.capitalize(), saved_at.replace("T", " ")])
		var index := choices.item_count - 1
		choices.set_item_metadata(index, mode)
		if mode == last_mode:
			choices.select(index)
	dialog.confirmed.connect(restore_selected)
	dialog.canceled.connect(start_new)
	add_child(dialog)

func restore_selected() -> void:
	var mode := str(choices.get_item_metadata(choices.selected))
	if not restore.call(sessions[mode]["snapshot"]):
		save_failed.emit("Could not restore session: invalid autosave.")
		dialog.call_deferred("popup_centered")
		return
	pending = false
	elapsed = 0.0
	changed = false

func start_new() -> void:
	pending = false
	sessions.clear()
	changed = false
	elapsed = 0.0
	queue_write()

func mark_changed() -> void:
	if pending:
		return
	if not changed:
		elapsed = maxf(elapsed, INTERVAL - 1.0)
	changed = true

func _process(delta: float) -> void:
	poll_writer()
	if pending or not capture.is_valid():
		return
	elapsed += delta
	if elapsed >= INTERVAL:
		elapsed = 0.0
		save_now()

func save_now() -> void:
	if pending or not capture.is_valid():
		return
	var snapshot: Dictionary = capture.call()
	var mode := "foundry" if snapshot.get("foundry_mode", false) else "editor"
	if snapshot.get("gates", []).is_empty() and not changed and not sessions.has(mode):
		return
	sessions[mode] = {"saved_at": Time.get_datetime_string_from_system(), "snapshot": snapshot}
	last_mode = mode
	queue_write()
	changed = false

static func read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_line() != MAGIC:
		return {}
	var checksum := file.get_line()
	var data := file.get_buffer(file.get_length() - file.get_position())
	if checksum != data.hex_encode().sha256_text():
		return {}
	var document = bytes_to_var(data)
	if not document is Dictionary or document.get("format") != FORMAT or not document.get("sessions") is Dictionary:
		return {}
	return document

func queue_write() -> void:
	queued_document = {"format": FORMAT, "last_mode": last_mode, "sessions": sessions.duplicate()}
	poll_writer()

func poll_writer() -> void:
	if writer != null:
		if writer.is_alive():
			return
		complete_write()
	if queued_document.is_empty():
		return
	var document := queued_document
	queued_document = {}
	writer = Thread.new()
	var error := writer.start(write_document.bind(ProjectSettings.globalize_path(storage_path), document))
	if error != OK:
		writer = null
		report_failure(error)

func complete_write() -> void:
	var error: Error = writer.wait_to_finish()
	writer = null
	if error != OK:
		report_failure(error)

func finish_writes() -> void:
	while writer != null or not queued_document.is_empty():
		if writer != null:
			complete_write()
		poll_writer()

func _exit_tree() -> void:
	finish_writes()

static func write_document(path: String, document: Dictionary) -> Error:
	var data := var_to_bytes(document)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_line(MAGIC)
	file.store_line(data.hex_encode().sha256_text())
	file.store_buffer(data)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	if not read_document(path).is_empty():
		error = DirAccess.copy_absolute(path, path + ".bak")
		if error != OK:
			return error
	return DirAccess.rename_absolute(path + ".tmp", path)

func report_failure(error: Error) -> void:
	save_failed.emit("Autosave failed: %s." % error_string(error))
