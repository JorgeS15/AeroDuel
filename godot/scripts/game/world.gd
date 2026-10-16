class_name World
extends Node2D
## A simulação do duelo: aviões, pilotos, balas, colisões e pontuação.
## Corre a 60 passos por segundo em _physics_process.

signal message(kind: String, side_id: int)
signal game_over(winner_id: int)

const DEFAULT_PLANE := preload("res://data/planes/biplane.tres")

var mode := "demo"           ## demo (bots no menu) | solo (jogador contra o bot)
var me := 0                  ## lado controlado neste ecrã
var difficulty := "normal"
var time := 0.0
var finished := false
var sides: Array[Side] = []
var planes: Array[Airplane] = []
var pilots: Array[Pilot] = []
var bullets: Array[Bullet] = []
var player_input := InputState.new()
var bot_passive := false      ## modo de teste: o bot voa a direito e não dispara

var background: Background
var fx_layer: FxLayer
var entities: Node2D


func _ready() -> void:
	background = Background.new()
	background.world = self
	add_child(background)
	fx_layer = FxLayer.new()
	fx_layer.world = self
	add_child(fx_layer)
	entities = Node2D.new()
	add_child(entities)


func start(p_mode: String, p_difficulty: String) -> void:
	mode = p_mode
	difficulty = p_difficulty
	me = 0
	time = 0.0
	finished = false
	for child in entities.get_children():
		child.queue_free()
	planes.clear()
	pilots.clear()
	bullets.clear()
	fx_layer.clear()
	player_input.clear()
	var demo := mode == "demo"
	sides = [
		Side.new(0, demo, InputState.new() if demo else player_input, DEFAULT_PLANE),
		Side.new(1, true, InputState.new(), DEFAULT_PLANE),
	]
	for s in sides:
		spawn_plane(s)


func _physics_process(dt: float) -> void:
	step(dt)


func step(dt: float) -> void:
	time += dt

	for s in sides:
		if s.is_bot:
			s.brain.think(s, self, difficulty, dt, bot_passive and mode != "demo")

	for p in planes:
		if not p.dead:
			p.step(dt)
	for pl in pilots:
		if not pl.dead:
			pl.step(dt)

	_step_bullets(dt)
	_collisions()

	# novos aviões
	for s in sides:
		if s.ctrl == null and s.respawn > 0.0:
			s.respawn -= dt
			if s.respawn <= 0.0:
				spawn_plane(s)
		s.input.eject = false

	_remove_dead()
	fx_layer.step(dt)


func _step_bullets(dt: float) -> void:
	for b in bullets:
		b.pos.x = Config.wrap_x(b.pos.x + b.vel.x * dt)
		b.pos.y += b.vel.y * dt
		b.life -= dt
		if b.pos.y >= Config.GROUND:
			b.life = 0.0
			fx("dust", [Vector2(b.pos.x, Config.GROUND)])
			continue
		if b.pos.y < -10.0:
			b.life = 0.0
			continue
		for p in planes:
			if p.dead or p.falling or p.side == b.shooter:
				continue
			if Config.dist2(b.pos, p.position) < 36.0:
				hit_plane(p)
				b.life = 0.0
				break
		if b.life <= 0.0:
			continue
		for pl in pilots:
			if pl.dead or pl.side == b.shooter:
				continue
			if Config.dist2(b.pos, pl.position) < 12.0:
				kill_pilot(pl)
				b.life = 0.0
				break
			if pl.state == Pilot.State.CHUTE and Config.dist2(b.pos, pl.chute_center()) < 40.0:
				tear_chute(pl)
				b.life = 0.0
				break


func _collisions() -> void:
	# aviões contra pilotos do outro lado
	for p in planes:
		if p.dead:
			continue
		for pl in pilots:
			if pl.dead or pl.side == p.side:
				continue
			if Config.dist2(p.position, pl.position) < 36.0:
				kill_pilot(pl)
			elif pl.state == Pilot.State.CHUTE and Config.dist2(p.position, pl.chute_center()) < 49.0:
				tear_chute(pl)
	# avião contra avião
	var alive := planes.filter(func(p: Airplane) -> bool: return not p.dead and not p.falling)
	if alive.size() == 2 and alive[0].side != alive[1].side and Config.dist2(alive[0].position, alive[1].position) < 64.0:
		for p in alive:
			p.hp = 0
			hit_plane(p)


