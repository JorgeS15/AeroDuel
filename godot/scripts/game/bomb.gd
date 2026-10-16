class_name Bomb
extends RefCounted
## Uma bomba largada por um avião. Só dados: o FxLayer desenha-as.

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var shooter: Side
var exploded := false
