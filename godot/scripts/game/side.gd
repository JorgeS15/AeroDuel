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


func _init(p_id: int, p_is_bot: bool, p_input: InputState, p_type: PlaneType) -> void:
	id = p_id
	is_bot = p_is_bot
	input = p_input
	plane_type = p_type
	if is_bot:
		brain = BotBrain.new()
