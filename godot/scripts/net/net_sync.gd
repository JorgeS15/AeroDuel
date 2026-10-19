class_name NetSync
extends RefCounted
## Fotografias do jogo no multijogador.
## O anfitrião tira uma fotografia do mundo 30 vezes por segundo (capture) e envia-a.
## O outro telemóvel não simula nada: guarda as fotografias que chegam e mostra o
## mundo um pouco atrasado (DELAY), a interpolar entre as duas fotografias à volta
## desse instante, para o movimento ficar suave mesmo com pacotes atrasados ou perdidos.

const DELAY := 0.08          ## segundos de atraso da imagem em relação à última fotografia
const MAX_BUFFER := 16
const TELEPORT := 40.0       ## acima desta distância entre fotografias não se interpola (avião novo)

# índices dentro de uma fotografia
enum { T, SIDES, PLANES, PILOTS, CRATES, BULLETS, BOMBS }

var _buf: Array = []
var _render_t := -1.0
var _planes := {}            ## nid -> Airplane
var _pilots := {}            ## nid -> Pilot
var _crates := {}            ## nid -> Crate


# ---------- anfitrião ----------

static func capture(w: World) -> Array:
	var sides := []
	for s in w.sides:
		sides.append_array([s.score, snappedf(s.respawn, 0.05), int(s.ctrl.get("nid")) if s.ctrl != null else 0])
	var planes := []
	for p in w.planes:
		if p.dead:
			continue
		var flags := int(p.on_ground) | int(p.stalled) << 1 | int(p.falling) << 2 | int(p.manned) << 3
		planes.append([p.nid, p.side.id, p.position, p.angle, p.speed, p.hp, flags,
			p.shield, p.triple_t, p.turbo_t, p.bombs, p.roll, p.hit_t])
	var pilots := []
	for pl in w.pilots:
		if not pl.dead:
			pilots.append([pl.nid, pl.side.id, pl.position, pl.state, pl.torn, pl.walk])
	var crates := []
	for c in w.crates:
		if not c.dead:
			crates.append([c.nid, c.kind, c.position, c.landed, c.ground_t])
	var bullets := PackedFloat32Array()
	for b in w.bullets:
		if b.life > 0.0:
			bullets.append_array([b.pos.x, b.pos.y, b.vel.x, b.vel.y, b.shooter.id])
	var bombs := PackedFloat32Array()
	for b in w.bombs:
		if not b.exploded:
			bombs.append_array([b.pos.x, b.pos.y, b.vel.x, b.vel.y])
	return [w.time, sides, planes, pilots, crates, bullets, bombs]


# ---------- outro telemóvel ----------

func push(snap: Array) -> void:
	if snap.size() != 7:
		return
	if not _buf.is_empty() and float(snap[T]) <= float(_buf[-1][T]):
		return   # chegou fora de ordem
	_buf.append(snap)
	if _buf.size() > MAX_BUFFER:
		_buf.pop_front()


func has_data() -> bool:
	return not _buf.is_empty()


func step(w: World, dt: float) -> void:
	if _buf.is_empty():
		return
	var latest := float(_buf[-1][T])
	var target := latest - DELAY
	if _render_t < 0.0 or absf(_render_t - target) > 0.5:
		_render_t = target   # primeira fotografia, ou ficámos muito para trás: salta
	else:
		# corre ao ritmo do relógio e corrige devagar a deriva em relação ao anfitrião
		_render_t += dt + (target - _render_t) * 0.08
	_render_t = minf(_render_t, latest)
	var ai := 0
	for i in _buf.size():
		if float(_buf[i][T]) <= _render_t:
			ai = i
	var a: Array = _buf[ai]
	var b: Array = _buf[mini(ai + 1, _buf.size() - 1)]
	var k := 0.0
	if float(b[T]) > float(a[T]):
		k = clampf((_render_t - float(a[T])) / (float(b[T]) - float(a[T])), 0.0, 1.0)
	if ai > 0:
		_buf = _buf.slice(ai)
	w.time = _render_t
	_apply(w, a, b, k, dt)


