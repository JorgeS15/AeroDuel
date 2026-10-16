class_name InputState
extends RefCounted
## Controlos de um lado neste instante. Escritos pelo jogador ou pelo bot e lidos pelo avião ou pelo piloto.

var left := false
var right := false
var fire := false
var eject := false   ## dura um só passo da simulação


func clear() -> void:
	left = false
	right = false
	fire = false
	eject = false
