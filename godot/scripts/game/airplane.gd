class_name Airplane
extends Node2D
## Um avião: física de voo, tiro e desenho.

var world: World
var side: Side
var nid := 0              ## identificador para o multijogador
var type: PlaneType

var angle := 0.0          ## 0 = para a direita; positivo roda no sentido dos ponteiros do relógio
var speed := 0.0
var fall_vy := 0.0        ## queda extra quando está em perda ou a cair
var hp := 3
var on_ground := true
var stalled := false
var falling := false      ## abatido ou abandonado: já não obedece aos controlos
var manned := true
var dead := false
var cooldown := 0.4
var spin := 0.0
var smoke_t := 0.0
var hit_t := 0.0
var prop := 0.0
# powerups ativos
var shield := 0           ## tiros que ainda absorve
var triple_t := 0.0       ## segundos de tiro triplo
var turbo_t := 0.0        ## segundos de turbo
var bombs := 0
var bomb_cd := 0.0        ## tempo mínimo entre bombas
## Orientação do desenho: 1 = normal, -1 = espelhado (fica direito quando o avião
## descola para a esquerda). Muda só no chão; `roll` faz a transição aos poucos.
var upright := 1.0
var roll := 1.0

const ROLL_SPEED := 9.0          ## unidades de `roll` por segundo (~0,2 s por meio-tonneau)


func setup(p_world: World, p_side: Side) -> void:
	world = p_world
	side = p_side
	type = side.plane_type
	hp = type.max_hp
	var right := side.id == 0
	position = Vector2(Config.hangar_x(side.id) + (8.0 if right else -8.0), Config.PLANE_Y)
	angle = 0.0 if right else PI
	upright = 1.0 if right else -1.0
	roll = upright


## Os controlos que este avião obedece, ou null se ninguém o pilota.
func controls() -> InputState:
	return side.input if manned and side.ctrl == self else null


func step(dt: float) -> void:
	var inp := controls()
	var flying := inp != null and not falling

	hit_t = maxf(0.0, hit_t - dt)
	triple_t = maxf(0.0, triple_t - dt)
	turbo_t = maxf(0.0, turbo_t - dt)
	cooldown -= dt
	bomb_cd -= dt
	if flying:
		prop += dt * 45.0

	# rotação
	if flying:
		var turn := (1.0 if inp.right else 0.0) - (1.0 if inp.left else 0.0)
		if stalled:
			turn *= 0.4
		angle += turn * turn_rate() * dt
	if falling:
		angle += spin * dt
	angle = wrapf(angle, -PI, PI)

	# velocidade: motor - atrito + gravidade ao longo da trajetória
	var engine := thrust() if flying else 0.0
	var gravity_along := 0.0 if on_ground else Config.GRAVITY * sin(angle)
	speed += (engine - type.drag * speed + gravity_along) * dt
	if on_ground and not flying:
		speed -= 30.0 * dt
	speed = maxf(0.0, speed)

	if on_ground:
		# no chão só se pode levantar o nariz, e só com velocidade suficiente
		var level := 0.0 if cos(angle) >= 0.0 else PI
		if sin(angle) < -0.02 and speed >= type.takeoff_speed:
			on_ground = false
		else:
			angle = level
			position.y = Config.PLANE_Y
		# reparação ao passar pelo próprio hangar
		if manned and hp < type.max_hp and absf(Config.dx_wrap(position.x, Config.hangar_x(side.id))) < 16.0:
			hp = type.max_hp
			world.fx("repair", [side.id])
	elif not falling:
		if not stalled and speed < type.stall_speed:
			stalled = true
		if stalled:
			# perda: o avião cai e o nariz desce sozinho
			fall_vy = minf(fall_vy + Config.GRAVITY * 0.8 * dt, 70.0)
			var d := Config.ang_diff(angle, PI / 2.0)
			angle = wrapf(angle + signf(d) * minf(absf(d), 1.5 * dt), -PI, PI)
			if speed > type.stall_speed + 12.0 and sin(angle) > 0.4:
				stalled = false
		else:
			fall_vy = maxf(0.0, fall_vy - 50.0 * dt)
	else:
		fall_vy = minf(fall_vy + Config.GRAVITY * dt, 110.0)

	# movimento
	position.x = Config.wrap_x(position.x + cos(angle) * speed * dt)
	if not on_ground:
		position.y += sin(angle) * speed * dt + fall_vy * dt
		position.x = Config.wrap_x(position.x + world.wind * dt)

	# teto
	if position.y < 6.0:
		position.y = 6.0
		if not falling:
			stalled = true
			speed = minf(speed, type.stall_speed - 4.0)

	# contacto com o chão: aterrar ou despenhar
	if not on_ground and position.y >= Config.PLANE_Y:
		if not falling and not stalled and fall_vy < 20.0 and absf(sin(angle)) < 0.3:
			on_ground = true
			position.y = Config.PLANE_Y
			angle = 0.0 if cos(angle) >= 0.0 else PI
			world.fx("land", [side.id])
		else:
			world.crash_plane(self)
			return

	world.emit_smoke(self, dt)

	if flying and inp.fire and cooldown <= 0.0:
		cooldown = type.fire_cooldown
		world.fire_bullet(self)

	if flying and inp.bomb and bombs > 0 and not on_ground and bomb_cd <= 0.0:
		bomb_cd = 0.7
		world.drop_bomb(self)

	if inp != null and inp.eject:
		world.eject(self)

	_update_roll(inp, dt)
	queue_redraw()


