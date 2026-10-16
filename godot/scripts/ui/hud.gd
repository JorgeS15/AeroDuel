class_name Hud
extends CanvasLayer
## Pontuação, vida, dicas, mensagens, controlos táteis, pausa e fim de jogo.

signal pause_pressed
signal resume_pressed
signal again_pressed
signal menu_pressed
signal eject_pressed

var world: World
var btn_left: TouchButton
var btn_right: TouchButton
var btn_fire: TouchButton
var btn_eject: TouchButton

var _root: Control
var _score := []
var _names := []
var _hp: Array[HpPips] = []
var _hint: Label
var _flash: Label
var _flash_t := 0.0
var _touch: Control
var _pause_panel: PanelContainer
var _over_panel: PanelContainer
var _over_title: Label
var _over_score: Label
var _sound_btn: Button


func _ready() -> void:
	layer = 1
	_root = Control.new()
	_root.theme = Game.ui_theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# pontuação
	for i in 2:
		var name_lbl := _label("", 12, Config.TEAM_WING[i])
		var score_lbl := _label("0", 12, Color.WHITE)
		_names.append(name_lbl)
		_score.append(score_lbl)
		var pips := HpPips.new()
		_hp.append(pips)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0:
			row.add_child(name_lbl); row.add_child(score_lbl); row.add_child(pips)
			row.position = Vector2(8, 2)
		else:
			row.add_child(pips); row.add_child(score_lbl); row.add_child(name_lbl)
			row.alignment = BoxContainer.ALIGNMENT_END
			row.position = Vector2(Config.W - 128, 2)
			row.size = Vector2(120, 16)
		_root.add_child(row)
	var goal := _label("Primeiro a %d" % Config.WIN_SCORE, 7, Color(1, 1, 1, 0.85))
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.position = Vector2(0, 5)
	goal.size = Vector2(Config.W, 10)
	_root.add_child(goal)

	_hint = _label("", 9, Config.WARN)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, 30)
	_hint.size = Vector2(Config.W, 12)
	_root.add_child(_hint)

	_flash = _label("", 14, Color.WHITE)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.position = Vector2(0, 56)
	_flash.size = Vector2(Config.W, 18)
	_flash.add_theme_constant_override("outline_size", 3)
	_root.add_child(_flash)

	# som e pausa
	_sound_btn = _button("", Vector2(Config.W - 72, 20), Vector2(32, 14))
	_sound_btn.pressed.connect(_toggle_sound)
	_update_sound_label()
	var pause_btn := _button("Pausa", Vector2(Config.W - 38, 20), Vector2(32, 14))
	pause_btn.pressed.connect(func() -> void: pause_pressed.emit())

	# controlos táteis
	_touch = Control.new()
	_touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_touch)
	btn_left = _touch_button("↺", Vector2(24, 188), 17, Color.WHITE)
	btn_right = _touch_button("↻", Vector2(64, 188), 17, Color.WHITE)
	btn_eject = _touch_button("SALTAR", Vector2(318, 192), 13, Color("#ffd23f"))
	btn_fire = _touch_button("FOGO", Vector2(358, 184), 20, Color("#ff6b6b"))
	btn_eject.tapped.connect(func() -> void: eject_pressed.emit())
	_touch.visible = DisplayServer.is_touchscreen_available()

	# pausa
	_pause_panel = _panel(["Pausa"], [["Continuar", resume_pressed], ["Menu principal", menu_pressed]])
	# fim de jogo
	_over_panel = _panel(["", ""], [["Jogar outra vez", again_pressed], ["Menu principal", menu_pressed]])
	var labels := _over_panel.get_child(0).get_children()
	_over_title = labels[0]
	_over_score = labels[1]
	_over_title.add_theme_font_size_override("font_size", 18)

	show_playing(false)


func show_playing(on: bool) -> void:
	visible = on
	_pause_panel.visible = false
	_over_panel.visible = false
	_flash.text = ""
	_flash_t = 0.0


