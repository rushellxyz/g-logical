extends RefCounted

const NAMES := ["Default", "Light", "Midnight", "Darcula", "IntelliJ Light", "High Contrast", "Nord"]
const COLORS := {
	"111722": ["dce3ed", "080d18"],
	"151c29": ["f4f6fa", "0c1222"],
	"15271f": ["edf5ee", "0b201b"],
	"542b2b": ["fff0ef", "29172e"],
	"202a3a": ["dce2eb", "1a2440"],
	"28543f": ["cedfce", "163c35"],
	"a34c4c": ["eed3d0", "50304f"],
	"202b3d": ["e6ebf3", "121b30"],
	"34445d": ["d6deeb", "202d4b"],
	"405571": ["c2d1e6", "2c3e65"],
	"4875a5": ["a7c6ed", "425da0"],
	"f1f5fa": ["24344c", "e1e8ff"],
	"f2f5fb": ["182943", "edf0ff"],
	"95a5bd": ["586b85", "92a1c9"],
	"aab8cb": ["52647c", "a1b1d5"],
	"29364b": ["e1e8f3", "1c2947"],
	"3d628b": ["b6d0ee", "3d5487"],
	"344963": ["cbd8e9", "27395d"],
	"485b75": ["8d9fb7", "40547f"],
	"77a9d8": ["3676b7", "89a3ee"],
	"f5f7fb": ["22334d", "edf0ff"],
	"c5d0df": ["475b76", "b8c5e6"],
	"d8e1ee": ["3c526f", "ccd6ef"],
	"182334": ["f4f7fb", "121c33"],
	"536b89": ["9aaec7", "4b5d89"],
	"f1d28c": ["79540d", "f0ce88"],
	"ffe7a3": ["72531b", "f4d59d"],
	"ffe08a": ["865b0a", "f4cd78"],
	"9aa8b8": ["60718a", "8b9dbf"],
	"68778e": ["889ab1", "57698f"],
	"61d49a": ["218657", "65ddc0"],
	"f0c15b": ["a37112", "efc775"],
	"4b596e": ["788da8", "56688d"],
	"99752c": ["9c6c18", "d1ae65"],
	"895b29": ["987034", "9c7e53"],
	"a47438": ["bc852e", "d0b477"],
	"59401f": ["705024", "594a37"],
	"6d5028": ["805a22", "736347"],
	"f28b82": ["c54545", "fa8ba8"],
	"8bc5f5": ["377dbd", "a1b2ff"],
	"6ca9e8": ["4488c7", "829cf0"],
	"3b2d49": ["e9ddf1", "302440"],
	"5a426e": ["d0b6e5", "674c85"],
	"3d2d50": ["e4dcf2", "2b244b"],
	"563d70": ["cbb6e6", "5b4b86"],
	"51452d": ["f1e7c9", "3c3328"],
	"806d3d": ["e0cb92", "72613c"],
	"394a68": ["dce7f7", "273554"],
	"5476a8": ["b9cff0", "4b5e98"],
	"514c32": ["ede9ce", "393827"],
	"827546": ["ddd29d", "70673d"],
	"42566f": ["c5d5e9", "35486d"],
	"647b99": ["8198b5", "5c719a"],
	"434443": ["dedfdb", "303539"],
	"9ca9a0": ["69786b", "879e97"],
	"71c28b": ["328651", "64c6a2"],
	"486b55": ["b9d7c4", "2d594d"],
	"385e58": ["a8d1c6", "294f50"],
	"963e45": ["efb8bd", "80354f"],
	"b54c54": ["eaa0aa", "a44665"],
	"752e35": ["dc939e", "61273f"],
	"3d7655": ["aad5b8", "2e685b"],
	"854343": ["e3b0b0", "713a57"]
}

