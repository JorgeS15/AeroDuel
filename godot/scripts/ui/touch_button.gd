class_name TouchButton
extends Control
## Botão redondo para o ecrã tátil, com multitoque a sério: vários dedos ao
## mesmo tempo e deslizar de um botão para outro.
## Também responde ao rato, para testar no computador.

signal tapped

@export var label := ""
@export var tint := Color(1, 1, 1)

var pressed := false
var _touches := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		if not _touches.is_empty():
			_touches.clear()
			_refresh()
		return
	if event is InputEventScreenTouch:
		if event.pressed and _hit(event.position):
			_touches[event.index] = true
		elif not event.pressed:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		if _hit(event.position):
			_touches[event.index] = true
		else:
			_touches.erase(event.index)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return   # rato emulado a partir de um toque: o toque já foi tratado
		if event.pressed and _hit(event.position):
			_touches[-1] = true
		elif not event.pressed:
			_touches.erase(-1)
	else:
		return
	_refresh()


func _hit(pos: Vector2) -> bool:
	var r := get_global_rect()
	return pos.distance_to(r.get_center()) <= r.size.x * 0.6


func _refresh() -> void:
	var now := not _touches.is_empty()
	if now == pressed:
		return
	pressed = now
	if pressed:
		tapped.emit()
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := size.x * 0.5
	var fill := tint
	fill.a = 0.45 if pressed else 0.18
	draw_circle(c, r, fill)
	draw_arc(c, r - 0.5, 0, TAU, 32, Color(tint, 0.7), 1.0, true)
	var font := get_theme_default_font()
	var fs := 13 if label.length() <= 2 else 7
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
