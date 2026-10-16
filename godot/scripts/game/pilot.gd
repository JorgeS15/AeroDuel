class_name Pilot
extends Node2D
## O piloto depois de saltar: queda livre, paraquedas e corrida até ao hangar.

enum State { FREE, CHUTE, GROUND }

var world: World
var side: Side
var vel := Vector2.ZERO
var state := State.FREE
var torn := false          ## paraquedas rasgado: já não abre
var t := 0.0
var walk := 0
var dead := false


func setup(p_world: World, p_side: Side, pos: Vector2, p_vel: Vector2) -> void:
	world = p_world
	side = p_side
	position = pos
	vel = p_vel


func step(dt: float) -> void:
	var inp: InputState = side.input if side.ctrl == self else null
	var dir := 0
	if inp != null:
		dir = (1 if inp.right else 0) - (1 if inp.left else 0)
	t += dt

	match state:
		State.FREE:
			vel.y += Config.GRAVITY * dt
			vel.x *= 1.0 - 0.5 * dt
			if not torn and t > 0.6:
				state = State.CHUTE
				world.fx("chute", [])
		State.CHUTE:
			vel.x += (dir * 22.0 - vel.x) * 2.0 * dt
			vel.y += (16.0 - vel.y) * 3.0 * dt

	if state != State.GROUND:
		position.x = Config.wrap_x(position.x + vel.x * dt)
		position.y += vel.y * dt
		if position.y >= Config.GROUND - 3.0:
			position.y = Config.GROUND - 3.0
			if state == State.CHUTE or vel.y < 50.0:
				state = State.GROUND
				vel = Vector2.ZERO
			else:
				world.kill_pilot(self)
				return
	else:
		walk = dir
		position.x = Config.wrap_x(position.x + dir * Config.WALK_SPEED * dt)
		if absf(Config.dx_wrap(position.x, Config.hangar_x(side.id))) < 5.0:
			world.pilot_reached_hangar(self)
			return

	queue_redraw()


func chute_center() -> Vector2:
	return position + Vector2(0.0, -10.0)


func velocity() -> Vector2:
	if state == State.GROUND:
		return Vector2(walk * Config.WALK_SPEED, 0.0)
	return vel


func tear_chute() -> void:
	state = State.FREE
	torn = true


func _draw() -> void:
	var body: Color = Config.TEAM_BODY[side.id]
	for off in Config.wrap_offsets(position.x, 10.0):
		var o := Vector2(off, 0.0)
		if state == State.CHUTE:
			var lines := Color(0, 0, 0, 0.4)
			draw_line(o + Vector2(-7, -10), o + Vector2(0, -2), lines, 0.4)
			draw_line(o + Vector2(7, -10), o + Vector2(0, -2), lines, 0.4)
			draw_line(o + Vector2(0, -17), o + Vector2(0, -2), lines, 0.4)
			draw_colored_polygon(_arc(o + Vector2(0, -10), 7.0, PI, TAU, false), Config.TEAM_CHUTE[side.id])
			draw_colored_polygon(_arc(o + Vector2(0, -10), 7.0, PI * 1.33, PI * 1.67, true), body)
		# corpo e cabeça
		draw_rect(Rect2(o + Vector2(-1, -2), Vector2(2, 3)), body)
		draw_rect(Rect2(o + Vector2(-1, -4), Vector2(2, 2)), Color("#f2c79b"))
		# pernas
		var stride := sin(world.time * 18.0) * 0.7 if state == State.GROUND and walk != 0 else 0.0
		draw_rect(Rect2(o + Vector2(-1 + stride, 1), Vector2(0.8, 2)), Color("#333333"))
		draw_rect(Rect2(o + Vector2(0.2 - stride, 1), Vector2(0.8, 2)), Color("#333333"))
		# braços a abanar em queda livre
		if state == State.FREE:
			var wave := sin(world.time * 30.0)
			draw_rect(Rect2(o + Vector2(-2.5, -2.5 + wave), Vector2(1, 1)), body)
			draw_rect(Rect2(o + Vector2(1.5, -2.5 - wave), Vector2(1, 1)), body)


## Pontos de um arco fechado, para desenhar a cúpula do paraquedas.
func _arc(center: Vector2, radius: float, from: float, to: float, include_center: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if include_center:
		pts.append(center)
	var n := 12
	for i in n + 1:
		var a := lerpf(from, to, float(i) / n)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts
