class_name MainMenu
extends CanvasLayer
## Menu principal (por cima de uma demonstração com dois bots), em páginas:
## início, duelo livre, campanha, jogar com amigos (Wi-Fi), hangar e ajuda.

signal duel_pressed
signal mission_pressed(index: int)

const DIFFICULTY_LABELS := { "facil": "Fácil", "normal": "Normal", "dificil": "Difícil" }

const HELP_TEXT := """[b]Rodar:[/b] ↺ ↻  (teclado: ← → ou A D)   [b]Disparar:[/b] FOGO (Espaço)   [b]Saltar:[/b] SALTAR (E)   [b]Bomba:[/b] BOMBA (B)

O avião acelera sozinho. Para descolar, espera que ganhe velocidade e puxa o nariz para cima. Se subires a direito muito tempo [b]entras em perda[/b]: aponta o nariz para baixo para recuperar. Para aterrar, toca no chão quase na horizontal; se passares pelo teu hangar, o avião fica reparado.
Avião abatido +1, piloto eliminado +1. Se caíres dentro do avião, o adversário ganha os dois pontos: salta! No ar guias o paraquedas com ↺ ↻; no chão, o piloto corre até ao hangar.
[b]Powerups:[/b] voa contra as caixas. [b]E[/b] escudo, [b]3[/b] tiro triplo, [b]T[/b] turbo, [b]+[/b] reparação, [b]B[/b] bombas.
[b]Campanha:[/b] cada missão dá até 3 estrelas e moedas. No [b]hangar[/b] compras aviões, melhorias e pinturas.
[b]Com amigos:[/b] os dois telemóveis na mesma rede Wi-Fi (ou um faz hotspot). Um carrega em [b]Criar jogo[/b]; o outro escolhe o jogo na lista ou escreve o IP que aparece no primeiro."""

var _root: Control
var _pages := {}
var _coins_labels: Array[Label] = []
var _duel_planes: PlaneCarousel
var _campaign_planes: PlaneCarousel
var _hangar_planes: PlaneCarousel
var _mission_list: GridContainer
var _region := 1
var _region_label: Label
var _hangar_body: VBoxContainer
var _update_label: Label
var _update_btn: Button
var _play_btn: Button
var _wifi_planes: PlaneCarousel
var _wifi_status: Label
var _wifi_hosts: VBoxContainer
var _host_btn: Button
var _ip_edit: LineEdit


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.theme = Game.ui_theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.043, 0.063, 0.125, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	_build_home()
	_build_duel()
	_build_campaign()
	_build_hangar()
	_build_wifi()
	_build_help()
	_build_footer()
	Progress.changed.connect(_refresh_all)
	Net.hosts_changed.connect(_refresh_wifi)
	Net.status_changed.connect(_refresh_wifi)
	_show("home")


func open() -> void:
	visible = true
	_show("home")
	Updater.check()


## Abre diretamente a página da campanha (ex.: ao sair de uma missão), na região
## da missão indicada, ou na última região já aberta.
func open_campaign(mission_index := -1) -> void:
	visible = true
	if mission_index >= 0:
		_region = Campaign.mission(mission_index).region
	else:
		_region = 1
		for r in Campaign.REGIONS:
			if Progress.total_stars() >= Progress.region_stars_needed(r) and Progress.mission_unlocked(Campaign.region_missions(r)[0]):
				_region = r
	_show("campaign")


## Abre a página do multijogador, com uma mensagem (ex.: o amigo saiu do jogo).
func open_wifi(message := "") -> void:
	visible = true
	_show("wifi")
	if not message.is_empty():
		_wifi_status.text = message


func _change_region(step: int) -> void:
	var n := Campaign.REGIONS.size()
	_region = (_region - 1 + step + n) % n + 1
	_refresh_missions()


func close() -> void:
	visible = false


# ---------- páginas ----------

