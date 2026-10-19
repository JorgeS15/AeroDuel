class_name World
extends Node2D
## A simulação do duelo: aviões, pilotos, balas, colisões e pontuação.
## Corre a 60 passos por segundo em _physics_process.

signal message(kind: String, side_id: int)
signal game_over(winner_id: int)
## Fim de uma missão da campanha. `result`: won, reason, time, kills, planes_lost, hangar_hp.
signal mission_finished(result: Dictionary)

## Aviões disponíveis, pela ordem em que aparecem no menu (ficheiros em data/planes/).
## São carregados só quando são precisos: com preload, o .tres podia ser lido antes de o
## script PlaneType estar compilado e chegava como um Resource genérico.
const PLANE_IDS := ["biplane", "fighter", "bomber", "triplane"]
static var _plane_cache := {}

var mode := "demo"           ## demo (bots no menu) | solo (duelo livre) | mission (campanha)
var me := 0                  ## lado controlado neste ecrã
var difficulty := "normal"
var time := 0.0
var finished := false
var sides: Array[Side] = []
var planes: Array[Airplane] = []
var pilots: Array[Pilot] = []
var bullets: Array[Bullet] = []
var crates: Array[Crate] = []
var bombs: Array[Bomb] = []
var crate_t := 0.0            ## segundos até cair a próxima caixa
var player_input := InputState.new()
var bot_passive := false      ## modo de teste: o bot voa a direito e não dispara
var powerups_enabled := true

# missão em curso (vazio fora da campanha)
var mission := {}
var kills := 0                ## aviões inimigos destruídos
var planes_lost := 0          ## aviões do jogador perdidos
var balloons_destroyed := 0
var hangar_hp := 0
var balloons: Array[Balloon] = []

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


static func plane_type(id: String) -> PlaneType:
	if not PLANE_IDS.has(id):
		id = "biplane"
	if not _plane_cache.has(id):
		_plane_cache[id] = load("res://data/planes/%s.tres" % id) as PlaneType
	return _plane_cache[id]


static func random_plane_id() -> String:
	return PLANE_IDS.pick_random()


## Começa um jogo novo. `opts` (tudo opcional):
##   difficulty: String, player_type / bot_type: PlaneType (null = ao calhas),
##   player_colors: [fuselagem, asas], mission: Dictionary (ver Campaign)
func start(p_mode: String, opts := {}) -> void:
	mode = p_mode
	mission = opts.get("mission", {})
	difficulty = opts.get("difficulty", "normal")
	me = 0
	time = 0.0
	finished = false
	for child in entities.get_children():
		child.queue_free()
	planes.clear()
	pilots.clear()
	bullets.clear()
	crates.clear()
	bombs.clear()
	balloons.clear()
	crate_t = randf_range(4.0, 7.0)
	fx_layer.clear()
	background.rebuild()
	player_input.clear()
	kills = 0
	planes_lost = 0
	balloons_destroyed = 0
	hangar_hp = int(mission.get("hangar_hp", 0))
	powerups_enabled = mission.get("powerups", true)

	var demo := mode == "demo"
	var p0: PlaneType = opts.get("player_type", null)
	if p0 == null:
		p0 = plane_type(random_plane_id())
	var p1: PlaneType = opts.get("bot_type", null)
	var bot_def: Dictionary = mission.get("bot", {})
	if not bot_def.is_empty():
		difficulty = bot_def.get("difficulty", difficulty)
		p1 = plane_type(bot_def.get("plane", "biplane")).duplicate()
		p1.max_hp += int(bot_def.get("hp_bonus", 0))
	if p1 == null:
		p1 = plane_type(random_plane_id())
	sides = [
		Side.new(0, demo, InputState.new() if demo else player_input, p0),
		Side.new(1, true, InputState.new(), p1),
	]
	sides[0].colors = opts.get("player_colors", [])
	sides[1].colors = bot_def.get("colors", [])
	sides[1].raid = bot_def.get("raid", false)
	for s in sides:
		spawn_plane(s)
	if mission.get("goal", "") == "balloons":
		_spawn_balloons(int(mission.target))


func _physics_process(dt: float) -> void:
	step(dt)