const ROLES := {
	"background": ["Window background", "111722"],
	"canvas": ["Canvas", "151c29"],
	"grid": ["Grid", "202a3a"],
	"panel": ["Panels and inputs", "202b3d", "182334"],
	"button": ["Buttons", "34445d"],
	"hover": ["Button hover", "405571"],
	"selection": ["Selected elements", "4875a5", "3d628b", "5476a8", "5a426e", "563d70", "806d3d", "827546"],
	"text": ["Text", "f1f5fa", "f2f5fb", "f5f7fb"],
	"muted_text": ["Secondary text", "95a5bd", "aab8cb", "c5d0df", "d8e1ee", "9aa8b8"],
	"gate": ["Gate body", "29364b", "42566f"],
	"gate_header": ["Gate header", "344963"],
	"border": ["Borders and inactive ports", "485b75", "536b89", "647b99", "9ca9a0", "68778e"],
	"accent": ["Accent and selection outline", "77a9d8", "8bc5f5", "6ca9e8"],
	"wire": ["Wires", "4b596e", "895b29", "59401f"],
	"wire_active": ["Active wires", "99752c", "a47438", "6d5028"],
	"success": ["Success and active inputs", "61d49a", "71c28b", "39ff14"],
	"warning": ["Values and active outputs", "f0c15b", "ffe08a", "f1d28c", "ffe7a3"],
	"error": ["Error and selected wires", "f28b82"],
	"physical_canvas": ["Physical mode canvas", "15271f"],
	"physical_grid": ["Physical mode grid", "28543f"],
	"foundry_canvas": ["Foundry canvas", "542b2b"],
	"foundry_grid": ["Foundry grid", "a34c4c"],
	"custom_gate": ["Custom gates", "3b2d49", "3d2d50"],
	"comment": ["Comments", "51452d", "514c32"],
	"clock": ["Clock gates", "394a68"],
	"tile": ["Physical tiles", "434443"],
	"positive_button": ["Export and physical mode buttons", "486b55", "385e58", "3d7655"],
	"negative_button": ["Reset and Foundry buttons", "963e45", "b54c54", "752e35", "854343"]
}
const PRESETS := {
	"Midnight": ["090710", "100c1c", "2a1d3d", "20152e", "322042", "49305e", "653d8c", "f3eaff", "b7a2ce", "291d3b", "3e2854", "6c5085", "d799ff", "8b6bae", "79e4dc", "79e4bd", "ffd493", "ff7da8", "0b201d", "21483f", "261026", "54274e", "38204e", "3d3026", "23374b", "34313f", "28584e", "773c58"],
	"Darcula": ["252526", "2b2b2b", "3b3b3b", "3c3f41", "4b5052", "5c6164", "365880", "e3e3e3", "a9a9a9", "3c3f41", "4b5052", "6a7075", "cc7832", "80858a", "ffc66d", "6aab73", "ffc66d", "f07878", "29332e", "3e5145", "382c2c", "5b4040", "493d52", "4d4738", "354450", "454846", "42634a", "784447"],
	"IntelliJ Light": ["e4e7eb", "ffffff", "e7e9ee", "f2f2f2", "e5e7eb", "d4e2f6", "b8d4f5", "202124", "626b78", "edf1f7", "dbe4f0", "929dab", "3574f0", "73849a", "aa6800", "24854b", "8a5b00", "c73636", "f0f7f0", "d7e6d7", "fff2f0", "efd8d4", "ede4f5", "fff4cf", "dfeaf9", "e1e4df", "c4dfca", "f0c6c6"],
	"High Contrast": ["000000", "000000", "343434", "080808", "151515", "303030", "174c76", "ffffff", "d1d1d1", "101010", "242424", "bdbdbd", "00d8ff", "ffffff", "ffff00", "00ff80", "ffff00", "ff6161", "001b0c", "356148", "25000c", "75404d", "210c30", "302800", "092530", "242424", "145e30", "7a2020"],
	"Nord": ["242933", "2e3440", "3b4252", "3b4252", "434c5e", "4c566a", "506987", "eceff4", "b4bfd0", "3b4252", "434c5e", "66788f", "88c0d0", "7c90ab", "ebcb8b", "a3be8c", "ebcb8b", "bf616a", "2d3b38", "46594e", "3e303e", "664b60", "483d53", "494536", "35465b", "41484b", "4b6557", "73454f"]
}

static var custom_themes: Array[Dictionary] = []
static var _source_roles: Dictionary = {}

