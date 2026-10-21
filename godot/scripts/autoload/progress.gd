extends Node
## Autoload "Progress": moedas, estrelas das missões, aviões comprados, melhorias
## e pinturas. Fica guardado no telemóvel (user://progress.json).

signal changed

const SAVE_PATH := "user://progress.json"

## Preço dos aviões (o biplano já vem incluído).
const PLANE_PRICES := { "biplane": 0, "fighter": 120, "triplane": 200, "bomber": 300 }

## Melhorias por avião: 3 níveis cada.
const UPGRADES := {
	"engine": { "name": "Motor", "desc": "+6% de motor e +3% de rotação por nível" },
	"armor": { "name": "Blindagem", "desc": "+1 de vida por nível" },
	"guns": { "name": "Metralhadora", "desc": "-8% de tempo entre tiros por nível" },
}
const UPGRADE_COSTS := [40, 90, 160]
const MAX_UPGRADE := 3

## Pinturas do teu avião: [fuselagem, asas].
const PAINTS := {
	"azul": { "name": "Azul", "price": 0, "colors": [Color("#2f6fd6"), Color("#9cc3ff")] },
	"verde": { "name": "Verde", "price": 60, "colors": [Color("#3d8f3a"), Color("#a8e09a")] },
	"amarelo": { "name": "Amarelo", "price": 60, "colors": [Color("#d6a32f"), Color("#ffe39c")] },
	"branco": { "name": "Branco", "price": 80, "colors": [Color("#e8e8e8"), Color("#9cc3ff")] },
	"camuflado": { "name": "Camuflado", "price": 120, "colors": [Color("#5b6b3a"), Color("#8f9a5c")] },
}

# Recompensas em moedas
const COINS_PER_KILL := 3
const COINS_DUEL_WIN := 20
const COINS_MISSION_DONE := 15
const COINS_PER_NEW_STAR := 20

var coins := 0
var stars := {}                 ## id da missão -> [bool, bool, bool] (melhor resultado)
var owned_planes := ["biplane"]
var upgrades := {}              ## id do avião -> { engine: n, armor: n, guns: n }
var owned_paints := ["azul"]
var paint := "azul"


func _ready() -> void:
	load_progress()


# ---------- estrelas e missões ----------

func mission_stars(id: String) -> Array:
	return stars.get(id, [false, false, false])


func star_count(id: String) -> int:
	return mission_stars(id).count(true)


func total_stars() -> int:
	var n := 0
	for id in stars:
		n += star_count(id)
	return n


## Uma missão abre quando a anterior foi cumprida e, na primeira de uma região,
## quando já há estrelas suficientes para essa região.
func mission_unlocked(index: int) -> bool:
	if total_stars() < region_stars_needed(Campaign.mission(index).region):
		return false
	if index == 0:
		return true
	return mission_stars(Campaign.mission(index - 1).id)[0]


func region_stars_needed(region: int) -> int:
	return int(Campaign.REGIONS[region].stars_needed)


## Guarda o resultado (fica o melhor) e devolve as moedas ganhas.
func record_mission(id: String, got: Array[bool], kills: int) -> int:
	var before := mission_stars(id)
	var best := []
	var new_stars := 0
	for i in 3:
		best.append(before[i] or got[i])
		if got[i] and not before[i]:
			new_stars += 1
	stars[id] = best
	var earned := kills * COINS_PER_KILL + new_stars * COINS_PER_NEW_STAR
	if got[0]:
		earned += COINS_MISSION_DONE
	add_coins(earned)
	return earned


func add_coins(amount: int) -> void:
	coins += amount
	save_progress()
	changed.emit()


# ---------- aviões ----------

func owns_plane(id: String) -> bool:
	return owned_planes.has(id)


func buy_plane(id: String) -> bool:
	var price: int = PLANE_PRICES.get(id, 0)
	if owns_plane(id) or coins < price:
		return false
	coins -= price
	owned_planes.append(id)
	save_progress()
	changed.emit()
	return true


func upgrade_level(plane_id: String, kind: String) -> int:
	return int(upgrades.get(plane_id, {}).get(kind, 0))


## Preço do próximo nível, ou -1 se já está no máximo.
func upgrade_cost(plane_id: String, kind: String) -> int:
	var lvl := upgrade_level(plane_id, kind)
	return -1 if lvl >= MAX_UPGRADE else UPGRADE_COSTS[lvl]


func buy_upgrade(plane_id: String, kind: String) -> bool:
	var cost := upgrade_cost(plane_id, kind)
	if cost < 0 or coins < cost or not owns_plane(plane_id):
		return false
	coins -= cost
	if not upgrades.has(plane_id):
		upgrades[plane_id] = {}
	upgrades[plane_id][kind] = upgrade_level(plane_id, kind) + 1
	save_progress()
	changed.emit()
	return true


## O PlaneType do jogador já com as melhorias compradas aplicadas.
func player_plane_type(plane_id: String) -> PlaneType:
	var t := World.plane_type(plane_id).duplicate() as PlaneType
	var engine := upgrade_level(plane_id, "engine")
	t.thrust *= 1.0 + 0.06 * engine
	t.turn_rate *= 1.0 + 0.03 * engine
	t.max_hp += upgrade_level(plane_id, "armor")
	t.fire_cooldown *= 1.0 - 0.08 * upgrade_level(plane_id, "guns")
	return t


# ---------- pinturas ----------

func paint_colors() -> Array:
	return PAINTS.get(paint, PAINTS["azul"]).colors


func buy_or_select_paint(id: String) -> bool:
	if not owned_paints.has(id):
		var price: int = PAINTS[id].price
		if coins < price:
			return false
		coins -= price
		owned_paints.append(id)
	paint = id
	save_progress()
	changed.emit()
	return true


# ---------- gravação ----------

func save_progress() -> void:
	var data := {
		"coins": coins, "stars": stars, "owned_planes": owned_planes,
		"upgrades": upgrades, "owned_paints": owned_paints, "paint": paint,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	coins = int(data.get("coins", 0))
	stars = data.get("stars", {})
	owned_planes = data.get("owned_planes", ["biplane"])
	upgrades = data.get("upgrades", {})
	owned_paints = data.get("owned_paints", ["azul"])
	paint = str(data.get("paint", "azul"))
	if not owned_planes.has("biplane"):
		owned_planes.append("biplane")


## Só para testes: volta ao início.
func reset() -> void:
	coins = 0
	stars = {}
	owned_planes = ["biplane"]
	upgrades = {}
	owned_paints = ["azul"]
	paint = "azul"