## Orientação do desenho. No ar o avião fica como o jogador o deixa: se fizer meio
## looping, continua a voar de costas até rodar outra vez. Só no chão (descolagem e
## aterragem) é que fica sempre direito; a mudança é animada como um tonneau curto.
func _update_roll(_inp: InputState, dt: float) -> void:
	if on_ground:
		upright = 1.0 if cos(angle) >= 0.0 else -1.0
	roll = move_toward(roll, upright, ROLL_SPEED * dt)


func thrust() -> float:
	return type.thrust * (Powerups.TURBO_THRUST if turbo_t > 0.0 else 1.0)


func turn_rate() -> float:
	return type.turn_rate * (Powerups.TURBO_TURN if turbo_t > 0.0 else 1.0)


## Aplica um powerup apanhado.
func pickup(kind: String) -> void:
	match kind:
		"shield":
			shield = Powerups.SHIELD_HITS
		"triple":
			triple_t = Powerups.TRIPLE_TIME
		"turbo":
			turbo_t = Powerups.TURBO_TIME
		"repair":
			hp = type.max_hp
		"bomb":
			bombs = mini(bombs + Powerups.BOMBS_PER_PICKUP, Powerups.MAX_BOMBS)


func velocity() -> Vector2:
	if on_ground:
		return Vector2(cos(angle) * speed, 0.0)
	return Vector2(cos(angle) * speed, sin(angle) * speed + fall_vy)


func _draw() -> void:
	var body: Color = Color.WHITE if hit_t > 0.0 else side.body_color()
	var wing: Color = Color.WHITE if hit_t > 0.0 else side.wing_color()
	# `roll` perto de 0 achata o desenho: parece o avião a rodar sobre si próprio
	var flip := Vector2(1.0, roll) * type.draw_scale
	var blade := absf(sin(prop)) * 4.0 + 0.6 if manned and not falling else 3.5
	for off in Config.wrap_offsets(position.x, 12.0):
		draw_set_transform(Vector2(off, 0.0), angle, flip)
		if turbo_t > 0.0 and manned and not falling:
			_draw_turbo_flame()
		match type.style:
			"fighter":
				_draw_fighter(body, wing)
			"bomber":
				_draw_bomber(body, wing)
			"triplane":
				_draw_triplane(body, wing)
			_:
				_draw_biplane(body, wing)
		draw_rect(Rect2(6.6, -blade, 0.8, blade * 2.0), Color("#e8e8e8"))
		draw_set_transform(Vector2(off, 0.0))
		if shield > 0:
			var pulse := 0.35 + 0.15 * sin(world.time * 8.0)
			draw_arc(Vector2.ZERO, type.hit_radius + 3.0, 0.0, TAU, 24, Color(0.37, 0.78, 1.0, pulse + 0.3), 0.8, true)
			draw_circle(Vector2.ZERO, type.hit_radius + 3.0, Color(0.37, 0.78, 1.0, pulse * 0.25))
	draw_set_transform(Vector2.ZERO)


func _draw_pilot_head(x: float, y: float) -> void:
	if manned:
		draw_rect(Rect2(x, y, 1.8, 1.8), Color("#f2c79b"))
		draw_rect(Rect2(x, y - 0.2, 1.8, 0.7), Color("#6b4a2b"))


func _draw_turbo_flame() -> void:
	var len := 2.0 + absf(sin(prop * 0.7)) * 2.5
	draw_colored_polygon(PackedVector2Array([Vector2(-6.5, -1.0), Vector2(-6.5 - len, 0.0), Vector2(-6.5, 1.0)]), Color("#ff8a25"))
	draw_colored_polygon(PackedVector2Array([Vector2(-6.5, -0.5), Vector2(-6.5 - len * 0.5, 0.0), Vector2(-6.5, 0.5)]), Color("#fff3a0"))