func show_paused(on: bool) -> void:
	_pause_panel.visible = on


func show_over(won: bool) -> void:
	_over_title.text = "Ganhaste!" if won else "Perdeste!"
	_over_title.add_theme_color_override("font_color", Config.GOOD if won else Config.BAD)
	_over_score.text = "Tu %d — %d Bot" % [world.sides[world.me].score, world.sides[1 - world.me].score]
	_over_panel.visible = true
	_over_panel.get_child(0).get_child(2).grab_focus()


func show_message(kind: String, side_id: int) -> void:
	var m := world.message_text(kind, side_id)
	if m.is_empty():
		return
	_flash.text = m[0]
	_flash.add_theme_color_override("font_color", m[1])
	_flash.modulate.a = 1.0
	_flash_t = 1.6


func _process(delta: float) -> void:
	if not visible or world == null or world.sides.is_empty():
		return
	for i in 2:
		var s := world.sides[i]
		_score[i].text = str(s.score)
		_names[i].text = ("TU" if i == world.me else "BOT")
		if s.ctrl is Airplane:
			_hp[i].set_hp((s.ctrl as Airplane).hp, (s.ctrl as Airplane).type.max_hp)
		else:
			_hp[i].set_hp(0, 0)
	_hint.text = world.player_hint()
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.modulate.a = clampf(_flash_t / 0.3, 0.0, 1.0)


func _toggle_sound() -> void:
	Game.sound_on = not Game.sound_on
	Game.save_settings()
	_update_sound_label()


func _update_sound_label() -> void:
	_sound_btn.text = "Som" if Game.sound_on else "Mudo"


# ---------- construção ----------

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 2)
	return l


func _button(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 7)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box: StyleBoxFlat = Game.ui_theme.get_stylebox(state, "Button").duplicate()
		box.content_margin_left = 2
		box.content_margin_right = 2
		box.content_margin_top = 1
		box.content_margin_bottom = 1
		box.bg_color = Color(0, 0, 0, 0.35)
		b.add_theme_stylebox_override(state, box)
	_root.add_child(b)   # só depois de entrar na árvore é que o tema conta para o tamanho
	b.position = pos
	b.size = sz
	return b


func _touch_button(text: String, center: Vector2, radius: float, tint: Color) -> TouchButton:
	var b := TouchButton.new()
	b.label = text
	b.tint = tint
	b.position = center - Vector2(radius, radius)
	b.size = Vector2(radius, radius) * 2.0
	_touch.add_child(b)
	return b


func _panel(texts: Array, buttons: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	for t in texts:
		var l := _label(t, 14 if t == texts[0] else 9, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	for entry in buttons:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(150, 22)
		b.add_theme_font_size_override("font_size", 10)
		var sig: Signal = entry[1]
		b.pressed.connect(func() -> void: sig.emit())
		box.add_child(b)
	_root.add_child(panel)
	panel.reset_size()
	panel.position = (Vector2(Config.W, Config.H) - panel.size) * 0.5
	box.resized.connect(func() -> void:
		panel.reset_size()
		panel.position = (Vector2(Config.W, Config.H) - panel.size) * 0.5)
	return panel


class HpPips:
	extends Control
	var hp := 0
	var max_hp := 0

	func _init() -> void:
		custom_minimum_size = Vector2(20, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_hp(value: int, maximum: int) -> void:
		if value == hp and maximum == max_hp:
			return
		hp = value
		max_hp = maximum
		custom_minimum_size = Vector2(maxi(maximum, 1) * 6, 14)
		queue_redraw()

	func _draw() -> void:
		for i in max_hp:
			var r := Rect2(i * 6, 5, 4.5, 4.5)
			if i < hp:
				draw_rect(r, Color.WHITE)
			else:
				draw_rect(r, Color(1, 1, 1, 0.6), false, 0.8)
