class_name Background
extends Node2D
## Céu, nuvens, colinas, árvores, hangares e chão.

const TREES := [0.286, 0.333, 0.495, 0.664, 0.703]   ## posições em fração da largura

var world: World
var _clouds: Array[Dictionary] = []
var _hills := PackedVector2Array()


func _ready() -> void:
	rebuild()


## Recalcula nuvens e colinas para a largura atual do mundo.
func rebuild() -> void:
	_clouds.clear()
	_hills = PackedVector2Array()
	for i in int(ceil(Config.W / 64.0)):
		_clouds.append({ "x": i * 70.0 + randf_range(0, 40), "y": randf_range(18, 90), "s": randf_range(0.7, 1.4), "v": randf_range(2, 5) })
	_hills.append(Vector2(0, Config.GROUND))
	var x := 0.0
	while x <= Config.W:
		_hills.append(Vector2(x, Config.GROUND - 16.0 - 9.0 * sin(x * 0.03) - 5.0 * sin(x * 0.071 + 1.0)))
		x += 4.0
	_hills.append(Vector2(Config.W, Config.GROUND))


func _process(delta: float) -> void:
	for c in _clouds:
		c.x = fmod(c.x + c.v * delta, Config.W + 60.0)
	queue_redraw()


func _draw() -> void:
	var w := Config.W
	var g := Config.GROUND
	# céu em degradé
	var top := Color("#4ea8f0")
	var bottom := Color("#cdeeff")
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, g), Vector2(0, g)]),
		PackedColorArray([top, top, bottom, bottom]))
	draw_circle(Vector2(300, 34), 12, Color("#fff6c2"))

	var cloud := Color(1, 1, 1, 0.82)
	for c in _clouds:
		var cx: float = c.x - 30.0
		var cy: float = c.y
		var s: float = c.s
		draw_circle(Vector2(cx, cy), 7 * s, cloud)
		draw_circle(Vector2(cx + 8 * s, cy - 4 * s), 8 * s, cloud)
		draw_circle(Vector2(cx + 17 * s, cy), 7 * s, cloud)

	draw_colored_polygon(_hills, Color("#8cc98a"))

	for tf in TREES:
		var tx: float = tf * w
		draw_rect(Rect2(tx - 0.7, g - 6, 1.4, 6), Color("#6b4a2b"))
		draw_circle(Vector2(tx, g - 8), 4, Color("#3e8a3a"))

	for i in 2:
		_draw_hangar(i)

	draw_rect(Rect2(0, g, w, 3), Color("#5fae4a"))
	draw_rect(Rect2(0, g + 3, w, Config.H - g - 3), Color("#8b6b3d"))
	var x := 4
	while x < w:
		draw_rect(Rect2(x, g + 8 + (x % 3) * 3, 3, 1.5), Color("#7a5d33"))
		x += 16


func _draw_hangar(id: int) -> void:
	var x: float = Config.hangar_x(id)
	var g := Config.GROUND
	var t := world.time if world else 0.0
	draw_rect(Rect2(x - 11, g - 11, 22, 11), Color("#d8c69c"))
	draw_colored_polygon(PackedVector2Array([Vector2(x - 13, g - 11), Vector2(x, g - 18), Vector2(x + 13, g - 11)]), Config.TEAM_BODY[id])
	draw_rect(Rect2(x - 6, g - 8, 12, 8), Color("#3b2f22"))
	# missões de defesa: barra de resistência e fumo quando danificado
	if world and world.mission.has("hangar_hp") and id == world.me:
		var full := float(world.mission.hangar_hp)
		var k := clampf(world.hangar_hp / full, 0.0, 1.0)
		draw_rect(Rect2(x - 11, g - 23, 22, 2.5), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(x - 11, g - 23, 22 * k, 2.5), Config.GOOD if k > 0.5 else Config.BAD)
		for i in int((1.0 - k) * 4.0):
			draw_circle(Vector2(x - 6 + i * 4, g - 14 - fmod(t * 6.0 + i * 3.0, 8.0)), 2.0, Color(0.2, 0.2, 0.2, 0.5))
	# bandeira
	var fx := x + 9 if id == 0 else x - 9
	draw_rect(Rect2(fx, g - 27, 0.8, 16), Color("#444444"))
	draw_rect(Rect2(fx + 0.8, g - 27 + sin(t * 6 + id) * 0.6, 5, 3), Config.TEAM_BODY[id])
