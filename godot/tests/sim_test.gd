extends Node
## Teste de simulação: 10 minutos de bot contra bot em cada dificuldade.
## Confirma que há combate a sério e que os bots não se despenham sozinhos.
## Correr com:  godot --headless --path godot res://tests/sim_test.tscn

const MINUTES := 10.0
const DT := 1.0 / 60.0


func _ready() -> void:
	var failures: Array[String] = []
	# cada avião contra cada avião (dificuldade normal), num ecrã largo (20:9)
	Config.W = 480.0
	for a in World.PLANE_IDS:
		for b in World.PLANE_IDS:
			var st := _simulate("normal", 2.0, a, b)
			var lost: int = st.shot_down + st.self_crash + st.abandoned
			print("%-8s vs %-8s %s" % [a, b, JSON.stringify(st)])
			if st.self_crash > maxi(2, int(lost * 0.15)):
				failures.append("%s vs %s: %d despistes sem tiros em %d perdas" % [a, b, st.self_crash, lost])
			if lost < 4:
				failures.append("%s vs %s: só %d aviões perdidos em 2 min" % [a, b, lost])
	Config.W = Config.BASE_W
	for difficulty in ["facil", "normal", "dificil"]:
		var stats := _simulate(difficulty, MINUTES, "biplane", "biplane")
		print("%-8s %s" % [difficulty, JSON.stringify(stats)])
		var losses: int = stats.shot_down + stats.self_crash + stats.abandoned
		if losses < 30:
			failures.append("%s: só %d aviões perdidos em %d min (pouco combate)" % [difficulty, losses, MINUTES])
		if stats.self_crash > losses * 0.15:
			failures.append("%s: %d despistes sem tiros em %d perdas" % [difficulty, stats.self_crash, losses])
		if stats.ejects == 0:
			failures.append("%s: os bots nunca saltaram de paraquedas" % difficulty)
	# missões da campanha, com um bot difícil no lugar do jogador
	for i in Campaign.count():
		var r := _play_mission(i)
		var m := Campaign.mission(i)
		print("missão %d %-22s %s  estrelas=%s" % [i + 1, m.title, JSON.stringify(r), str(Campaign.stars_for(m, r))])
		if not r.has("won"):
			failures.append("missão %d não terminou em 6 min" % (i + 1))
	if failures.is_empty():
		print("OK: simulação passou")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FALHOU: " + f)
		get_tree().quit(1)


func _play_mission(index: int) -> Dictionary:
	var world := World.new()
	add_child(world)
	world.set_physics_process(false)
	world.start("mission", { "mission": Campaign.mission(index), "player_type": World.plane_type("biplane") })
	var me := world.sides[0]
	me.is_bot = true
	me.brain = BotBrain.new()
	me.input = InputState.new()
	me.difficulty = "dificil"
	for p in world.planes:
		if p.side == me:
			p.side = me
	var result := {}
	world.mission_finished.connect(func(r: Dictionary) -> void: result.merge(r))   # (as lambdas não podem reatribuir variáveis locais)
	for i in int(6.0 * 60.0 / DT):
		world.step(DT)
		if not result.is_empty():
			break
	world.queue_free()
	return result


func _simulate(difficulty: String, minutes: float, plane_a: String, plane_b: String) -> Dictionary:
	var world := World.new()
	add_child(world)
	world.set_physics_process(false)   # avançamos à mão, o mais depressa possível
	world.start("demo", { "difficulty": difficulty })
	# na demonstração os aviões são ao calhas: fixamos os que queremos testar
	world.sides[0].plane_type = World.plane_type(plane_a)
	world.sides[1].plane_type = World.plane_type(plane_b)
	for p in world.planes:
		p.queue_free()
	world.planes.clear()
	for s in world.sides:
		world.spawn_plane(s)
	var stats := { "shot_down": 0, "self_crash": 0, "abandoned": 0, "ejects": 0, "pilot_deaths": 0, "rescues": 0, "pickups": 0, "bombs": 0 }
	var airborne_crates := {}
	var before := {}
	var pilots_before := {}
	for i in int(minutes * 60.0 / DT):
		var b0 := world.bombs.size()
		world.step(DT)
		# caixa que estava no ar e desapareceu = foi apanhada
		var still := {}
		for c in world.crates:
			if not c.landed:
				still[c] = true
		for c in airborne_crates:
			if not still.has(c) and not world.crates.has(c):
				stats.pickups += 1
		airborne_crates = still
		if world.bombs.size() > b0:
			stats.bombs += world.bombs.size() - b0
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
