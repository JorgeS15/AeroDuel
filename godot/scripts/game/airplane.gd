class_name Airplane
extends Node2D
## Um avião: física de voo, tiro e desenho.

var world: World
var side: Side
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
## Orientação visual: 1 = barriga para baixo a voar para a direita, -1 = espelhado
## (direito a voar para a esquerda). `roll` vai de um ao outro aos poucos (meio-tonneau).
var upright := 1.0
var roll := 1.0

const ROLL_SPEED := 9.0          ## unidades de `roll` por segundo (~0,2 s por meio-tonneau)
const ROLL_THRESHOLD := 0.25     ## quão para lá da vertical tem de estar para rolar


func setup(p_world: World, p_side: Side) -> void:
	world = p_world
	side = p_side
	type = side.plane_type
	hp = type.max_hp
	var right := side.id == 0
	position = Vector2(Config.HANGAR_X[side.id] + (8.0 if right else -8.0), Config.PLANE_Y)
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
	cooldown -= dt
	if flying:
		prop += dt * 45.0

	# rotação
	if flying:
		var turn := (1.0 if inp.right else 0.0) - (1.0 if inp.left else 0.0)
		if stalled:
			turn *= 0.4
		angle += turn * type.turn_rate * dt
	if falling:
		angle += spin * dt
	angle = wrapf(angle, -PI, PI)

	# velocidade: motor - atrito + gravidade ao longo da trajetória
	var engine := type.thrust if flying else 0.0
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
		if manned and hp < type.max_hp and absf(Config.dx_wrap(position.x, Config.HANGAR_X[side.id])) < 16.0:
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

	if inp != null and inp.eject:
		world.eject(self)

	_update_roll(inp, dt)
	queue_redraw()


## Decide para que lado o avião fica "direito". Enquanto o jogador está a rodar,
## mantém a orientação (num looping fica de costas no topo, como deve ser); quando
## larga, e se o avião estiver claramente a voar ao contrário, faz um meio-tonneau.
func _update_roll(inp: InputState, dt: float) -> void:
	var c := cos(angle)
	if on_ground:
		upright = 1.0 if c >= 0.0 else -1.0
		roll = upright
		return
	var turning := inp != null and (inp.left or inp.right)
	if not falling and not turning:
		if c < -ROLL_THRESHOLD:
			upright = -1.0
		elif c > ROLL_THRESHOLD:
			upright = 1.0
	roll = move_toward(roll, upright, ROLL_SPEED * dt)


func velocity() -> Vector2:
	if on_ground:
		return Vector2(cos(angle) * speed, 0.0)
	return Vector2(cos(angle) * speed, sin(angle) * speed + fall_vy)


func _draw() -> void:
	var body: Color = Color.WHITE if hit_t > 0.0 else Config.TEAM_BODY[side.id]
	var wing: Color = Color.WHITE if hit_t > 0.0 else Config.TEAM_WING[side.id]
	# `roll` perto de 0 achata o desenho: parece o avião a rodar sobre si próprio
	var flip := Vector2(1.0, roll)
	var blade := absf(sin(prop)) * 4.0 + 0.6 if manned and not falling else 3.5
	for off in Config.wrap_offsets(position.x, 10.0):
		draw_set_transform(Vector2(off, 0.0), angle, flip)
		# cauda e fuselagem
		draw_rect(Rect2(-7.0, -4.5, 2.0, 3.5), body)
		draw_rect(Rect2(-6.0, -1.5, 12.0, 3.0), body)
		# asas
		draw_rect(Rect2(-2.0, -5.0, 6.5, 1.4), wing)
		draw_rect(Rect2(-2.0, 1.5, 6.5, 1.4), wing)
		draw_rect(Rect2(-7.5, -0.5, 3.0, 1.0), wing)
		# suportes e roda
		draw_rect(Rect2(-1.0, -3.6, 0.6, 5.1), Color("#5a4630"))
		draw_rect(Rect2(3.0, -3.6, 0.6, 5.1), Color("#5a4630"))
		draw_circle(Vector2(1.5, 4.0), 1.1, Color("#222222"))
		# piloto
		if manned:
			draw_rect(Rect2(-3.4, -3.2, 1.8, 1.8), Color("#f2c79b"))
			draw_rect(Rect2(-3.4, -3.4, 1.8, 0.7), Color("#6b4a2b"))
		# motor e hélice
		draw_rect(Rect2(5.0, -1.6, 1.6, 3.2), Color("#333333"))
		draw_rect(Rect2(6.6, -blade, 0.8, blade * 2.0), Color("#e8e8e8"))
	draw_set_transform(Vector2.ZERO)
