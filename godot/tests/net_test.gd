extends Node
## Teste do multijogador com dois processos na mesma máquina, cada lado jogado por um bot:
##   godot --headless --path godot res://tests/net_test.tscn -- host
##   godot --headless --path godot res://tests/net_test.tscn -- join
## O convidado procura o jogo na rede, liga-se a 127.0.0.1 e no fim compara o que viu
## com o resultado que o anfitrião lhe envia.

const SECONDS := 45.0

var world: World
var role := ""
var brain := BotBrain.new()
var stats := { "snaps": 0, "fx": 0, "max_planes": 0, "max_bullets": 0, "found_host": false }
var _t := 0.0
var _started := false


func _ready() -> void:
	role = "join" if OS.get_cmdline_user_args().has("join") else "host"
	world = World.new()
	add_child(world)
	world.start("demo")
	world.set_physics_process(false)
	world.fx_event.connect(Net.send_fx)
	Net.match_started.connect(_on_match)
	Net.ended.connect(func(reason: String) -> void:
		print("[%s] ligação terminou: %s" % [role, reason])
		_finish())
	Net.snapshot_received.connect(func(snap: Array) -> void:
		stats.snaps += 1
		if world.mode == "remote":
			world.net_sync.push(snap))
	Net.fx_received.connect(func(event: String, args: Array) -> void:
		stats.fx += 1
		if world.mode == "remote":
			world.fx(event, args))
	var info := { "plane": "fighter" if role == "host" else "bomber", "colors": [], "w": 420.0 if role == "host" else 400.0, "name": role }
	if role == "host":
		Net.host_game(info)
		print("[host] à espera: ", Net.status)
	else:
		Net.start_browsing()
		await get_tree().create_timer(2.5).timeout
		stats.found_host = not Net.hosts.is_empty()
		print("[join] jogos encontrados na rede: ", Net.hosts.keys())
		Net.join("127.0.0.1", info)


func _on_match(data: Dictionary) -> void:
	print("[%s] partida: %s" % [role, JSON.stringify(data)])
	Config.W = float(data.w)
	world.start("versus" if role == "host" else "remote", {
		"player_type": World.plane_type(data.planes[0]),
		"bot_type": World.plane_type(data.planes[1]),
		"remote_input": Net.remote_input,
	})
	if role == "host":
		# o lado do anfitrião também é jogado por um bot
		world.sides[0].is_bot = true
		world.sides[0].brain = BotBrain.new()
		Net.world = world
	_started = true


func _physics_process(dt: float) -> void:
	if not _started:
		return
	if role == "join":
		var me := world.sides[1]
		if me.ctrl != null:
			brain.think(me, world, "normal", dt, false)
		Net.send_input(me.input)
		me.input.eject = false
		me.input.bomb = false
	world.step(dt)
	stats.max_planes = maxi(stats.max_planes, world.planes.size())
	stats.max_bullets = maxi(stats.max_bullets, world.bullets.size())
	_t += dt
	if role == "host" and _t > SECONDS:
		_finish()


func _finish() -> void:
	set_physics_process(false)
	var scores := [world.sides[0].score, world.sides[1].score] if world.sides.size() == 2 else []
	print("[%s] pontos %s  %s" % [role, str(scores), JSON.stringify(stats)])
	var ok := true
	if role == "host":
		ok = scores.size() == 2 and scores[0] + scores[1] >= 2
		Net.leave()
	else:
		ok = stats.snaps > SECONDS * 20 and stats.fx > 50 and stats.max_planes == 2 and stats.max_bullets > 0 and scores[0] + scores[1] >= 2
	print("[%s] %s" % [role, "OK" if ok else "FALHOU"])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if ok else 1)