func _build_home() -> void:
	var box := _page("home", 240)
	var title := _label("AeroDuel", 24)
	box.add_child(title)
	box.add_child(_label("Abate o avião inimigo. Se fores atingido, salta de paraquedas\ne corre para o teu hangar para ires buscar outro avião!", 7, 0.85))
	box.add_child(_coins_label())
	_play_btn = _big_button("Campanha", Color("#2f6fd6"), func() -> void: _show("campaign"))
	box.add_child(_play_btn)
	box.add_child(_big_button("Duelo livre", Color("#3b4a7a"), func() -> void: _show("duel")))
	box.add_child(_big_button("Jogar com amigos (Wi-Fi)", Color("#2e7d6b"), func() -> void: _show("wifi")))
	var row := _row()
	row.add_child(_button("Hangar", func() -> void: _show("hangar"), 70))
	row.add_child(_button("Como se joga", func() -> void: _show("help"), 90))
	box.add_child(row)


func _build_duel() -> void:
	var box := _page("duel", 270)
	box.add_child(_label("Duelo livre", 16))
	box.add_child(_label("Contra o bot, até 10 pontos. Todos os aviões disponíveis.", 7, 0.85))
	var diff_row := _row()
	var group := ButtonGroup.new()
	for key in DIFFICULTY_LABELS:
		var choose := func() -> void:
			Game.difficulty = key
			Game.save_settings()
		var b := _button(DIFFICULTY_LABELS[key], choose, 52)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == Game.difficulty
		_yellow_when_pressed(b)
		diff_row.add_child(b)
	box.add_child(diff_row)
	_duel_planes = PlaneCarousel.new()
	_duel_planes.only_owned = false
	_duel_planes.selected = Game.plane_choice
	_duel_planes.changed.connect(func(id: String) -> void:
		Game.plane_choice = id
		Game.save_settings())
	box.add_child(_duel_planes)
	box.add_child(_big_button("Jogar", Color("#2f6fd6"), func() -> void: duel_pressed.emit()))
	box.add_child(_back_button())


func _build_campaign() -> void:
	var box := _page("campaign", 340)
	var head := _row()
	var prev := _button("◀", func() -> void: _change_region(-1), 20)
	head.add_child(prev)
	_region_label = _label("", 11)
	_region_label.custom_minimum_size = Vector2(220, 0)
	head.add_child(_region_label)
	head.add_child(_button("▶", func() -> void: _change_region(1), 20))
	box.add_child(head)
	box.add_child(_coins_label())
	_mission_list = GridContainer.new()
	_mission_list.columns = 2
	_mission_list.add_theme_constant_override("h_separation", 8)
	_mission_list.add_theme_constant_override("v_separation", 4)
	box.add_child(_mission_list)
	_campaign_planes = PlaneCarousel.new()
	_campaign_planes.only_owned = true
	_campaign_planes.selected = Game.plane_choice if Progress.owns_plane(Game.plane_choice) else "biplane"
	_campaign_planes.changed.connect(func(id: String) -> void:
		Game.plane_choice = id
		Game.save_settings())
	box.add_child(_campaign_planes)
	box.add_child(_back_button())
	_refresh_missions()


func _build_hangar() -> void:
	var box := _page("hangar", 320)
	var head := _row()
	head.add_child(_label("Hangar", 12))
	head.add_child(_coins_label())
	box.add_child(head)
	_hangar_planes = PlaneCarousel.new()
	_hangar_planes.only_owned = false
	_hangar_planes.show_locks = true
	_hangar_planes.selected = Game.plane_choice
	_hangar_planes.changed.connect(func(_id: String) -> void: _refresh_hangar())
	box.add_child(_hangar_planes)
	_hangar_body = VBoxContainer.new()
	_hangar_body.add_theme_constant_override("separation", 3)
	box.add_child(_hangar_body)
	box.add_child(_back_button())
	_refresh_hangar()


