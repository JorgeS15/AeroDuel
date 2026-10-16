class_name Config
extends RefCounted
## Constantes do mundo e utilitários partilhados.
## As características de cada avião ficam em PlaneType (data/planes/*.tres).

## Largura do mundo (dá a volta nas laterais). A altura é fixa; a largura acompanha
## o formato do ecrã (Game acerta-a no arranque), por isso não há barras pretas.
static var W := 384.0
const BASE_W := 384.0
const H := 216.0                 ## altura do mundo (a barra de controlos fica por baixo)
const BAR_H := 44.0              ## altura da barra de controlos nos ecrãs táteis
const GROUND := 196.0            ## y do chão
const PLANE_Y := GROUND - 4.0    ## y do centro de um avião pousado
const GRAVITY := 55.0
const BULLET_LIFE := 1.1
const WIN_SCORE := 10
const RESPAWN_TIME := 2.5
const WALK_SPEED := 32.0

const TEAM_BODY := [Color("#2f6fd6"), Color("#d63a2f")]
const TEAM_WING := [Color("#9cc3ff"), Color("#ffb19c")]
const TEAM_CHUTE := [Color("#e8f1ff"), Color("#fff0ea")]
const TEAM_NAME := ["azul", "vermelho"]

const GOOD := Color("#9cff9c")
const BAD := Color("#ffb19c")
const WARN := Color("#fff6c2")


static func hangar_x(side_id: int) -> float:
	return 36.0 if side_id == 0 else W - 36.0


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