func step(dt: float) -> void:
	time += dt

	for s in sides:
		if s.is_bot:
			var diff := s.difficulty if not s.difficulty.is_empty() else difficulty
			s.brain.think(s, self, diff, dt, bot_passive and mode != "demo")

	for p in planes:
		if not p.dead:
			p.step(dt)
	for pl in pilots:
		if not pl.dead:
			pl.step(dt)

	_step_bullets(dt)
	_step_crates(dt)
	_step_bombs(dt)
	_collisions()

	# novos aviões
	for s in sides:
		if s.ctrl == null and s.respawn > 0.0:
			s.respawn -= dt
			if s.respawn <= 0.0:
				spawn_plane(s)
		s.input.eject = false
		s.input.bomb = false

	for bl in balloons:
		bl.step(dt)
	_remove_dead()
	fx_layer.step(dt)
	if not mission.is_empty() and not finished:
		_check_mission()


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
			if Config.dist2(b.pos, p.position) < p.type.hit_radius * p.type.hit_radius:
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
		if b.life <= 0.0 or b.shooter.id != me:
			continue
		for bl in balloons:
			if not bl.dead and Config.dist2(b.pos, bl.position) < Balloon.HIT_RADIUS * Balloon.HIT_RADIUS:
				_hit_balloon(bl, 1)
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
	# avião do jogador contra balão
	for p in planes:
		if p.dead or p.falling or p.side.id != me:
			continue
		for bl in balloons:
			if not bl.dead and Config.dist2(p.position, bl.position) < 81.0:
				_hit_balloon(bl, 99)
				hit_plane(p)
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
	for c in crates:
		if c.dead:
			c.queue_free()
	crates = crates.filter(func(c: Crate) -> bool: return not c.dead)
	bombs = bombs.filter(func(b: Bomb) -> bool: return not b.exploded)
	for bl in balloons:
		if bl.dead:
			bl.queue_free()
	balloons = balloons.filter(func(bl: Balloon) -> bool: return not bl.dead)


# ---------- Powerups e bombas ----------

func _step_crates(dt: float) -> void:
	if not powerups_enabled:
		return
	crate_t -= dt
	if crate_t <= 0.0:
		crate_t = randf_range(Powerups.SPAWN_MIN, Powerups.SPAWN_MAX)
		if crates.size() < Powerups.MAX_CRATES:
			var c := Crate.new()
			# longe dos hangares, para não cair logo em cima de quem está a descolar
			c.setup(Powerups.KINDS.pick_random(), Config.W * randf_range(0.2, 0.8))
			entities.add_child(c)
			crates.append(c)
	var r2 := Powerups.PICKUP_RADIUS * Powerups.PICKUP_RADIUS
	for c in crates:
		if c.dead:
			continue
		c.step(dt)
		for p in planes:
			if p.dead or p.falling or not p.manned:
				continue
			if Config.dist2(c.position, p.position) < r2:
				c.dead = true
				p.pickup(c.kind)
				fx("pickup", [c.kind, p.side.id, c.position])
				break


func drop_bomb(p: Airplane) -> void:
	p.bombs -= 1
	var b := Bomb.new()
	b.pos = p.position + Vector2(0.0, 4.0)
	b.vel = p.velocity() * 0.8
	b.shooter = p.side
	bombs.append(b)
	fx("bomb_drop", [p.side.id])


func _step_bombs(dt: float) -> void:
	for b in bombs:
		b.vel.y += Config.GRAVITY * dt
		b.vel.x *= 1.0 - 0.3 * dt
		b.pos.x = Config.wrap_x(b.pos.x + b.vel.x * dt)
		b.pos.y += b.vel.y * dt
		var hit := b.pos.y >= Config.GROUND - 1.0
		for p in planes:
			if not hit and not p.dead and p.side != b.shooter and Config.dist2(b.pos, p.position) < 64.0:
				hit = true
		if hit:
			_explode(b)


func _explode(b: Bomb) -> void:
	b.exploded = true
	var at := Vector2(b.pos.x, minf(b.pos.y, Config.GROUND - 2.0))
	fx("boom", [at, -1])
	var r2 := Powerups.BOMB_RADIUS * Powerups.BOMB_RADIUS
	for p in planes:
		if p.dead or p.side == b.shooter or Config.dist2(at, p.position) > r2:
			continue
		for i in Powerups.BOMB_DAMAGE:
			if not p.dead and not p.falling:
				hit_plane(p)
	for pl in pilots:
		if not pl.dead and pl.side != b.shooter and Config.dist2(at, pl.position) < r2:
			kill_pilot(pl)
	if b.shooter.id == me:
		for bl in balloons:
			if not bl.dead and Config.dist2(at, bl.position) < r2:
				_hit_balloon(bl, 99)
	# bomba inimiga sobre o hangar do jogador (missões de defesa)
	if hangar_hp > 0 and b.shooter.id != me and at.y > Config.GROUND - 30.0 \
			and absf(Config.dx_wrap(at.x, Config.hangar_x(me))) < 18.0:
		hangar_hp -= 1
		fx("hangar_hit", [hangar_hp])


# ---------- Ações ----------

func spawn_plane(side: Side) -> Airplane:
	var p := Airplane.new()
	p.setup(self, side)
	entities.add_child(p)
	planes.append(p)
	side.ctrl = p
	side.respawn = 0.0
	if side.raid:
		p.bombs = 99    # bombardeiro de ataque ao hangar: bombas sem fim
	return p


func fire_bullet(p: Airplane) -> void:
	var spread := [0.0]
	if p.triple_t > 0.0:
		spread = [0.0, -Powerups.TRIPLE_SPREAD, Powerups.TRIPLE_SPREAD]
	for d in spread:
		_spawn_bullet(p, p.angle + d, 8.0 * p.type.draw_scale, p.type.bullet_speed + p.speed * 0.5)
	if p.type.rear_gun:
		_spawn_bullet(p, p.angle + PI, 8.0 * p.type.draw_scale, p.type.bullet_speed - p.speed * 0.5)
	fx("shoot", [p.side.id])