func _build_wifi() -> void:
	var box := _page("wifi", 300)
	box.add_child(_label("Jogar com amigos", 14))
	box.add_child(_label("Liguem os dois telemóveis à mesma rede Wi-Fi (ou um faz hotspot para o outro).\nUm cria o jogo e o outro entra. Até 10 pontos, todos os aviões disponíveis.", 6, 0.8))
	_wifi_planes = PlaneCarousel.new()
	_wifi_planes.only_owned = false
	_wifi_planes.selected = Game.plane_choice
	_wifi_planes.changed.connect(func(id: String) -> void:
		Game.plane_choice = id
		Game.save_settings())
	box.add_child(_wifi_planes)
	_host_btn = _big_button("Criar jogo", Color("#2e9e4f"), _toggle_host)
	box.add_child(_host_btn)
	_wifi_hosts = VBoxContainer.new()
	_wifi_hosts.add_theme_constant_override("separation", 3)
	box.add_child(_wifi_hosts)
	var ip_row := _row()
	ip_row.add_child(_label("Entrar pelo IP:", 7, 0.85))
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.20"
	_ip_edit.custom_minimum_size = Vector2(100, 16)
	_ip_edit.add_theme_font_size_override("font_size", 8)
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _join(_ip_edit.text.strip_edges()))
	ip_row.add_child(_ip_edit)
	ip_row.add_child(_button("Entrar", func() -> void: _join(_ip_edit.text.strip_edges()), 46))
	box.add_child(ip_row)
	_wifi_status = _label("", 7, 1.0, Config.WARN)
	_wifi_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_wifi_status.custom_minimum_size = Vector2(290, 0)
	box.add_child(_wifi_status)
	box.add_child(_back_button())


func _net_info() -> Dictionary:
	return {
		"plane": Game.plane_choice,
		"colors": Progress.paint_colors(),
		"w": Game.native_w,
		"name": OS.get_model_name() if OS.get_model_name() != "GenericDevice" else OS.get_name(),
	}


func _toggle_host() -> void:
	if Net.role == Net.Role.HOST:
		Net.leave()
		Net.start_browsing()
		Net.status = ""
	else:
		Net.host_game(_net_info())
	_refresh_wifi()


func _join(ip: String) -> void:
	if ip.is_empty():
		return
	Net.join(ip, _net_info())
	_refresh_wifi()


func _refresh_wifi() -> void:
	if _wifi_hosts == null:
		return
	var hosting := Net.role == Net.Role.HOST
	_host_btn.text = "Cancelar jogo" if hosting else "Criar jogo"
	_wifi_status.text = Net.status
	for c in _wifi_hosts.get_children():
		c.queue_free()
	if hosting:
		return
	if Net.hosts.is_empty():
		_wifi_hosts.add_child(_label("A procurar jogos nesta rede…", 7, 0.7))
	for ip in Net.hosts:
		var h: Dictionary = Net.hosts[ip]
		var who: String = h.name if not str(h.name).is_empty() else "jogo"
		var b := _big_button("Entrar no jogo de %s  (%s)" % [who, ip], Color("#2f6fd6"), func() -> void: _join(ip))
		if not h.compatible:
			b.text = "%s: versão diferente, atualiza a app" % who
			b.disabled = true
		_wifi_hosts.add_child(b)


func _build_help() -> void:
	var box := _page("help", 350)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = HELP_TEXT
	text.fit_content = true
	text.custom_minimum_size = Vector2(340, 0)
	text.add_theme_font_size_override("normal_font_size", 7)
	text.add_theme_font_size_override("bold_font_size", 7)
	box.add_child(text)
	box.add_child(_back_button())


# ---------- conteúdo dinâmico ----------

func _refresh_all() -> void:
	for l in _coins_labels:
		l.text = "Moedas: %d   ·   Estrelas: %d/%d" % [Progress.coins, Progress.total_stars(), Campaign.count() * 3]
	_refresh_missions()
	_refresh_hangar()
	_campaign_planes.refresh()
	_duel_planes.refresh()
	_wifi_planes.refresh()
	_hangar_planes.refresh()


