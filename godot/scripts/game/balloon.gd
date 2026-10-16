class_name Balloon
extends Node2D
## Balão de observação inimigo, preso ao chão por um cabo. Alvo das missões.

const HIT_RADIUS := 7.0

var hp := 3
var dead := false
var hit_t := 0.0
var _anchor_y := 0.0
var _t := 0.0


func setup(pos: Vector2) -> void:
	position = pos
	_anchor_y = pos.y
	_t = randf() * TAU


func step(dt: float) -> void:
	_t += dt
	hit_t = maxf(0.0, hit_t - dt)
	position.y = _anchor_y + sin(_t * 0.9) * 3.0
	queue_redraw()


func _draw() -> void:
	var cable_to := Vector2(sin(_t * 0.5) * 2.0, Config.GROUND - position.y)
	for off in Config.wrap_offsets(position.x, 10.0):
		var o := Vector2(off, 0.0)
		draw_line(o + Vector2(0, 9), o + cable_to, Color(0.2, 0.2, 0.2, 0.6), 0.5)
		# cesto
		draw_rect(Rect2(o + Vector2(-1.5, 7), Vector2(3, 2.2)), Color("#6b4a2b"))
		draw_line(o + Vector2(-1.5, 7), o + Vector2(-3, 3), Color("#444444"), 0.4)
		draw_line(o + Vector2(1.5, 7), o + Vector2(3, 3), Color("#444444"), 0.4)
		# envelope
		var body := Color.WHITE if hit_t > 0.0 else Color("#c9b26a")
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			pts.append(o + Vector2(cos(a) * 5.5, sin(a) * 6.5 - 1.0))
		draw_colored_polygon(pts, body)
		draw_rect(Rect2(o + Vector2(-5.5, -1.6), Vector2(11, 1.2)), Color("#d63a2f"))
		draw_rect(Rect2(o + Vector2(-0.6, -7.5), Vector2(1.2, 13)), Color(0, 0, 0, 0.12))
