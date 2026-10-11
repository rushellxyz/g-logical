extends Node

const AppPalette = preload("res://app_palette.gd")
const ThemeEditor = preload("res://app_theme_editor.gd")
const SETTINGS_PATH := "user://g-logical-settings.cfg"

signal controls_changed
signal save_failed(message: String)

var touchpad_mode := false
var dialog: AcceptDialog
var choices: OptionButton
var theme_editor: ThemeEditor
var delete_confirmation: ConfirmationDialog
var _theme_update_pending := false
var _delete_id := ""
var settings_path := SETTINGS_PATH

func _ready() -> void:
	load_settings()
	build_dialog()

func load_settings() -> void:
	AppPalette.custom_themes.clear()
	AppPalette.selected = 0
	var settings := ConfigFile.new()
	if settings.load(settings_path) != OK:
		return
	touchpad_mode = bool(settings.get_value("controls", "touchpad_mode", false))
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
