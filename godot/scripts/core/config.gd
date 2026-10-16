class_name Config
extends RefCounted
## Constantes do mundo e utilitários partilhados.
## As características de cada avião ficam em PlaneType (data/planes/*.tres).

const W := 384.0                 ## largura do mundo (dá a volta nas laterais)
const H := 216.0
const GROUND := 196.0            ## y do chão
const PLANE_Y := GROUND - 4.0    ## y do centro de um avião pousado
const GRAVITY := 55.0
const BULLET_LIFE := 1.1
const WIN_SCORE := 10
const RESPAWN_TIME := 2.5
const WALK_SPEED := 16.0
const HANGAR_X := [36.0, W - 36.0]

const TEAM_BODY := [Color("#2f6fd6"), Color("#d63a2f")]
const TEAM_WING := [Color("#9cc3ff"), Color("#ffb19c")]
const TEAM_CHUTE := [Color("#e8f1ff"), Color("#fff0ea")]
const TEAM_NAME := ["azul", "vermelho"]

const GOOD := Color("#9cff9c")
const BAD := Color("#ffb19c")
const WARN := Color("#fff6c2")


static func wrap_x(x: float) -> float:
	return fposmod(x, W)


## Distância horizontal mais curta de `from` até `to`, tendo em conta a volta ao mundo.
static func dx_wrap(from: float, to: float) -> float:
	var d := to - from
	if d > W * 0.5:
		d -= W
	elif d < -W * 0.5:
		d += W
	return d


static func ang_diff(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)


static func dist2(a: Vector2, b: Vector2) -> float:
	var dx := dx_wrap(a.x, b.x)
	var dy := b.y - a.y
	return dx * dx + dy * dy


## Deslocamentos horizontais em que um objeto tem de ser desenhado para
## aparecer dos dois lados quando está junto à margem.
static func wrap_offsets(x: float, margin: float) -> Array[float]:
	var out: Array[float] = [0.0]
	if x < margin:
		out.append(W)
	if x > W - margin:
		out.append(-W)
	return out