static func theme_names() -> Array:
	var names: Array = NAMES.duplicate()
	for custom in custom_themes:
		names.append(custom["name"])
	return names

static func is_custom() -> bool:
	return selected >= NAMES.size() and selected < NAMES.size() + custom_themes.size()

static func source_role(key: String) -> String:
	if _source_roles.is_empty():
		for role in ROLES:
			for index in range(1, ROLES[role].size()):
				_source_roles[ROLES[role][index]] = role
	return _source_roles.get(key, "")

static func role_color(role: String) -> Color:
	if is_custom():
		return Color(custom_themes[selected - NAMES.size()]["colors"][role])
	if selected == 0:
		return Color(ROLES[role][1])
	if selected == 1:
		var key: String = ROLES[role][1]
		return Color(COLORS[key][0]) if COLORS.has(key) else Color(key)
	return Color(PRESETS[NAMES[selected]][ROLES.keys().find(role)])

static func snapshot_colors() -> Dictionary:
	var colors := {}
	for role in ROLES:
		colors[role] = role_color(role).to_html(false)
	return colors

static func theme_id() -> String:
	return custom_themes[selected - NAMES.size()]["id"] if is_custom() else NAMES[selected]

static func restore_theme(id: String, legacy_index: int) -> void:
	selected = clampi(legacy_index, 0, NAMES.size() - 1)
	for index in range(NAMES.size()):
		if NAMES[index] == id:
			selected = index
			return
	for index in range(custom_themes.size()):
		if custom_themes[index]["id"] == id:
			selected = NAMES.size() + index
			return

static var selected := 0

static func color(hex: String, alpha := 1.0) -> Color:
	var result := map_color(Color(hex))
	result.a = alpha
	return result

static func map_color(original: Color, fallback := false) -> Color:
	if selected == 0:
		return original
	var key := original.to_html(false)
	var result := original
	if selected == 1:
		if COLORS.has(key):
			result = Color(COLORS[key][0])
		elif fallback:
			result = Color.from_hsv(original.h, original.s * 0.35, clampf(1.0 - original.v * 0.8, 0.12, 0.98))
	else:
		var role := source_role(key)
		if not role.is_empty():
			result = role_color(role)
		elif fallback:
			if original.s > 0.3 and original.v > 0.4:
				result = role_color("accent")
			elif original.v > 0.65:
				result = role_color("text")
			else:
				result = role_color("panel").lerp(role_color("button"), original.v)
	result.a = original.a
	return result

static func recolor_style(style: StyleBoxFlat, fallback := false) -> void:
	for property in ["bg_color", "border_color", "shadow_color"]:
		var key: String = "palette_original_" + property
		if not style.has_meta(key):
			style.set_meta(key, style.get(property))
		style.set(property, map_color(style.get_meta(key), fallback))

static func make_ui_theme() -> Theme:
	if selected == 0:
		return null
	var theme: Theme = ThemeDB.get_default_theme().duplicate(true)
	for type in theme.get_type_list():
		for name in theme.get_color_list(type):
			theme.set_color(name, type, map_color(theme.get_color(name, type), true))
		for name in theme.get_stylebox_list(type):
			var style := theme.get_stylebox(name, type)
			if style is StyleBoxFlat:
				recolor_style(style, true)
	return theme

static func apply_to_tree(node: Node, theme: Theme) -> void:
	if node is Control or node is Window:
		node.theme = theme
		for property in node.get_property_list():
			var name: String = property["name"]
			if name.begins_with("theme_override_styles/"):
				var style = node.get(name)
				if style is StyleBoxFlat:
					recolor_style(style)
			elif name.begins_with("theme_override_colors/"):
				var value = node.get(name)
				if value is Color:
					var key := name.replace("/", "_")
					if not node.has_meta(key):
						node.set_meta(key, value)
					var original: Color = node.get_meta(key)
					node.set(name, map_color(original))
		if node is Button:
			for name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
				node.add_theme_color_override(name, color("#f1f5fa") if selected != 0 else Color.WHITE)
	for child in node.get_children():
		apply_to_tree(child, theme)
