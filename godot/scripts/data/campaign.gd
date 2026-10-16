class_name Campaign
extends RefCounted
## Missões da campanha. Cada missão é um dicionário com:
##   id, region, title, brief            textos
##   goal: "kills" | "balloons" | "score" objetivo
##   target                              quantidade a atingir
##   bot: { difficulty, plane, raid, hp_bonus, colors }
##   lose_bot_score                      (opcional) perde se o bot chegar a estes pontos
##   time_limit                          (opcional) perde se o tempo acabar (s)
##   hangar_hp                           (opcional) o hangar pode ser destruído
##   powerups                            (opcional, true por omissão)
##   par_time                            tempo para a 3.ª estrela (s)
##   star2: "no_loss" | "hangar_full"    condição da 2.ª estrela

const REGIONS := {
	1: { "name": "Costa", "stars_needed": 0 },
}

const ACE_COLORS := [Color("#2a2a2a"), Color("#d63a2f")]

const MISSIONS := [
	{
		"id": "r1m1", "region": 1, "title": "Primeiro voo",
		"brief": "Abate 3 aviões inimigos antes de o bot marcar 5 pontos.",
		"goal": "kills", "target": 3, "lose_bot_score": 5,
		"bot": { "difficulty": "facil", "plane": "biplane" },
		"par_time": 120.0, "star2": "no_loss",
	},
	{
		"id": "r1m2", "region": 1, "title": "Balões de observação",
		"brief": "Destrói os 4 balões inimigos em menos de 2 min 30 s.",
		"goal": "balloons", "target": 4, "time_limit": 150.0,
		"bot": { "difficulty": "facil", "plane": "biplane" },
		"par_time": 75.0, "star2": "no_loss",
	},
	{
		"id": "r1m3", "region": 1, "title": "Defender o hangar",
		"brief": "Os bombardeiros vêm destruir o teu hangar. Abate 4 antes que consigam.",
		"goal": "kills", "target": 4, "hangar_hp": 5,
		"bot": { "difficulty": "normal", "plane": "bomber", "raid": true },
		"par_time": 150.0, "star2": "hangar_full",
	},
	{
		"id": "r1m4", "region": 1, "title": "O Ás Negro",
		"brief": "O melhor piloto inimigo: rápido, certeiro e blindado, mas cavalheiro: não dispara sobre pilotos. Chega a 5 pontos antes dele.",
		"goal": "score", "target": 5, "lose_bot_score": 5, "powerups": false,
		"bot": { "difficulty": "as", "plane": "fighter", "hp_bonus": 1, "colors": ACE_COLORS },
		"par_time": 180.0, "star2": "no_loss",
	},
]


static func count() -> int:
	return MISSIONS.size()


static func mission(index: int) -> Dictionary:
	return MISSIONS[index]


static func index_of(id: String) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i].id == id:
			return i
	return -1


## Textos das três estrelas, para o ecrã de resultado.
static func star_labels(m: Dictionary) -> Array[String]:
	var second := "Sem perder nenhum avião" if m.get("star2", "no_loss") == "no_loss" else "Hangar intacto"
	return ["Missão cumprida", second, "Em menos de %s" % format_time(m.par_time)]


## Estrelas conquistadas: [cumprida, 2.ª condição, tempo].
static func stars_for(m: Dictionary, result: Dictionary) -> Array[bool]:
	if not result.won:
		return [false, false, false]
	var second: bool
	if m.get("star2", "no_loss") == "hangar_full":
		second = result.hangar_hp >= int(m.get("hangar_hp", 0))
	else:
		second = result.planes_lost == 0
	return [true, second, result.time <= m.par_time]


static func format_time(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]
