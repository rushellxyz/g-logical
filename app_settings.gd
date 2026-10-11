extends Node

const AppPalette = preload("res://app_palette.gd")
const ThemeEditor = preload("res://app_theme_editor.gd")
const PerformanceMonitor = preload("res://performance_monitor.gd")
const SETTINGS_PATH := "user://g-logical-settings.cfg"

signal controls_changed
signal save_failed(message: String)

var touchpad_mode := false
var show_fps := false
var vsync_enabled := true
var performance_monitor: PerformanceMonitor
var dialog: AcceptDialog
var choices: OptionButton
var theme_editor: ThemeEditor
var delete_confirmation: ConfirmationDialog
var _theme_update_pending := false
var _delete_id := ""
var settings_path := SETTINGS_PATH

func _ready() -> void:
	load_settings()
	performance_monitor = PerformanceMonitor.new()
	add_child(performance_monitor)
	performance_monitor.fps_changed.connect(func(_fps: int): get_parent().queue_redraw())
	performance_monitor.set_enabled(show_fps)
	apply_vsync()
	build_dialog()

func load_settings() -> void:
	show_fps = false
	vsync_enabled = true
	AppPalette.custom_themes.clear()
	AppPalette.selected = 0
	var settings := ConfigFile.new()
	if settings.load(settings_path) != OK:
		return
	touchpad_mode = bool(settings.get_value("controls", "touchpad_mode", false))
	show_fps = bool(settings.get_value("display", "show_fps", false))
	vsync_enabled = bool(settings.get_value("display", "vsync", true))
	var saved_custom = settings.get_value("appearance", "custom_themes", [])
	if saved_custom is Array:
		for entry in saved_custom:
			if not entry is Dictionary or not entry.get("colors") is Dictionary:
				continue
			var name := str(entry.get("name", "My theme")).strip_edges().left(48)
			var id := str(entry.get("id", ""))
			if name.is_empty() or not id.begins_with("custom_"):
				continue
			var colors := {}
			for role in AppPalette.ROLES:
				var value := str(entry["colors"].get(role, AppPalette.ROLES[role][1]))
				colors[role] = Color(value).to_html(false) if Color.html_is_valid(value) else AppPalette.ROLES[role][1]
			AppPalette.custom_themes.append({"id": id, "name": name, "colors": colors})
	AppPalette.restore_theme(str(settings.get_value("appearance", "theme_id", "")), int(settings.get_value("appearance", "theme", 0)))

func save() -> void:
	var settings := ConfigFile.new()
	settings.set_value("controls", "touchpad_mode", touchpad_mode)
	settings.set_value("display", "show_fps", show_fps)
	settings.set_value("display", "vsync", vsync_enabled)
	settings.set_value("appearance", "theme", AppPalette.selected)
	settings.set_value("appearance", "theme_id", AppPalette.theme_id())
	settings.set_value("appearance", "custom_themes", AppPalette.custom_themes)
	var error := settings.save(settings_path)
	if error != OK:
		save_failed.emit("Could not save app settings: %s." % error_string(error))

func build_dialog() -> void:
	dialog = AcceptDialog.new()
	dialog.title = "Settings"
	dialog.ok_button_text = "Close"
	dialog.confirmed.connect(save)
	dialog.close_requested.connect(save)
	add_child(dialog)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 440
	content.add_theme_constant_override("separation", 12)
	dialog.add_child(content)
	var controls := Label.new()
	controls.text = "Controls"
	controls.add_theme_font_size_override("font_size", 18)
	content.add_child(controls)
	var toggle := CheckButton.new()
	toggle.text = "Touchpad mode"
	toggle.button_pressed = touchpad_mode
	toggle.toggled.connect(func(enabled: bool):
		touchpad_mode = enabled
		controls_changed.emit()
		save()
	)
	content.add_child(toggle)
	var display_heading := Label.new()
	display_heading.text = "Display"
	display_heading.add_theme_font_size_override("font_size", 18)
	content.add_child(display_heading)
	var display_row := HBoxContainer.new()
	display_row.add_theme_constant_override("separation", 20)
	content.add_child(display_row)
	var fps_toggle := CheckButton.new()
	fps_toggle.text = "Show FPS"
	fps_toggle.button_pressed = show_fps
	fps_toggle.toggled.connect(set_show_fps)
	display_row.add_child(fps_toggle)
	var vsync_toggle := CheckButton.new()
	vsync_toggle.text = "VSync"
	vsync_toggle.button_pressed = vsync_enabled
	vsync_toggle.toggled.connect(set_vsync_enabled)
	display_row.add_child(vsync_toggle)
	var appearance := Label.new()
	appearance.text = "Appearance"
	appearance.add_theme_font_size_override("font_size", 18)
	content.add_child(appearance)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	var label := Label.new()
	label.text = "Color palette"
	row.add_child(label)
	choices = OptionButton.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.item_selected.connect(select_theme)
	row.add_child(choices)
	var create_button := Button.new()
	create_button.text = "Create theme"
	create_button.pressed.connect(create_theme)
	content.add_child(create_button)
	theme_editor = ThemeEditor.new()
	theme_editor.theme_renamed.connect(rename_theme)
	theme_editor.color_changed.connect(set_theme_color)
	theme_editor.edit_finished.connect(save)
	theme_editor.delete_requested.connect(request_delete_theme)
	content.add_child(theme_editor)
	delete_confirmation = ConfirmationDialog.new()
	delete_confirmation.title = "Delete theme"
	delete_confirmation.ok_button_text = "Delete"
	delete_confirmation.confirmed.connect(delete_theme)
	dialog.add_child(delete_confirmation)
	refresh_choices()

