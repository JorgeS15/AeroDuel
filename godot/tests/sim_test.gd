extends Node
## Teste de simulação: 10 minutos de bot contra bot em cada dificuldade.
## Confirma que há combate a sério e que os bots não se despenham sozinhos.
## Correr com:  godot --headless --path godot res://tests/sim_test.tscn

const MINUTES := 10.0
const DT := 1.0 / 60.0


func _ready() -> void:
	var failures: Array[String] = []
	for difficulty in ["facil", "normal", "dificil"]:
		var stats := _simulate(difficulty)
		print("%-8s %s" % [difficulty, JSON.stringify(stats)])
		var losses: int = stats.shot_down + stats.self_crash + stats.abandoned
		if losses < 30:
			failures.append("%s: só %d aviões perdidos em %d min (pouco combate)" % [difficulty, losses, MINUTES])
		if stats.self_crash > losses * 0.15:
			failures.append("%s: %d despistes sem tiros em %d perdas" % [difficulty, stats.self_crash, losses])
		if stats.ejects == 0:
			failures.append("%s: os bots nunca saltaram de paraquedas" % difficulty)
	if failures.is_empty():
		print("OK: simulação passou")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FALHOU: " + f)
		get_tree().quit(1)


func _simulate(difficulty: String) -> Dictionary:
	var world := World.new()
	add_child(world)
	world.set_physics_process(false)   # avançamos à mão, o mais depressa possível
	world.start("demo", difficulty)
	var stats := { "shot_down": 0, "self_crash": 0, "abandoned": 0, "ejects": 0, "pilot_deaths": 0, "rescues": 0 }
	var before := {}
	var pilots_before := {}
	for i in int(MINUTES * 60.0 / DT):
		world.step(DT)
		var now := {}
		for p in world.planes:
			now[p] = [p.manned, p.hp]
		for p in before:
			if not now.has(p):
				var info: Array = before[p]
				if not info[0]:
					stats.abandoned += 1
				elif info[1] <= 0:
					stats.shot_down += 1
				else:
					stats.self_crash += 1
			elif before[p][0] and not now[p][0]:
				stats.ejects += 1
		before = now
		var pilots_now := {}
		for pl in world.pilots:
			pilots_now[pl] = pl.side
		for pl in pilots_before:
			if not pilots_now.has(pl):
				var side: Side = pilots_before[pl]
				if side.ctrl is Airplane:
					stats.rescues += 1
				else:
					stats.pilot_deaths += 1
		pilots_before = pilots_now
	world.queue_free()
	return stats
