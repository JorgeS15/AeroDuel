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
No ar guias o paraquedas com ↺ ↻. No chão, o piloto anda com os mesmos botões até ao hangar.
[b]Powerups:[/b] caem caixas de paraquedas; voa contra elas para as apanhar. [b]E[/b] escudo (3 tiros), [b]3[/b] tiro triplo, [b]T[/b] turbo, [b]+[/b] reparação, [b]B[/b] bombas (botão BOMBA ou tecla B)."""

var _main_panel: PanelContainer
var _help_panel: PanelContainer
var _play_btn: Button
var _update_label: Label
var _plane_name: Label
var _plane_desc: Label
var _plane_preview: PlanePreview
var _update_btn: Button


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

	# escolha do avião
	var plane_row := HBoxContainer.new()
	plane_row.alignment = BoxContainer.ALIGNMENT_CENTER
	plane_row.add_theme_constant_override("separation", 6)
	var prev := Button.new()
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(20, 18)
	prev.pressed.connect(func() -> void: _cycle_plane(-1))
	plane_row.add_child(prev)
	_plane_preview = PlanePreview.new()
	plane_row.add_child(_plane_preview)
	var names := VBoxContainer.new()
	names.custom_minimum_size = Vector2(150, 0)
	names.add_theme_constant_override("separation", 0)
	_plane_name = Label.new()
	_plane_name.add_theme_font_size_override("font_size", 10)
	names.add_child(_plane_name)
	_plane_desc = Label.new()
	_plane_desc.add_theme_font_size_override("font_size", 6)
	_plane_desc.modulate = Color(1, 1, 1, 0.8)
	_plane_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_plane_desc.custom_minimum_size = Vector2(150, 0)
	names.add_child(_plane_desc)
	plane_row.add_child(names)
	var next := Button.new()
	next.text = "▶"
	next.custom_minimum_size = Vector2(20, 18)
	next.pressed.connect(func() -> void: _cycle_plane(1))
	plane_row.add_child(next)
	box.add_child(plane_row)
	_refresh_plane()

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

	# versão e atualizações (canto inferior)
	var footer := VBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 1)
	footer.position = Vector2(4, Config.H - 46)
	footer.size = Vector2(Config.W - 8, 44)
	root.add_child(footer)
	_update_btn = Button.new()
	_update_btn.add_theme_font_size_override("font_size", 8)
	_update_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_update_btn.pressed.connect(Updater.open_download)
	var update_style := StyleBoxFlat.new()
	update_style.bg_color = Color("#2e9e4f")
	update_style.set_corner_radius_all(4)
	update_style.content_margin_left = 6
	update_style.content_margin_right = 6
	update_style.content_margin_top = 2
	update_style.content_margin_bottom = 2
	_update_btn.add_theme_stylebox_override("normal", update_style)
	_update_btn.add_theme_stylebox_override("hover", update_style)
	footer.add_child(_update_btn)
	_update_label = Label.new()
	_update_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_update_label.add_theme_font_size_override("font_size", 6)
	_update_label.modulate = Color(1, 1, 1, 0.7)
	footer.add_child(_update_label)
	var version := Label.new()
	version.text = Game.version_text()
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.add_theme_font_size_override("font_size", 6)
	version.modulate = Color(1, 1, 1, 0.7)
	footer.add_child(version)
	Updater.status_changed.connect(_refresh_update)
	_refresh_update()


func open() -> void:
	visible = true
	Updater.check()
	_show_help(false)
	_play_btn.grab_focus()


func _cycle_plane(step: int) -> void:
	var ids: Array = World.PLANE_IDS
	var i := maxi(0, ids.find(Game.plane_choice))
	Game.plane_choice = ids[(i + step + ids.size()) % ids.size()]
	Game.save_settings()
	_refresh_plane()


func _refresh_plane() -> void:
	var t := World.plane_type(Game.plane_choice)
	_plane_name.text = t.display_name
	_plane_desc.text = t.description
	_plane_preview.show_type(t)


func _refresh_update() -> void:
	_update_label.text = Updater.status_text()
	_update_btn.visible = Updater.status == Updater.Status.AVAILABLE
	_update_btn.text = "Atualizar para o build %d" % Updater.latest_build


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
