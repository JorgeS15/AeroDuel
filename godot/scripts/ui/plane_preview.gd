class_name PlanePreview
extends Control
## Desenho do avião escolhido no menu, usando o próprio desenho do Airplane.

var _plane: Airplane


func _init() -> void:
	custom_minimum_size = Vector2(40, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_type(t: PlaneType) -> void:
	if _plane == null:
		_plane = Airplane.new()
		_plane.side = Side.new(0, false, InputState.new(), t)
		add_child(_plane)
	_plane.side.plane_type = t
	_plane.type = t
	_plane.hp = t.max_hp
	_plane.prop = 0.0
	_plane.position = custom_minimum_size * 0.5
	_plane.scale = Vector2(2.0, 2.0) / t.draw_scale
	_plane.queue_redraw()
