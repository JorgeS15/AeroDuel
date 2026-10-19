class_name Crate
extends Node2D
## Caixa de powerup: cai devagar de paraquedas; apanha-se a voar contra ela.

var nid := 0         ## identificador para o multijogador
var kind := "shield"
var landed := false
var ground_t := 0.0
var dead := false
var _t := 0.0


func setup(p_kind: String, x: float) -> void:
	kind = p_kind
	position = Vector2(x, -12.0)
	_t = randf() * TAU


func step(dt: float) -> void:
	_t += dt
	if not landed:
		position.y += 13.0 * dt
		position.x = Config.wrap_x(position.x + sin(_t * 1.3) * 6.0 * dt)
		if position.y >= Config.GROUND - 3.0:
			position.y = Config.GROUND - 3.0
			landed = true
	else:
		ground_t += dt
		if ground_t > Powerups.CRATE_LIFE_ON_GROUND:
			dead = true
	queue_redraw()


func _draw() -> void:
	var info := Powerups.info(kind)
	var color: Color = info.color
	# a piscar nos últimos segundos no chão
	if landed and ground_t > Powerups.CRATE_LIFE_ON_GROUND - 2.0 and int(ground_t * 8.0) % 2 == 0:
		return
	var font := ThemeDB.fallback_font
	for off in Config.wrap_offsets(position.x, 10.0):
		var o := Vector2(off, 0.0)
		if not landed:
			var lines := Color(0, 0, 0, 0.35)
			draw_line(o + Vector2(-5, -9), o + Vector2(-2, -3), lines, 0.4)
			draw_line(o + Vector2(5, -9), o + Vector2(2, -3), lines, 0.4)
			var pts := PackedVector2Array()
			for i in 11:
				var a := lerpf(PI, TAU, i / 10.0)
				pts.append(o + Vector2(0, -9) + Vector2(cos(a), sin(a)) * 5.0)
			draw_colored_polygon(pts, Color(1, 1, 1, 0.9))
		# caixa com a letra do powerup
		draw_rect(Rect2(o + Vector2(-3, -3), Vector2(6, 6)), color)
		draw_rect(Rect2(o + Vector2(-3, -3), Vector2(6, 6)), Color(0, 0, 0, 0.5), false, 0.5)
		var letter: String = info.letter
		var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		draw_string(font, o + Vector2(-w * 0.5, 2.2), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("#1a1a1a"))
