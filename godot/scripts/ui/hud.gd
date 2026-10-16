class_name Hud
extends CanvasLayer
## Pontuação, vida, dicas, mensagens, controlos táteis, pausa e fim de jogo.

signal pause_pressed
signal resume_pressed
signal again_pressed
signal menu_pressed
signal eject_pressed
signal bomb_pressed
signal next_mission_pressed
signal retry_pressed

var world: World
var btn_left: TouchButton
var btn_right: TouchButton
var btn_fire: TouchButton
var btn_eject: TouchButton
var btn_bomb: TouchButton

var _root: Control
var _score := []
var _names := []
var _hp: Array[HpPips] = []
var _hint: Label
var _powerups: Label
var _flash: Label
var _flash_t := 0.0
var _touch: Control
var _pause_panel: PanelContainer
var _over_panel: PanelContainer
var _over_title: Label
var _over_score: Label
var _goal: Label
var _result_panel: PanelContainer
var _result_title: Label
var _result_stars: Label
var _result_detail: Label
var _next_btn: Button
var _sound_btn: Button
var _bot_btn: Button


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
	_goal = _label("", 7, Color(1, 1, 1, 0.9))
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.position = Vector2(0, 5)
	_goal.size = Vector2(Config.W, 10)
	_root.add_child(_goal)

	_powerups = _label("", 7, Color.WHITE)
	_powerups.position = Vector2(8, 16)
	_root.add_child(_powerups)

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
	# só nos builds de debug: pôr o bot como alvo passivo, para testar a mecânica
	if OS.is_debug_build():
		_bot_btn = _button("", Vector2(Config.W - 112, 20), Vector2(38, 14))
		_bot_btn.pressed.connect(func() -> void:
			world.bot_passive = not world.bot_passive
			_update_bot_label())

	# controlos táteis
	_touch = Control.new()
	_touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_touch)
	btn_left = _touch_button("↺", Vector2(24, 188), 17, Color.WHITE)
	btn_right = _touch_button("↻", Vector2(64, 188), 17, Color.WHITE)
	btn_eject = _touch_button("SALTAR", Vector2(Config.W - 66, 192), 13, Color("#ffd23f"))
	btn_fire = _touch_button("FOGO", Vector2(Config.W - 26, 184), 20, Color("#ff6b6b"))
	btn_bomb = _touch_button("BOMBA", Vector2(Config.W - 34, 146), 13, Color("#9a8cff"))
	btn_bomb.visible = false
	btn_eject.tapped.connect(func() -> void: eject_pressed.emit())
	btn_bomb.tapped.connect(func() -> void: bomb_pressed.emit())
	_touch.visible = DisplayServer.is_touchscreen_available()

	# pausa
	_pause_panel = _panel(["Pausa", Game.version_text()], [["Continuar", resume_pressed], ["Menu principal", menu_pressed]])
	_pause_panel.get_child(0).get_child(1).add_theme_font_size_override("font_size", 6)
	# fim de jogo
	_over_panel = _panel(["", ""], [["Jogar outra vez", again_pressed], ["Menu principal", menu_pressed]])
	var labels := _over_panel.get_child(0).get_children()
	_over_title = labels[0]
	_over_score = labels[1]
	_over_title.add_theme_font_size_override("font_size", 18)
	# fim de missão
	_result_panel = _panel(["", "", ""], [["Próxima missão", next_mission_pressed], ["Repetir", retry_pressed], ["Campanha", menu_pressed]])
	var rl := _result_panel.get_child(0).get_children()
	_result_title = rl[0]
	_result_stars = rl[1]
	_result_detail = rl[2]
	_result_title.add_theme_font_size_override("font_size", 16)
	_result_stars.add_theme_font_size_override("font_size", 8)
	_result_stars.add_theme_color_override("font_color", Color("#ffd23f"))
	_result_detail.add_theme_font_size_override("font_size", 8)
	_next_btn = rl[3]

	show_playing(false)


func show_playing(on: bool) -> void:
	visible = on
	_update_bot_label()
	_pause_panel.visible = false
	_over_panel.visible = false
	_result_panel.visible = false
	_flash.text = ""
	_flash_t = 0.0


func show_paused(on: bool) -> void:
	_pause_panel.visible = on


func show_over(won: bool, coins: int) -> void:
	_over_title.text = "Ganhaste!" if won else "Perdeste!"
	_over_title.add_theme_color_override("font_color", Config.GOOD if won else Config.BAD)
	_over_score.text = "Tu %d — %d Bot   ·   +%d moedas" % [world.sides[world.me].score, world.sides[1 - world.me].score, coins]
	_over_panel.visible = true
	_over_panel.get_child(0).get_child(2).grab_focus()


## Ecrã de fim de missão. `stars`: [bool x3]; `labels`: texto de cada estrela.
func show_mission_result(result: Dictionary, stars: Array, labels: Array, coins: int, has_next: bool) -> void:
	_result_title.text = "Missão cumprida!" if result.won else "Missão falhada"
	_result_title.add_theme_color_override("font_color", Config.GOOD if result.won else Config.BAD)
	var lines: Array[String] = []
	for i in 3:
		lines.append(("★ " if stars[i] else "☆ ") + labels[i])
	_result_stars.text = "\n".join(lines)
	var detail := "Tempo %s  ·  %d abatidos  ·  +%d moedas" % [Campaign.format_time(result.time), result.kills, coins]
	if not result.won:
		detail = result.reason + "\n" + detail
	_result_detail.text = detail
	_next_btn.visible = result.won and has_next
	_result_panel.visible = true
	(_next_btn if _next_btn.visible else _result_panel.get_child(0).get_child(4)).grab_focus()


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
		_names[i].text = "TU" if i == world.me else ("BOT" if world.mission.is_empty() else "INIMIGO")
		if s.ctrl is Airplane:
			_hp[i].set_hp((s.ctrl as Airplane).hp, (s.ctrl as Airplane).type.max_hp)
		else:
			_hp[i].set_hp(0, 0)
	_hint.text = world.player_hint()
	_goal.text = world.mission_status_text()
	_update_powerups()
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.modulate.a = clampf(_flash_t / 0.3, 0.0, 1.0)


func _update_powerups() -> void:
	var p := world.sides[world.me].ctrl as Airplane
	var parts: Array[String] = []
	if p != null and not p.dead:
		if p.shield > 0:
			parts.append("Escudo %d" % p.shield)
		if p.triple_t > 0.0:
			parts.append("Triplo %ds" % ceili(p.triple_t))
		if p.turbo_t > 0.0:
			parts.append("Turbo %ds" % ceili(p.turbo_t))
		if p.bombs > 0:
			parts.append("Bombas %d" % p.bombs)
	_powerups.text = "  ·  ".join(parts)
	btn_bomb.visible = p != null and p.bombs > 0 and not p.falling


func _update_bot_label() -> void:
	if _bot_btn and world:
		_bot_btn.text = "Bot: alvo" if world.bot_passive else "Bot: ataca"


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
