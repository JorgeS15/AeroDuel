class_name Side
extends RefCounted
## Um dos dois lados do duelo (0 azul, 1 vermelho).

var id := 0
var is_bot := false
var score := 0
var ctrl: Node2D = null      ## o Airplane ou o Pilot que este lado controla agora
var respawn := 0.0           ## segundos até receber um avião novo
var input: InputState
var brain: BotBrain = null
var plane_type: PlaneType
var colors: Array = []       ## [fuselagem, asas]; vazio = cores da equipa
var raid := false            ## bot de ataque ao hangar (missões de defesa)
var difficulty := ""         ## dificuldade própria deste bot ("" = a do mundo)


func _init(p_id: int, p_is_bot: bool, p_input: InputState, p_type: PlaneType) -> void:
	id = p_id
	is_bot = p_is_bot
	input = p_input
	plane_type = p_type
	if is_bot:
		brain = BotBrain.new()


func body_color() -> Color:
	return colors[0] if colors.size() >= 2 else Config.TEAM_BODY[id]


func wing_color() -> Color:
	return colors[1] if colors.size() >= 2 else Config.TEAM_WING[id]
