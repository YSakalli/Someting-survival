extends Node
##
## 42 API OAuth2 (Authorization Code Flow) singleton.
##
## Akis:
##   1) start_login() -> tarayicida intra.42.fr/oauth/authorize acilir
##   2) localhost:PORT/callback dinlenir, code yakalanir
##   3) code -> token endpoint, access_token alinir
##   4) access_token ile /v2/me cagrilir
##   5) login_success(user_data) yayinlanir
##

signal status_changed(message: String)
signal login_success(user_data: Dictionary)
signal login_failed(error: String)

const AUTH_URL := "https://api.intra.42.fr/oauth/authorize"
const TOKEN_URL := "https://api.intra.42.fr/oauth/token"
const ME_URL := "https://api.intra.42.fr/v2/me"
const COALITIONS_URL_FMT := "https://api.intra.42.fr/v2/users/%d/coalitions"

var _uid: String = ""
var _secret: String = ""
var _redirect_uri: String = "http://localhost:8765/callback"
var _redirect_port: int = 8765

var _state_token: String = ""
var access_token: String = ""
var user_data: Dictionary = {}
var coalition: String = ""
var element: String = "fire"
var last_coalitions_status: int = 0
var last_coalitions_body: String = ""

var _tcp_server: TCPServer = null
var _pending_peers: Array = []  # [{peer: StreamPeerTCP, buffer: String}, ...]

var _http_token: HTTPRequest
var _http_me: HTTPRequest
var _http_coalitions: HTTPRequest


func _ready() -> void:
	set_process(false)
	_load_secrets()

	_http_token = HTTPRequest.new()
	add_child(_http_token)
	_http_token.request_completed.connect(_on_token_response)

	_http_me = HTTPRequest.new()
	add_child(_http_me)
	_http_me.request_completed.connect(_on_me_response)

	_http_coalitions = HTTPRequest.new()
	add_child(_http_coalitions)
	_http_coalitions.request_completed.connect(_on_coalitions_response)


func _load_secrets() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://42api/secrets.cfg")
	if err != OK:
		push_warning("42api/secrets.cfg yuklenemedi (err=%d). UID/SECRET'i doldur." % err)
		return
	_uid = String(cfg.get_value("api42", "uid", "")).strip_edges()
	_secret = String(cfg.get_value("api42", "secret", "")).strip_edges()
	_redirect_uri = String(cfg.get_value("api42", "redirect_uri", _redirect_uri)).strip_edges()
	# Port'u redirect_uri'den cikar
	var port_part := _redirect_uri.split(":")[2]  # "8765/callback"
	_redirect_port = int(port_part.split("/")[0])
	var uid_prefix := _uid.substr(0, 12) if _uid.length() > 12 else _uid
	print("[OAuth42] secrets yuklendi: uid_len=%d uid_prefix='%s' secret_len=%d redirect='%s'" % [_uid.length(), uid_prefix, _secret.length(), _redirect_uri])


func start_login() -> void:
	if _uid == "" or _secret == "":
		emit_signal("login_failed", "secrets.cfg eksik (UID/SECRET bos).")
		return
	if _tcp_server != null:
		emit_signal("login_failed", "Zaten bir giris islemi devam ediyor.")
		return

	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(_redirect_port, "127.0.0.1")
	if err != OK:
		_tcp_server = null
		emit_signal("login_failed", "Port %d dinlenemedi (zaten kullanimda olabilir). Hata: %d" % [_redirect_port, err])
		return

	_state_token = _generate_state()

	var params := {
		"client_id": _uid,
		"redirect_uri": _redirect_uri,
		"response_type": "code",
		"scope": "public",
		"state": _state_token,
	}
	var query := ""
	for k in params.keys():
		if query != "":
			query += "&"
		query += String(k).uri_encode() + "=" + String(params[k]).uri_encode()
	var full_url := AUTH_URL + "?" + query

	emit_signal("status_changed", "Tarayicida 42'ye giris yap...")
	OS.shell_open(full_url)
	set_process(true)


func cancel_login() -> void:
	_stop_server()
	emit_signal("status_changed", "Giris iptal edildi.")


func _generate_state() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var s := ""
	for i in range(32):
		s += chars[randi() % chars.length()]
	return s


func _process(_delta: float) -> void:
	if _tcp_server == null:
		return

	while _tcp_server.is_connection_available():
		var peer := _tcp_server.take_connection()
		_pending_peers.append({"peer": peer, "buffer": ""})

	var i := 0
	while i < _pending_peers.size():
		if _tcp_server == null:
			return  # _stop_server cagrildi
		var entry: Dictionary = _pending_peers[i]
		var peer: StreamPeerTCP = entry.peer
		peer.poll()
		var should_remove := false
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			should_remove = true
		else:
			var available := peer.get_available_bytes()
			if available > 0:
				entry.buffer += peer.get_utf8_string(available)
			if "\r\n\r\n" in entry.buffer:
				_handle_http_request(peer, entry.buffer)
				should_remove = true
		if should_remove:
			_pending_peers.remove_at(i)
		else:
			i += 1


