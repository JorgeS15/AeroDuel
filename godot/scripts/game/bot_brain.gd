class_name BotBrain
extends RefCounted
## IA do bot: aponta para onde o alvo vai estar, evita o chão e a perda,
## salta quando é abatido e corre para o hangar.

const DIFFICULTIES := {
	"facil":   { "reaction": 0.35, "noise": 0.30, "cone": 0.10, "range": 110.0, "trigger": 0.35, "hunt_pilots": false },
	"normal":  { "reaction": 0.18, "noise": 0.14, "cone": 0.14, "range": 140.0, "trigger": 0.7,  "hunt_pilots": true },
	"dificil": { "reaction": 0.08, "noise": 0.05, "cone": 0.18, "range": 170.0, "trigger": 1.0,  "hunt_pilots": true },
}

var _t := 0.0          ## tempo até rever a pontaria
var _noise := 0.0      ## erro de pontaria atual
var _eject_t := 0.0


## `passive` (modo de teste): voa a direito a meia altura e não dispara, como um alvo.
func think(side: Side, world: World, difficulty: String, dt: float, passive := false) -> void:
	var inp := side.input
	var d: Dictionary = DIFFICULTIES[difficulty]
	inp.clear()
	var me := side.ctrl
	if me == null:
		return

	if me is Pilot:
		var pilot := me as Pilot
		if pilot.state == Pilot.State.FREE:
			return
		var dx := Config.dx_wrap(pilot.position.x, Config.HANGAR_X[side.id])
		if absf(dx) > 1.0:
			inp.left = dx < 0.0
			inp.right = dx > 0.0
		return

	var p := me as Airplane
	if p.falling:
		_eject_t += dt
		if _eject_t > d.reaction + 0.2:
			inp.eject = true
		return
	_eject_t = 0.0

	var facing := 1.0 if cos(p.angle) >= 0.0 else -1.0
	var up := -0.55 if facing > 0.0 else PI + 0.55
	var desired: float
	var aim := NAN
	var dist := INF
	_t -= dt

	if p.on_ground:
		if p.speed > p.type.takeoff_speed + 15.0:
			desired = -0.35 if facing > 0.0 else PI + 0.35
		else:
			desired = 0.0 if facing > 0.0 else PI
	elif p.stalled:
		desired = PI / 2.0
	else:
		# escolher alvo
		var target: Node2D = null if passive else world.sides[1 - side.id].ctrl
		var valid := false
		var tpos := Vector2.ZERO
		var tvel := Vector2.ZERO
		if target is Airplane and not (target as Airplane).falling and not (target as Airplane).dead:
			valid = true
			tpos = target.position
			tvel = (target as Airplane).velocity()
		elif target is Pilot and d.hunt_pilots and not (target as Pilot).dead:
			valid = true
			tpos = target.position
			tvel = (target as Pilot).velocity()
		if valid:
			var rel := Vector2(Config.dx_wrap(p.position.x, tpos.x), tpos.y - p.position.y)
			dist = rel.length()
			var lead_t := dist / (p.type.bullet_speed + p.speed * 0.5)   # apontar para onde o alvo vai estar
			rel += tvel * lead_t
			aim = rel.angle()
			if _t <= 0.0:
				_t = d.reaction
				_noise = randf_range(-d.noise, d.noise)
			desired = aim + _noise
		else:
			var cruise_y := 100.0 if passive else 70.0
			desired = atan2((cruise_y - p.position.y) * 0.5, 60.0 * facing)   # patrulhar a meia altura

		var alt := Config.GROUND - p.position.y
		# não mergulhar a pique perto do chão
		if alt < 90.0 and sin(desired) > 0.45:
			desired = atan2(0.45, 0.89 if cos(desired) >= 0.0 else -0.89)
		# evitar entrar em perda
		if p.speed < p.type.stall_speed + 10.0 and sin(desired) < -0.25:
			desired = atan2(-0.1, facing)
		# muito baixo: subir
		if alt < 50.0 and sin(p.angle) > -0.15:
			desired = up

	var diff := Config.ang_diff(p.angle, desired)
	if absf(diff) > 0.05:
		inp.right = diff > 0.0
		inp.left = diff < 0.0
	if not is_nan(aim) and dist < d.range and absf(Config.ang_diff(p.angle, aim)) < d.cone and randf() < d.trigger:
		inp.fire = true