func _remove_dead() -> void:
	for p in planes:
		if p.dead:
			p.queue_free()
	for pl in pilots:
		if pl.dead:
			pl.queue_free()
	planes = planes.filter(func(p: Airplane) -> bool: return not p.dead)
	pilots = pilots.filter(func(pl: Pilot) -> bool: return not pl.dead)
	bullets = bullets.filter(func(b: Bullet) -> bool: return b.life > 0.0)


# ---------- Ações ----------

func spawn_plane(side: Side) -> Airplane:
	var p := Airplane.new()
	p.setup(self, side)
	entities.add_child(p)
	planes.append(p)
	side.ctrl = p
	side.respawn = 0.0
	return p


func fire_bullet(p: Airplane) -> void:
	var dir := Vector2(cos(p.angle), sin(p.angle))
	var b := Bullet.new()
	b.pos = Vector2(Config.wrap_x(p.position.x + dir.x * 8.0), p.position.y + dir.y * 8.0)
	b.vel = dir * (p.type.bullet_speed + p.speed * 0.5)
	b.shooter = p.side
	bullets.append(b)
	fx("shoot", [p.side.id])


func hit_plane(p: Airplane) -> void:
	p.hp -= 1
	p.hit_t = 0.12
	fx("hit", [p.position, p.side.id])
	if p.hp <= 0 and not p.falling:
		p.falling = true
		p.stalled = false
		p.spin = (-1.0 if randf() < 0.5 else 1.0) * randf_range(1.5, 3.0)
		if p.on_ground:
			crash_plane(p)


func crash_plane(p: Airplane) -> void:
	if p.dead:
		return
	p.dead = true
	fx("boom", [Vector2(p.position.x, minf(p.position.y, Config.GROUND - 2.0)), p.side.id])
	if p.manned:
		p.side.ctrl = null
		p.side.respawn = Config.RESPAWN_TIME
		_award(p.side, 2, "plane_crew")
	else:
		_award(p.side, 1, "plane")


func eject(p: Airplane) -> void:
	if not p.manned or p.dead or p.on_ground:
		return
	p.manned = false
	if not p.falling:
		p.falling = true
		p.spin = randf_range(-1.0, 1.0)
	var pilot := Pilot.new()
	var v := Vector2(cos(p.angle), sin(p.angle)) * p.speed * 0.4 + Vector2(0.0, -45.0)
	pilot.setup(self, p.side, p.position + Vector2(0.0, -4.0), v)
	entities.add_child(pilot)
	pilots.append(pilot)
	p.side.ctrl = pilot
	fx("eject", [])


func kill_pilot(pl: Pilot) -> void:
	if pl.dead:
		return
	pl.dead = true
	fx("blood", [pl.position])
	pl.side.ctrl = null
	pl.side.respawn = Config.RESPAWN_TIME
	_award(pl.side, 1, "pilot")


func tear_chute(pl: Pilot) -> void:
	pl.tear_chute()
	fx("tear", [pl.chute_center(), pl.side.id])


func pilot_reached_hangar(pl: Pilot) -> void:
	pl.dead = true
	spawn_plane(pl.side)
	fx("new_plane", [pl.side.id])


func _award(loser: Side, points: int, kind: String) -> void:
	var winner := sides[1 - loser.id]
	winner.score += points
	if mode == "demo":
		if winner.score >= Config.WIN_SCORE:   # a demonstração do menu recomeça sozinha
			for s in sides:
				s.score = 0
		return
	if finished:
		return
	fx("msg", [kind, loser.id])
	if winner.score >= Config.WIN_SCORE:
		finished = true
		_sfx("win" if winner.id == me else "lose")
		game_over.emit(winner.id)


