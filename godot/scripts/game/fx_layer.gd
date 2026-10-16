class_name FxLayer
extends Node2D
## Partículas (fumo, explosões, poeira) e balas, desenhadas de uma vez.

const MAX_PARTICLES := 600

var world: World
var _particles: Array[Dictionary] = []


func clear() -> void:
	_particles.clear()
	queue_redraw()


func add_particle(pos: Vector2, vel: Vector2, life: float, color: Color, size: float, gravity: float) -> void:
	_particles.append({ "pos": pos, "vel": vel, "life": life, "max": life, "color": color, "size": size, "grav": gravity })


func puff(pos: Vector2, color: Color, count: int, spd: float, life: float, size: float, gravity: float) -> void:
	for i in count:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(0.2, 1.0) * spd
		add_particle(pos, v, life, color, size * randf_range(0.7, 1.3), gravity)


func explosion(pos: Vector2) -> void:
	puff(pos, Color("#ffd23f"), 16, 70.0, 0.5, 2.0, 30.0)
	puff(pos, Color("#ff7b25"), 16, 50.0, 0.7, 2.6, 15.0)
	puff(pos, Color("#555555"), 12, 25.0, 1.4, 3.2, -12.0)


func step(dt: float) -> void:
	for q in _particles:
		q.vel.y += q.grav * dt
		q.pos += q.vel * dt
		q.life -= dt
	_particles = _particles.filter(func(q: Dictionary) -> bool: return q.life > 0.0)
	if _particles.size() > MAX_PARTICLES:
		_particles = _particles.slice(_particles.size() - MAX_PARTICLES)
	queue_redraw()


func _draw() -> void:
	for q in _particles:
		var k: float = q.life / q.max
		var c: Color = q.color
		c.a = k
		var s: float = q.size * (0.5 + 0.5 * k)
		draw_rect(Rect2(q.pos - Vector2(s, s) * 0.5, Vector2(s, s)), c)
	if world == null:
		return
	for b in world.bullets:
		var c := Color("#fff38a") if b.shooter.id == 0 else Color("#ffcf8a")
		draw_rect(Rect2(b.pos.x - 1.0, b.pos.y - 0.6, 2.0, 1.2), c)