func _spawn_bullet(p: Airplane, a: float, offset: float, spd: float) -> void:
	var dir := Vector2(cos(a), sin(a))
	var b := Bullet.new()
	b.pos = Vector2(Config.wrap_x(p.position.x + dir.x * offset), p.position.y + dir.y * offset)
	b.vel = dir * spd
	b.shooter = p.side
	bullets.append(b)


func hit_plane(p: Airplane) -> void:
	if p.shield > 0:
		p.shield -= 1
		fx("shield_hit", [p.position, p.side.id])
		return
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
	if kind.begins_with("plane"):
		if loser.id == me:
			planes_lost += 1
		else:
			kills += 1
	fx("msg", [kind, loser.id])
	if mode == "solo" and winner.score >= Config.WIN_SCORE:
		finished = true
		_sfx("win" if winner.id == me else "lose")
		game_over.emit(winner.id)


# ---------- Missões ----------

func _spawn_balloons(n: int) -> void:
	for i in n:
		var bl := Balloon.new()
		# espalhados pelo lado inimigo do mapa, a alturas diferentes
		var x := Config.W * lerpf(0.35, 0.85, (i + 0.5) / n) + randf_range(-10, 10)
		bl.setup(Vector2(x, randf_range(55.0, 135.0)))
		entities.add_child(bl)
		balloons.append(bl)


func _hit_balloon(bl: Balloon, damage: int) -> void:
	bl.hp -= damage
	bl.hit_t = 0.12
	if bl.hp > 0:
		fx("hit", [bl.position, -1])
		return
	bl.dead = true
	balloons_destroyed += 1
	fx("boom", [bl.position, -1])
	fx("msg", ["balloon", 1 - me])


func _check_mission() -> void:
	var target := int(mission.get("target", 1))
	var done := false
	match mission.get("goal", ""):
		"kills":
			done = kills >= target
		"balloons":
			done = balloons_destroyed >= target
		"score":
			done = sides[me].score >= target
	if done:
		_finish_mission(true, "")
	elif mission.has("lose_bot_score") and sides[1 - me].score >= int(mission.lose_bot_score):
		_finish_mission(false, "O inimigo chegou a %d pontos." % int(mission.lose_bot_score))
	elif mission.has("time_limit") and time >= float(mission.time_limit):
		_finish_mission(false, "O tempo acabou.")
	elif mission.has("hangar_hp") and hangar_hp <= 0:
		_finish_mission(false, "O teu hangar foi destruído.")


func _finish_mission(won: bool, reason: String) -> void:
	finished = true
	_sfx("win" if won else "lose")
	mission_finished.emit({
		"won": won, "reason": reason, "time": time, "kills": kills,
		"planes_lost": planes_lost, "hangar_hp": hangar_hp,
	})


## Texto curto do objetivo para o HUD, ex.: "Abatidos 1/3 · Inimigo 2/5 · 1:12".
func mission_status_text() -> String:
	if mission.is_empty():
		return "Primeiro a %d" % Config.WIN_SCORE
	var target := int(mission.get("target", 1))
	var parts: Array[String] = []
	match mission.get("goal", ""):
		"kills":
			parts.append("Abatidos %d/%d" % [kills, target])
		"balloons":
			parts.append("Balões %d/%d" % [balloons_destroyed, target])
		"score":
			parts.append("Pontos %d/%d" % [sides[me].score, target])
	if mission.has("lose_bot_score"):
		parts.append("Inimigo %d/%d" % [sides[1 - me].score, int(mission.lose_bot_score)])
	if mission.has("hangar_hp"):
		parts.append("Hangar %d/%d" % [hangar_hp, int(mission.hangar_hp)])
	if mission.has("time_limit"):
		parts.append("Resta " + Campaign.format_time(maxf(0.0, float(mission.time_limit) - time)))
	else:
		parts.append(Campaign.format_time(time))
	return "  ·  ".join(parts)


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
		"pickup":
			fx_layer.puff(args[2], Powerups.info(args[0]).color, 10, 35.0, 0.5, 1.4, 0.0)
			if args[1] == me:
				_sfx("repair")
			if live:
				message.emit("pickup:" + args[0], args[1])
		"shield_hit":
			fx_layer.puff(args[0], Color("#5ec8ff"), 8, 40.0, 0.3, 1.2, 0.0)
			_sfx("hit")
		"bomb_drop":
			_sfx("eject")
		"hangar_hit":
			Input.vibrate_handheld(80)
			if live:
				message.emit("hangar_hit", me)


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
	var foe := "Bot" if mission.is_empty() else "Inimigo"
	if kind == "balloon":
		return ["Balão destruído! %d/%d" % [balloons_destroyed, int(mission.get("target", 0))], Config.GOOD]
	if kind == "hangar_hit":
		return ["O hangar foi atingido! (%d/%d)" % [hangar_hp, int(mission.get("hangar_hp", 0))], Config.BAD]
	if kind.begins_with("pickup:"):
		var pname: String = Powerups.info(kind.substr(7)).name
		return ["%s!" % pname, Powerups.info(kind.substr(7)).color] if mine else ["%s apanhou: %s" % [foe, pname], Config.WARN]
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
