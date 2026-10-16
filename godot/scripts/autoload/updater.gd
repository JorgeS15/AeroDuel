extends Node
## Autoload "Updater": verifica se há um build mais recente do mesmo canal
## (latest ou pr-N) nos releases do GitHub e guarda o link para o APK novo.
##
## O CI publica, junto do AeroDuel.apk, um build.json com o número do build.
## Só funciona se os releases estiverem acessíveis sem sessão iniciada
## (repositório público). Num repositório privado o GitHub responde 404.

signal status_changed

enum Status { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, UNAVAILABLE }

const REPO := "JorgeS15/AeroDuel"

var status := Status.IDLE
var latest_build := 0
var apk_url := ""
var _http: HTTPRequest


func _ready() -> void:
	check()


func check() -> void:
	var channel := str(Game.build.channel)
	if channel.is_empty() or status == Status.CHECKING:
		return   # build local (sem canal) ou já a verificar
	_set_status(Status.CHECKING)
	_http = HTTPRequest.new()
	_http.max_redirects = 8
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_completed.bind(channel))
	var url := "https://github.com/%s/releases/download/%s/build.json" % [REPO, channel]
	if _http.request(url, ["User-Agent: AeroDuel", "Cache-Control: no-cache"]) != OK:
		_finish(Status.UNAVAILABLE)


## O APK novo é aberto no browser, que o descarrega; depois o Android pede
## para confirmar a instalação (é obrigatório para apps fora da Play Store).
func open_download() -> void:
	if not apk_url.is_empty():
		OS.shell_open(apk_url)


static func is_newer(remote_build: int, local_build: int) -> bool:
	return remote_build > local_build


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, channel: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish(Status.UNAVAILABLE)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_finish(Status.UNAVAILABLE)
		return
	latest_build = int(data.get("build", 0))
	if is_newer(latest_build, int(Game.build.build)):
		apk_url = "https://github.com/%s/releases/download/%s/AeroDuel.apk" % [REPO, channel]
		_finish(Status.AVAILABLE)
	else:
		_finish(Status.UP_TO_DATE)


func _finish(new_status: Status) -> void:
	if _http:
		_http.queue_free()
		_http = null
	_set_status(new_status)


func _set_status(new_status: Status) -> void:
	status = new_status
	status_changed.emit()


func status_text() -> String:
	match status:
		Status.CHECKING:
			return "A procurar atualizações…"
		Status.UP_TO_DATE:
			return "Estás na versão mais recente."
		Status.AVAILABLE:
			return "Há uma versão nova: build %d." % latest_build
		Status.UNAVAILABLE:
			return "Não foi possível verificar atualizações."
	return ""