# ---------- Efeitos ----------
## Tudo o que se vê ou ouve num instante passa por aqui. No multiplayer,
## o anfitrião vai reencaminhar estes eventos para o outro telemóvel.
func fx(event: String, args: Array) -> void:
	var live := mode != "demo" and not finished
	match event:
		"boom":
			fx_layer.explosion(args[0])
			_sfx("boom")
			if live and args[1] == me:
				Input.vibrate_handheld(150)
		"hit":
			fx_layer.puff(args[0], Color("#ffe680"), 6, 50.0, 0.25, 1.2, 0.0)
			_sfx("hit")
			if live and args[1] == me:
				Input.vibrate_handheld(40)
		"blood":
			fx_layer.puff(args[0], Color("#b0182b"), 10, 40.0, 0.5, 1.2, 60.0)
			_sfx("hit")
		"tear":
			fx_layer.puff(args[0], Config.TEAM_CHUTE[args[1]], 8, 30.0, 0.6, 1.5, 20.0)
			if live:
				message.emit("tear", args[1])
		"dust":
			fx_layer.puff(args[0], Color("#a58a5c"), 3, 20.0, 0.3, 1.0, 40.0)
		"shoot":
			_sfx("shoot_me" if args[0] == me else "shoot_foe")
		"eject":
			_sfx("eject")
		"chute":
			_sfx("chute")
		"land":
			if args[0] == me:
				_sfx("land")
		"repair":
			if args[0] == me:
				_sfx("repair")
				if live:
					message.emit("repair", args[0])
		"new_plane":
			if live:
				message.emit("new_plane", args[0])
		"msg":
			if live:
				message.emit(args[0], args[1])


func _sfx(name: String) -> void:
	if mode == "demo":
		return
	var player := get_node_or_null("/root/Sfx")
	if player:
		player.play(name)


func emit_smoke(p: Airplane, dt: float) -> void:
	p.smoke_t -= dt
	if p.smoke_t > 0.0 or (p.hp >= p.type.max_hp and not p.falling):
		return
	p.smoke_t = 0.03 if p.falling else (0.07 if p.hp == 1 else 0.16)
	var dark := p.falling or p.hp == 1
	var tail := p.position - Vector2(cos(p.angle), sin(p.angle)) * 6.0
	fx_layer.add_particle(tail, Vector2(randf_range(-4, 4), randf_range(-8, -2)), 1.1,
		Color("#333333") if dark else Color("#999999"), randf_range(2.0, 3.5), -4.0)
	if p.falling and randf() < 0.5:
		fx_layer.add_particle(p.position, Vector2(randf_range(-6, 6), randf_range(-6, 0)), 0.3, Color("#ff8a25"), 2.0, 0.0)


# ---------- Ajudas para o HUD ----------

func player_hint() -> String:
	var s := sides[me]
	var c := s.ctrl
	if c == null:
		return "Novo avião em %d…" % ceili(s.respawn) if s.respawn > 0.0 else ""
	if c is Pilot:
		var pl := c as Pilot
		match pl.state:
			Pilot.State.GROUND:
				return "Corre até ao hangar %s!" % Config.TEAM_NAME[me]
			Pilot.State.CHUTE:
				return "Guia o paraquedas com ↺ ↻"
			_:
				return "O paraquedas rasgou-se!" if pl.torn else ""
	var p := c as Airplane
	if p.falling:
		return "Estás a cair! SALTA!"
	if p.stalled:
		return "Perda de velocidade! Aponta o nariz para baixo"
	if p.on_ground and p.speed < p.type.takeoff_speed:
		return "A ganhar velocidade…"
	if p.on_ground:
		return "Puxa o nariz para cima para descolar"
	return ""


func message_text(kind: String, side_id: int) -> Array:
	var mine := side_id == me
	var foe := "Bot"
	match kind:
		"plane_crew":
			return ["Caíste com o avião! %s +2" % foe, Config.BAD] if mine else ["Avião e piloto inimigos abatidos! +2", Config.GOOD]
		"plane":
			return ["Perdeste o avião! %s +1" % foe, Config.BAD] if mine else ["Avião inimigo destruído! +1", Config.GOOD]
		"pilot":
			return ["O teu piloto foi abatido! %s +1" % foe, Config.BAD] if mine else ["Piloto inimigo eliminado! +1", Config.GOOD]
		"tear":
			return ["Paraquedas rasgado!", Config.WARN] if mine else ["Rasgaste o paraquedas!", Config.WARN]
		"repair":
			return ["Avião reparado!", Config.GOOD] if mine else []
		"new_plane":
			return ["Novo avião!", Config.TEAM_WING[me]] if mine else []
	return []
