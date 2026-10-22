extends Node
## Cena principal: liga o mundo, o HUD e o menu, e trata do estado do jogo.

enum State { MENU, PLAYING, PAUSED, OVER }

var state := State.MENU
var world: World
var hud: Hud
var menu: MainMenu
var mission_index := -1      ## missão em curso (-1 = duelo livre)
var _hud_w := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = World.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	_make_hud()
	menu = MainMenu.new()
	add_child(menu)

	menu.duel_pressed.connect(start_duel)
	menu.mission_pressed.connect(start_mission)
	world.game_over.connect(_on_game_over)
	world.mission_finished.connect(_on_mission_finished)
	world.fx_event.connect(Net.send_fx)
	Net.match_started.connect(_on_net_match)
	Net.ended.connect(_on_net_ended)
	Net.over_received.connect(_on_net_over)
	Net.rematch_requested.connect(func() -> void:
		if state == State.OVER and world.mode == "versus":
			Net.start_match())
	Net.snapshot_received.connect(func(snap: Array) -> void:
		if world.mode == "remote":
			world.net_sync.push(snap))
	Net.fx_received.connect(func(event: String, args: Array) -> void:
		if world.mode == "remote":
			world.fx(event, args))
	go_menu()


## O HUD é construído para a largura atual do mundo: volta a ser feito quando ela muda.
func _make_hud() -> void:
	if hud != null:
		world.message.disconnect(hud.show_message)
		hud.queue_free()
	hud = Hud.new()
	hud.world = world
	add_child(hud)
	world.message.connect(hud.show_message)
	hud.pause_pressed.connect(func() -> void: set_paused(true))
	hud.resume_pressed.connect(func() -> void: set_paused(false))
	hud.again_pressed.connect(_play_again)
	hud.retry_pressed.connect(func() -> void: start_mission(mission_index))
	hud.next_mission_pressed.connect(func() -> void: start_mission(mission_index + 1))
	hud.menu_pressed.connect(go_menu)
	hud.eject_pressed.connect(func() -> void: world.player_input.eject = true)
	hud.bomb_pressed.connect(func() -> void: world.player_input.bomb = true)
	_hud_w = Config.W


func _set_world_width(w: float) -> void:
	if is_equal_approx(w, Config.W) and is_equal_approx(w, _hud_w):
		return
	Game.set_world_width(w)
	_make_hud()


func _player_opts() -> Dictionary:
	return {
		"difficulty": Game.difficulty,
		"player_type": Progress.player_plane_type(Game.plane_choice),
		"player_colors": Progress.paint_colors(),
	}


## Duelo livre: todos os aviões disponíveis (com as melhorias compradas).
func start_duel() -> void:
	mission_index = -1
	_begin("solo", _player_opts())


func start_mission(index: int) -> void:
	if index < 0 or index >= Campaign.count() or not Progress.mission_unlocked(index):
		go_menu()
		return
	mission_index = index
	if not Progress.owns_plane(Game.plane_choice):
		Game.plane_choice = "biplane"
	var opts := _player_opts()
	opts.mission = Campaign.mission(index)
	_begin("mission", opts)


func _begin(mode: String, opts: Dictionary) -> void:
	get_tree().paused = false
	world.start(mode, opts)
	menu.close()
	hud.show_playing(true)
	state = State.PLAYING


## Começa uma partida em rede (Net já combinou os aviões, as cores e a largura do mundo).
func _on_net_match(data: Dictionary) -> void:
	mission_index = -1
	_set_world_width(float(data.w))
	var host := Net.role == Net.Role.HOST
	_begin("versus" if host else "remote", {
		"player_type": World.plane_type(data.planes[0]),
		"bot_type": World.plane_type(data.planes[1]),
		"player_colors": data.colors[0],
		"bot_colors": data.colors[1],
		"remote_input": Net.remote_input,
	})
	if host:
		Net.world = world


func _on_net_ended(reason: String) -> void:
	if state != State.MENU:
		go_menu()
	menu.open_wifi(reason)


## Convidado: o anfitrião diz quem ganhou.
func _on_net_over(winner_id: int) -> void:
	if world.mode != "remote":
		return
	world.finished = true
	Sfx.play("win" if winner_id == world.me else "lose")
	_on_game_over(winner_id)


func _play_again() -> void:
	match world.mode:
		"versus":
			Net.start_match()
		"remote":
			Net.request_rematch()
			hud.show_waiting()
		_:
			start_duel()


func go_menu() -> void:
	if Net.is_active():
		Net.leave()
	_set_world_width(Game.native_w)
	get_tree().paused = false
	world.start("demo", { "difficulty": Game.difficulty })
	hud.show_playing(false)
	if mission_index >= 0:
		menu.open_campaign()
	else:
		menu.open()
	state = State.MENU


## No multijogador o jogo não para (o outro telemóvel continua a jogar): só abre o painel.
func set_paused(on: bool) -> void:
	if on and state == State.PLAYING:
		state = State.PAUSED
		get_tree().paused = not world.is_multiplayer()
		hud.show_paused(true)
	elif not on and state == State.PAUSED:
		state = State.PLAYING
		get_tree().paused = false
		hud.show_paused(false)


func _on_game_over(winner_id: int) -> void:
	state = State.OVER
	var won := winner_id == world.me
	var coins := -1   # no multijogador não há moedas
	if world.mode == "versus":
		Net.send_over(winner_id)
	elif not world.is_multiplayer():
		coins = world.kills * Progress.COINS_PER_KILL + (Progress.COINS_DUEL_WIN if won else 0)
		Progress.add_coins(coins)
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if state == State.OVER:
			hud.show_over(won, coins))


func _on_mission_finished(result: Dictionary) -> void:
	state = State.OVER
	var m := Campaign.mission(mission_index)
	var stars := Campaign.stars_for(m, result)
	var coins := Progress.record_mission(m.id, stars, result.kills)
	var has_next := mission_index + 1 < Campaign.count()
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if state == State.OVER:
			hud.show_mission_result(result, stars, Campaign.star_labels(m), coins, has_next))


func _physics_process(_dt: float) -> void:
	# junta teclado e botões táteis nos controlos do jogador (antes de o mundo avançar)
	var inp := world.player_input
	if state == State.PLAYING:
		inp.left = Input.is_action_pressed("turn_left") or hud.btn_left.pressed
		inp.right = Input.is_action_pressed("turn_right") or hud.btn_right.pressed
		inp.fire = Input.is_action_pressed("fire") or hud.btn_fire.pressed
	else:
		inp.left = false
		inp.right = false
		inp.fire = false
	if world.mode == "remote":
		# o convidado não simula: os controlos vão para o anfitrião
		Net.send_input(inp)
		inp.eject = false
		inp.bomb = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("eject") and state == State.PLAYING:
		world.player_input.eject = true
	elif event.is_action_pressed("bomb") and state == State.PLAYING:
		world.player_input.bomb = true
	elif event.is_action_pressed("pause"):
		set_paused(state == State.PLAYING)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			set_paused(true)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# botão "voltar" do Android
			match state:
				State.PLAYING:
					set_paused(true)
				State.PAUSED, State.OVER:
					go_menu()
				State.MENU:
					get_tree().quit()
