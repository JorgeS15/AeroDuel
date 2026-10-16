class_name MainMenu
extends CanvasLayer
## Menu principal, por cima de uma demonstração com dois bots.

signal play_pressed

const DIFFICULTY_LABELS := { "facil": "Fácil", "normal": "Normal", "dificil": "Difícil" }

const HELP_TEXT := """[b]Rodar:[/b] ↺ ↻  (teclado: ← → ou A D)
[b]Disparar:[/b] FOGO  (Espaço ou J)
[b]Saltar de paraquedas:[/b] SALTAR  (E ou K)

O avião acelera sozinho. Para descolar, espera que ganhe velocidade e puxa o nariz para cima.
Se subires a direito muito tempo perdes velocidade e [b]entras em perda[/b]: aponta o nariz para baixo para recuperar.
Para aterrar, toca no chão quase na horizontal. Se passares pelo teu hangar, o avião fica reparado.
Avião abatido +1, piloto eliminado +1. Se caíres dentro do avião, o adversário ganha os dois pontos: salta!
No ar guias o paraquedas com ↺ ↻. No chão, o piloto anda com os mesmos botões até ao hangar."""

var _main_panel: PanelContainer
var _help_panel: PanelContainer
var _play_btn: Button


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.theme = Game.ui_theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.043, 0.063, 0.125, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	# painel principal
	_main_panel = PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_main_panel.add_child(box)

	var title := Label.new()
	title.text = "AeroDuel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Abate o avião inimigo. Se fores atingido, salta de paraquedas\ne corre para o teu hangar para ires buscar outro avião!"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 8)
	sub.modulate = Color(1, 1, 1, 0.85)
	box.add_child(sub)

	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for key in DIFFICULTY_LABELS:
		var b := Button.new()
		b.text = DIFFICULTY_LABELS[key]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == Game.difficulty
		b.custom_minimum_size = Vector2(52, 18)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				Game.difficulty = key
				Game.save_settings())
		diff_row.add_child(b)
	box.add_child(diff_row)
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color("#ffd23f")
	pressed_style.set_corner_radius_all(5)
	pressed_style.content_margin_left = 7
	pressed_style.content_margin_right = 7
	for b in diff_row.get_children():
		b.add_theme_stylebox_override("pressed", pressed_style)
		b.add_theme_stylebox_override("hover_pressed", pressed_style)

	_play_btn = Button.new()
	_play_btn.text = "Jogar contra o bot"
	_play_btn.custom_minimum_size = Vector2(0, 26)
	_play_btn.add_theme_font_size_override("font_size", 12)
	var play_style := StyleBoxFlat.new()
	play_style.bg_color = Color("#2f6fd6")
	play_style.border_color = Color("#9cc3ff")
	play_style.set_border_width_all(1)
	play_style.set_corner_radius_all(5)
	_play_btn.add_theme_stylebox_override("normal", play_style)
	_play_btn.add_theme_stylebox_override("hover", play_style)
	_play_btn.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(_play_btn)

	var help_btn := Button.new()
	help_btn.text = "Como se joga"
	help_btn.flat = true
	help_btn.pressed.connect(func() -> void: _show_help(true))
	box.add_child(help_btn)

	root.add_child(_main_panel)
	_center(_main_panel, 250)

	# ajuda
	_help_panel = PanelContainer.new()
	var hbox := VBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	_help_panel.add_child(hbox)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = HELP_TEXT
	text.fit_content = true
	text.custom_minimum_size = Vector2(320, 0)
	text.add_theme_font_size_override("normal_font_size", 8)
	text.add_theme_font_size_override("bold_font_size", 8)
	hbox.add_child(text)
	var back := Button.new()
	back.text = "Voltar"
	back.pressed.connect(func() -> void: _show_help(false))
	hbox.add_child(back)
	root.add_child(_help_panel)
	_center(_help_panel, 340)
	_help_panel.visible = false

	var version := Label.new()
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	version.add_theme_font_size_override("font_size", 6)
	version.modulate = Color(1, 1, 1, 0.6)
	version.position = Vector2(Config.W - 30, Config.H - 12)
	root.add_child(version)


func open() -> void:
	visible = true
	_show_help(false)
	_play_btn.grab_focus()


func close() -> void:
	visible = false


func _show_help(on: bool) -> void:
	_help_panel.visible = on
	_main_panel.visible = not on


func _center(panel: PanelContainer, width: float) -> void:
	panel.custom_minimum_size = Vector2(width, 0)
	var place := func() -> void:
		panel.reset_size()
		panel.position = (Vector2(Config.W, Config.H) - panel.size) * 0.5
	place.call()
	panel.resized.connect(place)
