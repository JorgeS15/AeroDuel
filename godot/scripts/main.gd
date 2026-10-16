extends Node
## Cena principal: liga o mundo, o HUD e o menu, e trata do estado do jogo.

enum State { MENU, PLAYING, PAUSED, OVER }

var state := State.MENU
var world: World
var hud: Hud
var menu: MainMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = World.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	hud = Hud.new()
	hud.world = world
	add_child(hud)
	menu = MainMenu.new()
	add_child(menu)

	menu.play_pressed.connect(start_game)
	world.message.connect(hud.show_message)
	world.game_over.connect(_on_game_over)
	hud.pause_pressed.connect(func() -> void: set_paused(true))
	hud.resume_pressed.connect(func() -> void: set_paused(false))
	hud.again_pressed.connect(start_game)
	hud.menu_pressed.connect(go_menu)
	hud.eject_pressed.connect(func() -> void: world.player_input.eject = true)
	go_menu()


func start_game() -> void:
	get_tree().paused = false
	world.start("solo", Game.difficulty)
	menu.close()
	hud.show_playing(true)
	state = State.PLAYING


func go_menu() -> void:
	get_tree().paused = false
	world.start("demo", Game.difficulty)
	hud.show_playing(false)
	menu.open()
	state = State.MENU


func set_paused(on: bool) -> void:
	if on and state == State.PLAYING:
		state = State.PAUSED
		get_tree().paused = true
		hud.show_paused(true)
	elif not on and state == State.PAUSED:
		state = State.PLAYING
		get_tree().paused = false
		hud.show_paused(false)


func _on_game_over(winner_id: int) -> void:
	state = State.OVER
	var won := winner_id == world.me
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if state == State.OVER:
			hud.show_over(won))


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("eject") and state == State.PLAYING:
		world.player_input.eject = true
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
