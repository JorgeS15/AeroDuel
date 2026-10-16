extends Node
## Autoload "Game": definições guardadas, mapa de teclas e tema da interface.

const SETTINGS_PATH := "user://settings.cfg"
const BUILD_INFO_PATH := "res://build.json"   ## escrito pelo CI; não existe em builds locais

var difficulty := "normal"
var plane_choice := "biplane"    ## id do avião escolhido no menu (World.PLANE_IDS)
var sound_on := true
var ui_theme: Theme
## Nos ecrãs táteis os botões ficam numa barra por baixo do jogo, para os dedos
## não taparem o avião. O ecrã lógico passa a ter 216 + BAR_H de altura.
var controls_bar := false
## Versão, n.º do build, canal (latest / pr-N) e commit deste APK.
var build := { "version": "", "build": 0, "channel": "", "commit": "local" }


func _ready() -> void:
	set_controls_bar(DisplayServer.is_touchscreen_available())
	_setup_input()
	_load_build_info()
	ui_theme = _make_theme()
	_load_settings()


## Liga ou desliga a barra de controlos e recalcula a largura do mundo.
## O mundo tem sempre 216 de altura; a largura segue o formato do ecrã (mín. 384).
func set_controls_bar(on: bool) -> void:
	controls_bar = on
	var total_h := Config.H + (Config.BAR_H if on else 0.0)
	get_tree().root.content_scale_size = Vector2i(int(Config.BASE_W), int(total_h))
	var win := Vector2(DisplayServer.window_get_size())
	var aspect := win.x / maxf(win.y, 1.0)
	Config.W = maxf(Config.BASE_W, roundf(aspect * total_h))


## Texto curto para mostrar no ecrã, ex.: "v0.1.0 · build 7 · pr-2 · 81cb40b".
func version_text() -> String:
	var parts := ["v" + str(build.version)]
	if int(build.build) > 0:
		parts.append("build %d" % int(build.build))
	if not str(build.channel).is_empty():
		parts.append(str(build.channel))
	parts.append(str(build.commit))
	if OS.is_debug_build():
		parts.append("debug")
	return " · ".join(parts)


func _load_build_info() -> void:
	build.version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if not FileAccess.file_exists(BUILD_INFO_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(BUILD_INFO_PATH))
	if typeof(data) == TYPE_DICTIONARY:
		for key in data:
			build[key] = data[key]


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "sound_on", sound_on)
	cfg.set_value("game", "plane", plane_choice)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	difficulty = cfg.get_value("game", "difficulty", difficulty)
	sound_on = cfg.get_value("game", "sound_on", sound_on)
	plane_choice = cfg.get_value("game", "plane", plane_choice)


func _setup_input() -> void:
	var keys := {
		"turn_left": [KEY_LEFT, KEY_A],
		"turn_right": [KEY_RIGHT, KEY_D],
		"fire": [KEY_SPACE, KEY_J, KEY_Z],
		"eject": [KEY_E, KEY_K, KEY_X],
		"bomb": [KEY_B, KEY_L],
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
