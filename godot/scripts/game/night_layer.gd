class_name NightLayer
extends Node2D
## Missões noturnas: escurece tudo o que está por baixo (aviões incluídos),
## por isso de noite vê-se pior o adversário.

var world: World


func _draw() -> void:
	if world != null and world.night:
		draw_rect(Rect2(0, 0, Config.W, Config.H), Color(0.02, 0.03, 0.12, 0.38))
