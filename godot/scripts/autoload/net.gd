extends Node
## Autoload "Net": multijogador na mesma rede Wi-Fi (ou com um telemóvel a fazer hotspot).
##
## Um telemóvel cria o jogo (anfitrião): é ele que corre a simulação. O outro entra,
## envia os seus controlos a cada passo e recebe uma fotografia do jogo 30 vezes por
## segundo, mais os efeitos (sons, explosões, mensagens) — ver NetSync e World.fx().
## Os jogos abertos anunciam-se por difusão UDP na rede local; também se pode ligar
## diretamente pelo IP, para as redes que bloqueiam a difusão.

signal hosts_changed
signal status_changed
signal match_started(data: Dictionary)
signal ended(reason: String)            ## ligação perdida, recusada ou fechada pelo outro
signal over_received(winner_id: int)
signal rematch_requested
signal snapshot_received(snap: Array)
signal fx_received(event: String, args: Array)

const PORT := 27450
const DISCOVERY_PORT := 27451
const PROTOCOL := 1                     ## sobe quando a rede deixa de ser compatível
const ANNOUNCE_EVERY := 1.0
const HOST_TIMEOUT := 3.5               ## segundos sem anúncio até um jogo sair da lista
const SNAP_EVERY := 2                   ## passos de física entre fotografias (60/2 = 30 por segundo)
const GAME_TAG := "aeroduel"

enum Role { NONE, HOST, CLIENT }

var role := Role.NONE
var connected := false                  ## o outro telemóvel está ligado e apresentado
var status := ""                        ## texto para o menu
var hosts := {}                         ## ip -> { name, seen }
var remote_input := InputState.new()    ## anfitrião: controlos do outro telemóvel
var my_info := {}                       ## plane, colors, w, name deste telemóvel
var peer_info := {}
var world: World                        ## anfitrião: o mundo a fotografar

var _udp: PacketPeerUDP
var _browsing := false
var _announce_t := 0.0
var _peer_id := 0
var _frame := 0
var _clock := 0.0
var _eject_n := 0                       ## convidado: quantas vezes carregou em SALTAR
var _bomb_n := 0
var _seen_eject := 0                    ## anfitrião: o último contador recebido
var _seen_bomb := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_active() -> bool:
	return role != Role.NONE


## Endereços IPv4 deste telemóvel na rede local (para mostrar a quem vai ligar pelo IP).
func local_ips() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# ---------- criar, procurar, entrar e sair ----------

func host_game(info: Dictionary) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		_set_status("Não foi possível criar o jogo (erro %d)." % err)
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	my_info = info
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_announce_t = 0.0
	var ips := local_ips()
	_set_status("À espera de um amigo…" + ("   O teu IP: " + ", ".join(ips) if not ips.is_empty() else ""))
	return true


## Começa a ouvir os anúncios dos jogos abertos na rede.
func start_browsing() -> void:
	if _browsing or role == Role.HOST:
		return
	_udp = PacketPeerUDP.new()
	if _udp.bind(DISCOVERY_PORT) != OK:
		_udp = null
		return
	_browsing = true
	hosts.clear()
	hosts_changed.emit()


func stop_browsing() -> void:
	if _browsing:
		_udp.close()
		_udp = null
		_browsing = false
	if not hosts.is_empty():
		hosts.clear()
		hosts_changed.emit()


func join(ip: String, info: Dictionary) -> bool:
	leave()
	if not ip.is_valid_ip_address():
		_set_status("IP inválido: " + ip)
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_set_status("Não foi possível ligar (erro %d)." % err)
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	my_info = info
	_set_status("A ligar a %s…" % ip)
	return true


## Fecha a ligação (ou o jogo aberto) sem avisar o menu.
func leave() -> void:
	stop_browsing()
	if _udp != null:
		_udp.close()
		_udp = null
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	role = Role.NONE
	connected = false
	_peer_id = 0
	world = null
	remote_input.clear()


func _end(reason: String) -> void:
	var was_active := is_active()
	leave()
	_set_status(reason)
	if was_active:
		ended.emit(reason)


func _set_status(text: String) -> void:
	status = text
	status_changed.emit()


# ---------- eventos da ligação ----------

func _on_peer_connected(_id: int) -> void:
	pass   # o anfitrião espera pela apresentação (_rpc_hello)


func _on_peer_disconnected(id: int) -> void:
	if role == Role.HOST and id == _peer_id:
		_end("O teu amigo saiu do jogo.")


func _on_connected_to_server() -> void:
	_set_status("Ligado. A preparar o jogo…")
	_rpc_hello.rpc_id(1, PROTOCOL, my_info)


func _on_connection_failed() -> void:
	_end("Não foi possível ligar. Confirma que estão os dois na mesma rede Wi-Fi.")


func _on_server_disconnected() -> void:
	_end("O anfitrião fechou o jogo.")


# ---------- mensagens ----------

## Convidado -> anfitrião: versão da rede e o avião escolhido.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(protocol: int, info: Dictionary) -> void:
	if role != Role.HOST or connected:
		return
	var sender := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_rpc_reject.rpc_id(sender, "Versões diferentes do jogo: atualizem os dois telemóveis.")
		return
	_peer_id = sender
	peer_info = info
	connected = true
	if _udp != null:
		_udp.close()
		_udp = null
	start_match()