## Biplano: duas asas com suportes.
func _draw_biplane(body: Color, wing: Color) -> void:
	draw_rect(Rect2(-7.0, -4.5, 2.0, 3.5), body)
	draw_rect(Rect2(-6.0, -1.5, 12.0, 3.0), body)
	draw_rect(Rect2(-2.0, -5.0, 6.5, 1.4), wing)
	draw_rect(Rect2(-2.0, 1.5, 6.5, 1.4), wing)
	draw_rect(Rect2(-7.5, -0.5, 3.0, 1.0), wing)
	draw_rect(Rect2(-1.0, -3.6, 0.6, 5.1), Color("#5a4630"))
	draw_rect(Rect2(3.0, -3.6, 0.6, 5.1), Color("#5a4630"))
	draw_circle(Vector2(1.5, 4.0), 1.1, Color("#222222"))
	_draw_pilot_head(-3.4, -3.2)
	draw_rect(Rect2(5.0, -1.6, 1.6, 3.2), Color("#333333"))


## Caça: monoplano esguio com cúpula e nariz em bico.
func _draw_fighter(body: Color, wing: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-7.5, -4.0), Vector2(-5.5, -1.2), Vector2(-7.0, -1.2)]), body)
	draw_colored_polygon(PackedVector2Array([Vector2(-7.0, -1.2), Vector2(4.5, -1.6), Vector2(6.5, 0.0), Vector2(4.5, 1.4), Vector2(-7.0, 0.8)]), body)
	draw_rect(Rect2(-1.5, -0.2, 6.0, 1.3), wing)
	draw_rect(Rect2(-7.8, -0.4, 2.6, 0.9), wing)
	draw_circle(Vector2(-0.5, -1.6), 1.4, Color(0.75, 0.9, 1.0, 0.9))
	_draw_pilot_head(-1.3, -2.4)
	draw_circle(Vector2(1.0, 2.6), 0.9, Color("#222222"))
	draw_rect(Rect2(0.8, 1.2, 0.4, 1.0), Color("#444444"))


## Bombardeiro: fuselagem grossa, asas compridas e posto de tiro traseiro.
func _draw_bomber(body: Color, wing: Color) -> void:
	draw_rect(Rect2(-8.0, -5.0, 2.4, 4.5), body)
	draw_rect(Rect2(-7.0, -2.0, 13.0, 4.0), body)
	draw_rect(Rect2(-3.0, -5.6, 8.5, 1.5), wing)
	draw_rect(Rect2(-3.0, 2.0, 8.5, 1.5), wing)
	draw_rect(Rect2(-8.6, -0.6, 3.2, 1.2), wing)
	for x in [-2.0, 1.5, 4.5]:
		draw_rect(Rect2(x, -4.1, 0.6, 6.1), Color("#5a4630"))
	draw_circle(Vector2(-5.0, -2.2), 1.2, Color(0.75, 0.9, 1.0, 0.85))   # metralhador traseiro
	draw_circle(Vector2(1.0, 4.4), 1.2, Color("#222222"))
	draw_circle(Vector2(-6.0, 2.6), 0.7, Color("#222222"))
	_draw_pilot_head(2.0, -3.8)
	draw_rect(Rect2(5.0, -2.0, 1.6, 4.0), Color("#333333"))


## Triplano: três asas empilhadas.
func _draw_triplane(body: Color, wing: Color) -> void:
	draw_rect(Rect2(-6.5, -4.5, 2.0, 3.5), body)
	draw_rect(Rect2(-5.5, -1.4, 11.0, 2.8), body)
	draw_rect(Rect2(-1.5, -6.2, 5.5, 1.2), wing)
	draw_rect(Rect2(-1.5, -3.0, 5.5, 1.2), wing)
	draw_rect(Rect2(-1.5, 1.6, 5.5, 1.2), wing)
	draw_rect(Rect2(-7.0, -0.5, 2.8, 1.0), wing)
	draw_rect(Rect2(-0.6, -5.0, 0.5, 6.6), Color("#5a4630"))
	draw_rect(Rect2(2.8, -5.0, 0.5, 6.6), Color("#5a4630"))
	draw_circle(Vector2(1.2, 3.9), 1.0, Color("#222222"))
	_draw_pilot_head(-3.6, -3.2)
	draw_rect(Rect2(5.0, -1.5, 1.6, 3.0), Color("#333333"))