func set_show_fps(enabled: bool) -> void:
	show_fps = enabled
	performance_monitor.set_enabled(enabled)
	get_parent().queue_redraw()
	save()

func fps_status_text() -> String:
	return "  |  FPS %d" % performance_monitor.fps if show_fps else ""

func set_vsync_enabled(enabled: bool) -> void:
	vsync_enabled = enabled
	apply_vsync()
	save()

func apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode, get_window().get_window_id())

func refresh_choices() -> void:
	choices.clear()
	for name in AppPalette.theme_names():
		choices.add_item(name)
	choices.select(AppPalette.selected)
	theme_editor.refresh()

func select_theme(index: int) -> void:
	AppPalette.selected = index
	theme_editor.refresh()
	apply_theme()
	save()
	resize_dialog.call_deferred()

func create_theme() -> void:
	var colors := AppPalette.snapshot_colors()
	var names := AppPalette.theme_names()
	var name := "My theme"
	var suffix := 2
	while name in names:
		name = "My theme %d" % suffix
		suffix += 1
	AppPalette.custom_themes.append({
		"id": "custom_%d_%d" % [Time.get_ticks_usec(), randi()],
		"name": name,
		"colors": colors
	})
	AppPalette.selected = AppPalette.NAMES.size() + AppPalette.custom_themes.size() - 1
	refresh_choices()
	apply_theme()
	save()
	resize_dialog.call_deferred()
	theme_editor.name_field.grab_focus()
	theme_editor.name_field.select_all()

func rename_theme(value: String) -> void:
	if not AppPalette.is_custom():
		return
	var name := value.strip_edges()
	if name.is_empty():
		return
	AppPalette.custom_themes[AppPalette.selected - AppPalette.NAMES.size()]["name"] = name
	choices.set_item_text(AppPalette.selected, name)
	save()

func set_theme_color(role: String, value: Color) -> void:
	if not AppPalette.is_custom() or not AppPalette.ROLES.has(role):
		return
	AppPalette.custom_themes[AppPalette.selected - AppPalette.NAMES.size()]["colors"][role] = value.to_html(false)
	if not _theme_update_pending:
		_theme_update_pending = true
		flush_theme_edit.call_deferred()

func flush_theme_edit() -> void:
	_theme_update_pending = false
	apply_theme()
	save()

func request_delete_theme() -> void:
	if not AppPalette.is_custom():
		return
	_delete_id = AppPalette.theme_id()
	delete_confirmation.dialog_text = 'Delete theme "%s"?' % AppPalette.custom_themes[AppPalette.selected - AppPalette.NAMES.size()]["name"]
	delete_confirmation.popup_centered()

func delete_theme() -> void:
	for index in range(AppPalette.custom_themes.size()):
		if AppPalette.custom_themes[index]["id"] == _delete_id:
			AppPalette.custom_themes.remove_at(index)
			AppPalette.selected = 0
			break
	_delete_id = ""
	refresh_choices()
	apply_theme()
	save()
	resize_dialog.call_deferred()

func resize_dialog() -> void:
	if dialog.visible:
		dialog.reset_size()
		dialog.popup_centered()

func open() -> void:
	theme_editor.refresh()
	dialog.reset_size()
	dialog.popup_centered()

func apply_theme() -> void:
	AppPalette.apply_to_tree(get_parent(), AppPalette.make_ui_theme())
	get_parent().queue_redraw()
