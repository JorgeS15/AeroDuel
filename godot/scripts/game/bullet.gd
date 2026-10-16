class_name Bullet
extends RefCounted
## Uma bala. São só dados: o FxLayer desenha-as todas de uma vez.

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var life := Config.BULLET_LIFE
var shooter: Side