func _refresh_missions() -> void:
	if _mission_list == null:
		return
	for c in _mission_list.get_children():
		c.queue_free()
	var region: Dictionary = Campaign.REGIONS[_region]
	var need := Progress.region_stars_needed(_region)
	_region_label.text = "Região %d: %s" % [_region, region.name]
	if Progress.total_stars() < need:
		_region_label.text += "   (precisa de %d ★)" % need
	for i in Campaign.region_missions(_region):
		var m := Campaign.mission(i)
		var unlocked := Progress.mission_unlocked(i)
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 0)
		var got: Array = Progress.mission_stars(m.id)
		var stars := ""
		for st in got:
			stars += "★" if st else "☆"
		var b := _button("%d. %s   %s" % [i + 1, m.title, stars if unlocked else "(bloqueada)"], func() -> void: mission_pressed.emit(i), 160)
		b.disabled = not unlocked
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_child(b)
		var locked_text := "Cumpre a missão anterior para abrir."
		if Progress.total_stars() < Progress.region_stars_needed(_region):
			locked_text = "Precisas de %d estrelas para abrir esta região (tens %d)." % [Progress.region_stars_needed(_region), Progress.total_stars()]
		var brief := _label(m.brief if unlocked else locked_text, 6, 0.75, Color.WHITE, false)
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD
		brief.custom_minimum_size = Vector2(160, 0)
		card.add_child(brief)
		_mission_list.add_child(card)