func _apply(w: World, a: Array, b: Array, k: float, dt: float) -> void:
	var sides: Array = a[SIDES]
	for i in w.sides.size():
		var s := w.sides[i]
		s.score = int(sides[i * 3])
		s.respawn = float(sides[i * 3 + 1])

	# aviões
	var next := _by_nid(b[PLANES])
	var seen := {}
	for e in a[PLANES]:
		var nid: int = e[0]
		seen[nid] = true
		var p: Airplane = _planes.get(nid)
		if p == null:
			p = Airplane.new()
			p.setup(w, w.sides[int(e[1])])
			p.nid = nid
			w.entities.add_child(p)
			_planes[nid] = p
		var pos: Vector2 = e[2]
		var ang: float = e[3]
		var roll: float = e[11]
		if next.has(nid):
			var n: Array = next[nid]
			pos = _lerp_pos(pos, n[2], k)
			ang = lerp_angle(ang, n[3], k)
			roll = lerpf(roll, n[11], k)
		p.position = pos
		p.angle = ang
		p.roll = roll
		p.speed = e[4]
		p.hp = e[5]
		var flags: int = e[6]
		p.on_ground = flags & 1 != 0
		p.stalled = flags & 2 != 0
		p.falling = flags & 4 != 0
		p.manned = flags & 8 != 0
		p.shield = e[7]
		p.triple_t = e[8]
		p.turbo_t = e[9]
		p.bombs = e[10]
		p.hit_t = e[12]
		if p.manned and not p.falling:
			p.prop += dt * 45.0
		w.emit_smoke(p, dt)
		p.queue_redraw()
	_drop_missing(_planes, seen)
	w.planes.assign(_planes.values())

	# pilotos
	next = _by_nid(b[PILOTS])
	seen = {}
	for e in a[PILOTS]:
		var nid: int = e[0]
		seen[nid] = true
		var pl: Pilot = _pilots.get(nid)
		if pl == null:
			pl = Pilot.new()
			pl.setup(w, w.sides[int(e[1])], e[2], Vector2.ZERO)
			pl.nid = nid
			w.entities.add_child(pl)
			_pilots[nid] = pl
		var pos: Vector2 = e[2]
		if next.has(nid):
			pos = _lerp_pos(pos, next[nid][2], k)
		pl.position = pos
		pl.state = e[3]
		pl.torn = e[4]
		pl.walk = e[5]
		pl.queue_redraw()
	_drop_missing(_pilots, seen)
	w.pilots.assign(_pilots.values())

	# caixas de powerups
	next = _by_nid(b[CRATES])
	seen = {}
	for e in a[CRATES]:
		var nid: int = e[0]
		seen[nid] = true
		var c: Crate = _crates.get(nid)
		if c == null:
			c = Crate.new()
			c.setup(e[1], 0.0)
			c.nid = nid
			w.entities.add_child(c)
			_crates[nid] = c
		var pos: Vector2 = e[2]
		if next.has(nid):
			pos = _lerp_pos(pos, next[nid][2], k)
		c.position = pos
		c.landed = e[3]
		c.ground_t = e[4]
		c.queue_redraw()
	_drop_missing(_crates, seen)
	w.crates.assign(_crates.values())

	# quem cada lado controla agora
	for i in w.sides.size():
		var nid: int = sides[i * 3 + 2]
		w.sides[i].ctrl = _planes.get(nid, _pilots.get(nid, null))

	# balas e bombas: só dados, avançados a partir da fotografia
	var since := w.time - float(a[T])
	var bl: PackedFloat32Array = a[BULLETS]
	w.bullets.clear()
	for i in range(0, bl.size() - 4, 5):
		var bu := Bullet.new()
		bu.vel = Vector2(bl[i + 2], bl[i + 3])
		bu.pos = Vector2(Config.wrap_x(bl[i] + bu.vel.x * since), bl[i + 1] + bu.vel.y * since)
		bu.shooter = w.sides[int(bl[i + 4])]
		w.bullets.append(bu)
	var bo: PackedFloat32Array = a[BOMBS]
	w.bombs.clear()
	for i in range(0, bo.size() - 3, 4):
		var bm := Bomb.new()
		bm.vel = Vector2(bo[i + 2], bo[i + 3])
		bm.pos = Vector2(Config.wrap_x(bo[i] + bm.vel.x * since), bo[i + 1] + bm.vel.y * since)
		w.bombs.append(bm)


static func _by_nid(list: Array) -> Dictionary:
	var out := {}
	for e in list:
		out[e[0]] = e
	return out


static func _lerp_pos(from: Vector2, to: Vector2, k: float) -> Vector2:
	var dx := Config.dx_wrap(from.x, to.x)
	var dy := to.y - from.y
	if dx * dx + dy * dy > TELEPORT * TELEPORT:
		return from
	return Vector2(Config.wrap_x(from.x + dx * k), from.y + dy * k)


static func _drop_missing(nodes: Dictionary, seen: Dictionary) -> void:
	for nid in nodes.keys():
		if not seen.has(nid):
			nodes[nid].queue_free()
			nodes.erase(nid)
