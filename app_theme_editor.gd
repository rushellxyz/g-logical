extends VBoxContainer

const AppPalette = preload("res://app_palette.gd")

signal theme_renamed(name: String)
signal color_changed(role: String, color: Color)
signal edit_finished
signal delete_requested

var name_field: LineEdit
var pickers: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var name_row := HBoxContainer.new()
	add_child(name_row)
	name_field = LineEdit.new()
	name_field.placeholder_text = "Theme name"
	name_field.max_length = 48
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.text_changed.connect(func(value: String): theme_renamed.emit(value))
	name_field.text_submitted.connect(func(_value: String): edit_finished.emit())
	name_field.focus_exited.connect(func(): edit_finished.emit())
	name_row.add_child(name_field)
	var delete_button := Button.new()
	delete_button.text = "Delete theme"
	delete_button.pressed.connect(func(): delete_requested.emit())
	name_row.add_child(delete_button)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var fields := GridContainer.new()
	fields.columns = 2
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("h_separation", 16)
	fields.add_theme_constant_override("v_separation", 8)
	scroll.add_child(fields)
	for role in AppPalette.ROLES:
		var label := Label.new()
		label.text = AppPalette.ROLES[role][0]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fields.add_child(label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(72, 28)
		picker.edit_alpha = false
		picker.color_changed.connect(func(value: Color): color_changed.emit(role, value))
		picker.popup_closed.connect(func(): edit_finished.emit())
		fields.add_child(picker)
		pickers[role] = picker

func refresh() -> void:
	visible = AppPalette.is_custom()
	if not visible:
		return
	name_field.text = AppPalette.custom_themes[AppPalette.selected - AppPalette.NAMES.size()]["name"]
	for role in pickers:
		pickers[role].color = AppPalette.role_color(role)