func _refresh_hangar() -> void:
	if _hangar_body == null:
		return
	for c in _hangar_body.get_children():
		c.queue_free()
	var id := _hangar_planes.selected
	if not Progress.owns_plane(id):
		var price: int = Progress.PLANE_PRICES[id]
		var buy := _big_button("Comprar por %d moedas" % price, Color("#2e9e4f"), func() -> void:
			if Progress.buy_plane(id):
				Game.plane_choice = id
				Game.save_settings())
		buy.disabled = Progress.coins < price
		_hangar_body.add_child(buy)
		if Progress.coins < price:
			_hangar_body.add_child(_label("Faltam %d moedas. Ganha-as na campanha e no duelo livre." % (price - Progress.coins), 6, 0.75))
	else:
		for kind in Progress.UPGRADES:
			var u: Dictionary = Progress.UPGRADES[kind]
			var lvl := Progress.upgrade_level(id, kind)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var name_lbl := _label("%s  %s" % [u.name, "■".repeat(lvl) + "□".repeat(Progress.MAX_UPGRADE - lvl)], 8, 1.0, Color.WHITE, false)
			name_lbl.custom_minimum_size = Vector2(110, 0)
			row.add_child(name_lbl)
			var desc := _label(u.desc, 6, 0.7, Color.WHITE, false)
			desc.custom_minimum_size = Vector2(110, 0)
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD
			row.add_child(desc)
			var cost := Progress.upgrade_cost(id, kind)
			var b := _button("Máximo" if cost < 0 else "%d moedas" % cost, func() -> void: Progress.buy_upgrade(id, kind), 60)
			b.disabled = cost < 0 or Progress.coins < cost
			row.add_child(b)
			_hangar_body.add_child(row)
	# pinturas (para todos os aviões)
	var paints := _row()
	paints.add_child(_label("Pintura:", 7, 0.85))
	for pid in Progress.PAINTS:
		var p: Dictionary = Progress.PAINTS[pid]
		var owned := Progress.owned_paints.has(pid)
		var text: String = p.name if owned else "%s %d" % [p.name, p.price]
		var b := _button(text, func() -> void: Progress.buy_or_select_paint(pid), 0)
		b.add_theme_font_size_override("font_size", 6)
		var sb := StyleBoxFlat.new()
		sb.bg_color = p.colors[0]
		sb.border_color = Color("#ffd23f") if Progress.paint == pid else p.colors[1]
		sb.set_border_width_all(2 if Progress.paint == pid else 1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.disabled = not owned and Progress.coins < p.price
		paints.add_child(b)
	_hangar_body.add_child(paints)


func _refresh_update() -> void:
	_update_label.text = Updater.status_text()
	_update_btn.visible = Updater.status == Updater.Status.AVAILABLE
	_update_btn.text = "Atualizar para o build %d" % Updater.latest_build


# ---------- construção ----------

func _show(page: String) -> void:
	for key in _pages:
		_pages[key].visible = key == page
	# só se procuram jogos na rede enquanto a página do multijogador está aberta
	if page == "wifi":
		Net.start_browsing()
		_wifi_planes.selected = Game.plane_choice
	elif not Net.connected:
		Net.leave()
	_refresh_all()
	_refresh_wifi()


func _page(key: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	_root.add_child(panel)
	panel.custom_minimum_size = Vector2(width, 0)
	var place := func() -> void:
		panel.reset_size()
		panel.position = (Vector2(Config.W, Config.H) - panel.size) * 0.5
	panel.resized.connect(place)
	box.resized.connect(place)
	place.call_deferred()
	_pages[key] = panel
	return box


func _label(text: String, size: int, alpha := 1.0, color := Color.WHITE, centered := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.modulate.a = alpha
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _coins_label() -> Label:
	var l := _label("", 8, 1.0, Color("#ffd23f"))
	_coins_labels.append(l)
	return l


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 6)
	return r


func _button(text: String, on_press: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 16)
	b.add_theme_font_size_override("font_size", 8)
	b.pressed.connect(on_press)
	return b


func _big_button(text: String, color: Color, on_press: Callable) -> Button:
	var b := _button(text, on_press)
	b.custom_minimum_size = Vector2(0, 22)
	b.add_theme_font_size_override("font_size", 11)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = color.lightened(0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var off := sb.duplicate() as StyleBoxFlat
	off.bg_color = color.darkened(0.5)
	b.add_theme_stylebox_override("disabled", off)
	return b


func _back_button() -> Button:
	var b := _button("Voltar", func() -> void: _show("home"), 70)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


func _yellow_when_pressed(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ffd23f")
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("hover_pressed", sb)


func _build_footer() -> void:
	var footer := VBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 1)
	footer.position = Vector2(4, Config.H - 46)
	footer.size = Vector2(Config.W - 8, 44)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(footer)
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
	_update_label = _label("", 6, 0.7)
	_update_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_update_label)
	var version := _label(Game.version_text(), 6, 0.7)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(version)
	Updater.status_changed.connect(_refresh_update)
	_refresh_update()


## Seletor de avião ◀ desenho nome ▶. `only_owned`: só os aviões comprados.
class PlaneCarousel:
	extends HBoxContainer
	signal changed(id: String)

	var only_owned := false
	var show_locks := false
	var selected := "biplane"
	var _preview: PlanePreview
	var _name: Label
	var _desc: Label

	func _ready() -> void:
		alignment = BoxContainer.ALIGNMENT_CENTER
		add_theme_constant_override("separation", 6)
		var prev := Button.new()
		prev.text = "◀"
		prev.custom_minimum_size = Vector2(20, 18)
		prev.pressed.connect(func() -> void: _cycle(-1))
		add_child(prev)
		_preview = PlanePreview.new()
		add_child(_preview)
		var names := VBoxContainer.new()
		names.custom_minimum_size = Vector2(150, 0)
		names.add_theme_constant_override("separation", 0)
		_name = Label.new()
		_name.add_theme_font_size_override("font_size", 10)
		names.add_child(_name)
		_desc = Label.new()
		_desc.add_theme_font_size_override("font_size", 6)
		_desc.modulate = Color(1, 1, 1, 0.8)
		_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		_desc.custom_minimum_size = Vector2(150, 0)
		names.add_child(_desc)
		add_child(names)
		var next := Button.new()
		next.text = "▶"
		next.custom_minimum_size = Vector2(20, 18)
		next.pressed.connect(func() -> void: _cycle(1))
		add_child(next)
		refresh()

	func _ids() -> Array:
		if only_owned:
			return World.PLANE_IDS.filter(func(id) -> bool: return Progress.owns_plane(id))
		return World.PLANE_IDS

	func _cycle(step: int) -> void:
		var ids := _ids()
		var i := maxi(0, ids.find(selected))
		selected = ids[(i + step + ids.size()) % ids.size()]
		refresh()
		changed.emit(selected)

	func refresh() -> void:
		if _name == null:
			return
		if not _ids().has(selected):
			selected = _ids()[0]
		var t := World.plane_type(selected)
		var owned := Progress.owns_plane(selected)
		_name.text = t.display_name + ("" if owned or not show_locks else "  (bloqueado)")
		_desc.text = t.description
		_preview.show_type(t)