## Anfitrião: começa (ou recomeça) a partida e diz ao convidado como.
func start_match() -> void:
	if role != Role.HOST or not connected:
		return
	var host_colors: Array = my_info.get("colors", [])
	var guest_colors: Array = peer_info.get("colors", [])
	if guest_colors == host_colors:
		guest_colors = []   # pinturas iguais: o convidado fica com as cores vermelhas
	var data := {
		# a largura do mundo tem de ser a mesma nos dois: fica a do ecrã mais estreito
		"w": minf(float(my_info.get("w", Config.BASE_W)), float(peer_info.get("w", Config.BASE_W))),
		"planes": [my_info.get("plane", "biplane"), peer_info.get("plane", "biplane")],
		"colors": [host_colors, guest_colors],
		"names": [my_info.get("name", ""), peer_info.get("name", "")],
	}
	_seen_eject = 0
	_seen_bomb = 0
	_eject_n = 0
	_bomb_n = 0
	remote_input.clear()
	_rpc_start.rpc_id(_peer_id, data)
	match_started.emit(data)


@rpc("authority", "call_remote", "reliable")
func _rpc_start(data: Dictionary) -> void:
	connected = true
	_eject_n = 0
	_bomb_n = 0
	_set_status("")
	match_started.emit(data)


@rpc("authority", "call_remote", "reliable")
func _rpc_reject(reason: String) -> void:
	_end(reason)


## Convidado: envia os controlos deste passo. SALTAR e BOMBA vão como contadores,
## para não se perderem se um pacote não chegar.
func send_input(inp: InputState) -> void:
	if role != Role.CLIENT or not connected:
		return
	if inp.eject:
		_eject_n += 1
	if inp.bomb:
		_bomb_n += 1
	var bits := int(inp.left) | int(inp.right) << 1 | int(inp.fire) << 2
	_rpc_input.rpc_id(1, bits, _eject_n, _bomb_n)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_input(bits: int, eject_n: int, bomb_n: int) -> void:
	if role != Role.HOST or multiplayer.get_remote_sender_id() != _peer_id:
		return
	remote_input.left = bits & 1 != 0
	remote_input.right = bits & 2 != 0
	remote_input.fire = bits & 4 != 0
	if eject_n > _seen_eject:
		remote_input.eject = true
	if bomb_n > _seen_bomb:
		remote_input.bomb = true
	_seen_eject = maxi(_seen_eject, eject_n)
	_seen_bomb = maxi(_seen_bomb, bomb_n)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snap(snap: Array) -> void:
	snapshot_received.emit(snap)


func send_fx(event: String, args: Array) -> void:
	if role == Role.HOST and connected:
		_rpc_fx.rpc_id(_peer_id, event, args)


@rpc("authority", "call_remote", "reliable")
func _rpc_fx(event: String, args: Array) -> void:
	fx_received.emit(event, args)


func send_over(winner_id: int) -> void:
	if role == Role.HOST and connected:
		_rpc_over.rpc_id(_peer_id, winner_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_over(winner_id: int) -> void:
	over_received.emit(winner_id)


## Convidado: pede outra partida (o anfitrião aceita logo).
func request_rematch() -> void:
	if role == Role.CLIENT and connected:
		_rpc_rematch.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch() -> void:
	if role == Role.HOST and multiplayer.get_remote_sender_id() == _peer_id:
		rematch_requested.emit()


# ---------- ciclo ----------

func _physics_process(dt: float) -> void:
	_clock += dt
	if role == Role.HOST and not connected and _udp != null:
		_announce_t -= dt
		if _announce_t <= 0.0:
			_announce_t = ANNOUNCE_EVERY
			_announce()
	if _browsing:
		_listen()
	if role == Role.HOST and connected and world != null and world.mode == "versus":
		_frame += 1
		if _frame % SNAP_EVERY == 0:
			_rpc_snap.rpc_id(_peer_id, NetSync.capture(world))


func _announce() -> void:
	var packet := JSON.stringify({ "g": GAME_TAG, "p": PROTOCOL, "n": my_info.get("name", "") }).to_utf8_buffer()
	# difusão geral e também para cada sub-rede /24 (alguns routers e hotspots só deixam passar esta)
	var targets := ["255.255.255.255"]
	for ip in local_ips():
		var parts := ip.split(".")
		targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for t in targets:
		_udp.set_dest_address(t, DISCOVERY_PORT)
		_udp.put_packet(packet)


func _listen() -> void:
	var changed := false
	while _udp.get_available_packet_count() > 0:
		var data := _udp.get_packet().get_string_from_utf8()
		var ip := _udp.get_packet_ip()
		var msg = JSON.parse_string(data)
		if typeof(msg) != TYPE_DICTIONARY or msg.get("g", "") != GAME_TAG:
			continue
		if not hosts.has(ip):
			changed = true
		hosts[ip] = { "name": str(msg.get("n", "")), "seen": _clock, "compatible": int(msg.get("p", 0)) == PROTOCOL }
	for ip in hosts.keys():
		if _clock - float(hosts[ip].seen) > HOST_TIMEOUT:
			hosts.erase(ip)
			changed = true
	if changed:
		hosts_changed.emit()
