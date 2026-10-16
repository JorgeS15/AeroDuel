extends Node
## Autoload "Game": definições guardadas, mapa de teclas e tema da interface.

const SETTINGS_PATH := "user://settings.cfg"

var difficulty := "normal"
var sound_on := true
var ui_theme: Theme


func _ready() -> void:
	_setup_input()
	ui_theme = _make_theme()
	_load_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "sound_on", sound_on)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	difficulty = cfg.get_value("game", "difficulty", difficulty)
	sound_on = cfg.get_value("game", "sound_on", sound_on)


func _setup_input() -> void:
	var keys := {
		"turn_left": [KEY_LEFT, KEY_A],
		"turn_right": [KEY_RIGHT, KEY_D],
		"fire": [KEY_SPACE, KEY_J, KEY_Z],
		"eject": [KEY_E, KEY_K, KEY_X],
		"pause": [KEY_P, KEY_ESCAPE],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 9
	var normal := _box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.2))
	var hover := _box(Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.3))
	var pressed := _box(Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.4))
	var focus := _box(Color(0, 0, 0, 0), Color("#ffd23f"))
	focus.draw_center = false
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", normal)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color("#222222"))
	t.set_color("font_hover_pressed_color", "Button", Color("#222222"))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.078, 0.106, 0.2, 0.94), Color(1, 1, 1, 0.14), 7, 10))
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	return t


func _box(bg: Color, border: Color, radius := 5, pad := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 3
	s.content_margin_right = pad + 3
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s
