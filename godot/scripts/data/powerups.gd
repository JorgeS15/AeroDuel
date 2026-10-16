class_name Powerups
extends RefCounted
## Catálogo dos powerups que caem de paraquedas. Apanham-se a voar contra a caixa.

const KINDS := ["shield", "triple", "turbo", "repair", "bomb"]

const INFO := {
	"shield": { "name": "Escudo", "letter": "E", "color": Color("#5ec8ff") },
	"triple": { "name": "Tiro triplo", "letter": "3", "color": Color("#ffd23f") },
	"turbo": { "name": "Turbo", "letter": "T", "color": Color("#ff8a25") },
	"repair": { "name": "Reparação", "letter": "+", "color": Color("#5fd36b") },
	"bomb": { "name": "Bombas", "letter": "B", "color": Color("#9a8cff") },
}

const SHIELD_HITS := 3         ## tiros que o escudo absorve
const TRIPLE_TIME := 8.0       ## segundos de tiro triplo
const TRIPLE_SPREAD := 0.12    ## abertura do leque (rad)
const TURBO_TIME := 8.0
const TURBO_THRUST := 1.35     ## multiplicador da força do motor
const TURBO_TURN := 1.15       ## multiplicador da rotação
const BOMBS_PER_PICKUP := 2
const MAX_BOMBS := 3
const BOMB_RADIUS := 22.0      ## raio da explosão
const BOMB_DAMAGE := 2         ## tiros equivalentes a um avião apanhado na explosão

const SPAWN_MIN := 9.0         ## intervalo entre caixas (s)
const SPAWN_MAX := 15.0
const MAX_CRATES := 2
const CRATE_LIFE_ON_GROUND := 8.0
const PICKUP_RADIUS := 10.0


static func info(kind: String) -> Dictionary:
	return INFO[kind]