func _handle_http_request(peer: StreamPeerTCP, raw: String) -> void:
	var first_line := raw.split("\r\n")[0]
	var parts := first_line.split(" ")
	if parts.size() < 2:
		_send_response(peer, 400, _html_page("Bad request"))
		return
	var path := parts[1]
	if not path.begins_with("/callback"):
		_send_response(peer, 404, _html_page("Not found"))
		return

	var qmark := path.find("?")
	if qmark == -1:
		_send_response(peer, 400, _html_page("Callback parametresiz geldi."))
		emit_signal("login_failed", "Callback'te query parametresi yok.")
		_stop_server()
		return

	var query := path.substr(qmark + 1)
	var params := {}
	for pair in query.split("&"):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2:
			params[kv[0].uri_decode()] = kv[1].uri_decode()

	if "error" in params:
		var err_msg: String = params.get("error_description", params["error"])
		_send_response(peer, 200, _html_page("Giris reddedildi: " + err_msg))
		emit_signal("login_failed", "42 reddetti: " + err_msg)
		_stop_server()
		return

	if not "code" in params or not "state" in params:
		_send_response(peer, 400, _html_page("Eksik code veya state."))
		emit_signal("login_failed", "Callback'te code veya state eksik.")
		_stop_server()
		return

	if params["state"] != _state_token:
		_send_response(peer, 400, _html_page("State uyumsuz (CSRF korumasi)."))
		emit_signal("login_failed", "State uyumsuz - olasi CSRF.")
		_stop_server()
		return

	_send_response(peer, 200, _html_page("Giris basarili! Bu sekmeyi kapatabilirsin."))
	_stop_server()

	emit_signal("status_changed", "Token aliniyor...")
	_exchange_code_for_token(params["code"])


func _send_response(peer: StreamPeerTCP, status: int, body: String) -> void:
	var status_text := "OK" if status == 200 else "ERROR"
	var body_bytes := body.to_utf8_buffer()
	var response := "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, status_text, body_bytes.size()]
	peer.put_data(response.to_utf8_buffer())
	peer.put_data(body_bytes)
	peer.disconnect_from_host()


func _html_page(message: String) -> String:
	return "<!doctype html><html><head><meta charset='utf-8'><title>42 Auth</title><style>body{font-family:sans-serif;background:#111;color:#eee;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}div{text-align:center;padding:2em 3em;border:1px solid #00babc;border-radius:8px}h1{color:#00babc;margin:0 0 .5em}</style></head><body><div><h1>42-gamejam</h1><p>" + message + "</p></div></body></html>"


func _stop_server() -> void:
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null
	for entry in _pending_peers:
		var peer: StreamPeerTCP = entry.peer
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
	_pending_peers.clear()
	set_process(false)


func _exchange_code_for_token(code: String) -> void:
	var body := {
		"grant_type": "authorization_code",
		"client_id": _uid,
		"client_secret": _secret,
		"code": code,
		"redirect_uri": _redirect_uri,
	}
	var body_str := ""
	for k in body.keys():
		if body_str != "":
			body_str += "&"
		body_str += String(k).uri_encode() + "=" + String(body[k]).uri_encode()
	var headers := ["Content-Type: application/x-www-form-urlencoded"]
	var err := _http_token.request(TOKEN_URL, headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		emit_signal("login_failed", "Token request baslatilamadi (err=%d)." % err)


func _on_token_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	if response_code != 200:
		emit_signal("login_failed", "Token endpoint %d dondu: %s" % [response_code, text])
		return
	var json: Variant = JSON.parse_string(text)
	if json == null or typeof(json) != TYPE_DICTIONARY or not "access_token" in json:
		emit_signal("login_failed", "Token cevabi gecersiz: " + text)
		return
	access_token = json["access_token"]
	emit_signal("status_changed", "Kullanici bilgisi cekiliyor...")
	_fetch_me()


func _fetch_me() -> void:
	var headers := ["Authorization: Bearer " + access_token]
	var err := _http_me.request(ME_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		emit_signal("login_failed", "/v2/me request baslatilamadi (err=%d)." % err)


func _on_me_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	if response_code != 200:
		emit_signal("login_failed", "/v2/me %d dondu: %s" % [response_code, text])
		return
	var json: Variant = JSON.parse_string(text)
	if json == null or typeof(json) != TYPE_DICTIONARY:
		emit_signal("login_failed", "/v2/me cevabi parse edilemedi.")
		return
	user_data = json
	emit_signal("status_changed", "Koalisyon bilgisi cekiliyor...")
	_fetch_coalitions()


func _fetch_coalitions() -> void:
	var user_id: int = int(user_data.get("id", 0))
	if user_id <= 0:
		push_warning("[OAuth42] user id alinamadi, coalition atlandi")
		emit_signal("login_success", user_data)
		return
	var url := COALITIONS_URL_FMT % user_id
	print("[OAuth42] coalitions URL=", url)
	var headers := ["Authorization: Bearer " + access_token]
	var err := _http_coalitions.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		# Coalition gelemese de login tamamlanmis sayalim
		emit_signal("login_success", user_data)


func _on_coalitions_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	last_coalitions_status = response_code
	last_coalitions_body = text
	print("[OAuth42] coalitions HTTP %d body=%s" % [response_code, text])
	if response_code == 200:
		var json: Variant = JSON.parse_string(text)
		if typeof(json) == TYPE_ARRAY and (json as Array).size() > 0:
			# Birden fazla varsa ilkini birincil kabul et
			var primary: Dictionary = (json as Array)[0]
			coalition = String(primary.get("name", ""))
			var slug: String = String(primary.get("slug", ""))
			element = _coalition_to_element(coalition, slug)
			user_data["coalition"] = coalition
			user_data["element"] = element
			print("[OAuth42] coalition='%s' slug='%s' -> element='%s'" % [coalition, slug, element])
		else:
			print("[OAuth42] coalitions cevabi bos veya array degil")
	else:
		push_warning("[OAuth42] coalitions endpoint %d dondu" % response_code)
	emit_signal("login_success", user_data)


func _coalition_to_element(name: String, slug: String) -> String:
	var key := (name + " " + slug).to_lower()
	if "aqualis" in key:
		return "water"
	if "terranos" in key:
		return "wood"
	if "aerys" in key:
		return "air"
	if "ignatus" in key:
		return "fire"
	return "fire"
