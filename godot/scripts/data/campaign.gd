class_name Campaign
extends RefCounted
## Missões da campanha. Cada missão é um dicionário com:
##   id, region, title, brief            textos
##   goal: "kills" | "balloons" | "score" | "survive"   objetivo
##   target                              quantidade a atingir (survive: segundos a aguentar)
##   bot: { difficulty, plane, raid, hp_bonus, colors }
##   lose_bot_score                      (opcional) perde se o bot chegar a estes pontos
##   time_limit                          (opcional) perde se o tempo acabar (s)
##   hangar_hp                           (opcional) o hangar pode ser destruído
##   powerups                            (opcional, true por omissão)
##   par_time                            tempo para a 3.ª estrela (s)
##   star2: "no_loss" | "hangar_full"    condição da 2.ª estrela
##   star3_kills                         (opcional) a 3.ª estrela pede N abates em vez do tempo
##   wind                                (opcional) vento horizontal (px/s; + para a direita)
##   night                               (opcional) missão noturna

## stars_needed: estrelas no total para abrir a região (além de cumprir a missão anterior).
const REGIONS := {
	1: { "name": "Costa", "stars_needed": 0 },
	2: { "name": "Montanhas", "stars_needed": 6 },
	3: { "name": "Frente", "stars_needed": 14 },
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
	# ---------- Região 2: Montanhas (vento) ----------
	{
		"id": "r2m1", "region": 2, "title": "Vento cruzado",
		"brief": "Nas montanhas sopra vento forte, que empurra aviões e paraquedas. Abate 4 aviões antes de o inimigo marcar 6 pontos.",
		"goal": "kills", "target": 4, "lose_bot_score": 6, "wind": 14.0,
		"bot": { "difficulty": "normal", "plane": "biplane" },
		"par_time": 150.0, "star2": "no_loss",
	},
	{
		"id": "r2m2", "region": 2, "title": "Balões na serra",
		"brief": "Destrói os 6 balões em menos de 3 min. Um caça inimigo patrulha a serra.",
		"goal": "balloons", "target": 6, "time_limit": 180.0, "wind": -10.0,
		"bot": { "difficulty": "normal", "plane": "fighter" },
		"par_time": 110.0, "star2": "no_loss",
	},
	{
		"id": "r2m3", "region": 2, "title": "Aguentar a posição",
		"brief": "Os reforços chegam daqui a 1 min 15 s. Aguenta até lá sem deixar o inimigo chegar a 10 pontos.",
		"goal": "survive", "target": 75.0, "lose_bot_score": 10, "wind": 8.0,
		"bot": { "difficulty": "normal", "plane": "triplane" },
		"par_time": 75.0, "star2": "no_loss", "star3_kills": 4,
	},
	{
		"id": "r2m4", "region": 2, "title": "Raide na montanha",
		"brief": "Bombardeiros blindados atacam o hangar com o vento a favor. Abate 5 antes que o destruam.",
		"goal": "kills", "target": 5, "hangar_hp": 4, "wind": -12.0,
		"bot": { "difficulty": "dificil", "plane": "bomber", "raid": true },
		"par_time": 180.0, "star2": "hangar_full",
	},
	# ---------- Região 3: Frente (noite) ----------
	{
		"id": "r3m1", "region": 3, "title": "Patrulha noturna",
		"brief": "De noite vê-se pouco. Abate 4 caças inimigos antes de eles marcarem 7 pontos.",
		"goal": "kills", "target": 4, "lose_bot_score": 7, "night": true,
		"bot": { "difficulty": "normal", "plane": "fighter" },
		"par_time": 180.0, "star2": "no_loss",
	},
	{
		"id": "r3m2", "region": 3, "title": "Balões ao luar",
		"brief": "Destrói os 6 balões da frente, de noite, em menos de 2 min 30 s.",
		"goal": "balloons", "target": 6, "time_limit": 150.0, "night": true,
		"bot": { "difficulty": "dificil", "plane": "triplane" },
		"par_time": 100.0, "star2": "no_loss",
	},
	{
		"id": "r3m3", "region": 3, "title": "Última defesa",
		"brief": "O ataque final ao teu hangar, com vento. Abate 6 bombardeiros reforçados; o hangar só aguenta 3 bombas.",
		"goal": "kills", "target": 6, "hangar_hp": 3, "wind": 8.0,
		"bot": { "difficulty": "dificil", "plane": "bomber", "raid": true, "hp_bonus": 1 },
		"par_time": 210.0, "star2": "hangar_full",
	},
	{
		"id": "r3m4", "region": 3, "title": "O regresso do Ás",
		"brief": "O Ás Negro voltou, de noite e sem powerups. Chega a 7 pontos antes dele.",
		"goal": "score", "target": 7, "lose_bot_score": 7, "powerups": false, "night": true,
		"bot": { "difficulty": "as", "plane": "fighter", "hp_bonus": 1, "colors": ACE_COLORS },
		"par_time": 240.0, "star2": "no_loss",
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
	var third := "Em menos de %s" % format_time(m.par_time)
	if m.has("star3_kills"):
		third = "Abater pelo menos %d aviões" % int(m.star3_kills)
	return ["Missão cumprida", second, third]


## Estrelas conquistadas: [cumprida, 2.ª condição, tempo].
static func stars_for(m: Dictionary, result: Dictionary) -> Array[bool]:
	if not result.won:
		return [false, false, false]
	var second: bool
	if m.get("star2", "no_loss") == "hangar_full":
		second = result.hangar_hp >= int(m.get("hangar_hp", 0))
	else:
		second = result.planes_lost == 0
	var third: bool = result.time <= m.par_time
	if m.has("star3_kills"):
		third = result.kills >= int(m.star3_kills)
	return [true, second, third]


## Missões de uma região, como índices em MISSIONS.
static func region_missions(region: int) -> Array[int]:
	var out: Array[int] = []
	for i in MISSIONS.size():
		if MISSIONS[i].region == region:
			out.append(i)
	return out


static func format_time(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]
