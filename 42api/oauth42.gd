extends Node

signal status_changed(message: String)
signal login_success(user_data: Dictionary)
signal login_failed(error: String)

const TOKEN_URL := "https://api.intra.42.fr/oauth/token"
const ME_URL := "https://api.intra.42.fr/v2/me"
const COALITIONS_URL_FMT := "https://api.intra.42.fr/v2/users/%d/coalitions"

var _uid: String = "u-s4t2ud-f622f15ad067886daa95a2cca02bc19574412cb85d528b16043dd6591d3eeb01"
var _secret: String = "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"
var _redirect_uri: String = ""

var access_token: String = ""
var user_data: Dictionary = {}
var coalition: String = ""
var element: String = "fire"

var _http_token: HTTPRequest
var _http_me: HTTPRequest
var _http_coalitions: HTTPRequest

var _check_timer: Timer

func _ready() -> void:
	_http_token = HTTPRequest.new()
	add_child(_http_token)
	_http_token.request_completed.connect(_on_token_response)

	_http_me = HTTPRequest.new()
	add_child(_http_me)
	_http_me.request_completed.connect(_on_me_response)

	_http_coalitions = HTTPRequest.new()
	add_child(_http_coalitions)
	_http_coalitions.request_completed.connect(_on_coalitions_response)

	# URL'den code var mı kontrol et
	_check_url_for_code()

func _check_url_for_code() -> void:
	if not OS.has_feature("web"):
		return
	
	# Mevcut URL'i al
	var current_url = JavaScriptBridge.eval("window.location.href")
	print("[OAuth] URL:", current_url)
	
	# URL'de code var mı?
	if "?code=" in current_url or "&code=" in current_url:
		_extract_code_from_url(current_url)

func start_login() -> void:
	if not OS.has_feature("web"):
		push_error("Bu script sadece web için!")
		return
	
	# Mevcut sayfanın URL'ini redirect olarak kullan
	_redirect_uri = JavaScriptBridge.eval("window.location.origin + window.location.pathname")
	print("[OAuth] redirect_uri:", _redirect_uri)
	
	var state = _generate_state()
	# State'i localStorage'a kaydet
	JavaScriptBridge.eval("localStorage.setItem('oauth_state', '%s')" % state)
	
	var params = "client_id=%s&redirect_uri=%s&response_type=code&scope=public&state=%s" % [
		_uid.uri_encode(),
		_redirect_uri.uri_encode(),
		state
	]
	
	var auth_url = "https://api.intra.42.fr/oauth/authorize?" + params
	JavaScriptBridge.eval("window.location.href = '%s'" % auth_url)

func _extract_code_from_url(url: String) -> void:
	var query = url.split("?")[1] if "?" in url else ""
	var params = {}
	for pair in query.split("&"):
		var kv = pair.split("=")
		if kv.size() == 2:
			params[kv[0]] = kv[1].uri_decode()
	
	if not "code" in params:
		return
	
	# State kontrol et
	var saved_state = JavaScriptBridge.eval("localStorage.getItem('oauth_state')")
	if params.get("state", "") != saved_state:
		emit_signal("login_failed", "State uyumsuz!")
		return
	
	# URL'i temizle
	JavaScriptBridge.eval("window.history.replaceState({}, document.title, window.location.pathname)")
	
	emit_signal("status_changed", "Token aliniyor...")
	_redirect_uri = JavaScriptBridge.eval("window.location.origin + window.location.pathname")
	_exchange_code_for_token(params["code"])

func _generate_state() -> String:
	var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var s = ""
	for i in range(32):
		s += chars[randi() % chars.length()]
	return s

func _exchange_code_for_token(code: String) -> void:
	var body_str = "grant_type=authorization_code&client_id=%s&client_secret=%s&code=%s&redirect_uri=%s" % [
		_uid.uri_encode(),
		_secret.uri_encode(),
		code.uri_encode(),
		_redirect_uri.uri_encode()
	]
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	_http_token.request(TOKEN_URL, headers, HTTPClient.METHOD_POST, body_str)

func _on_token_response(_result, response_code, _headers, body) -> void:
	var text = body.get_string_from_utf8()
	if response_code != 200:
		emit_signal("login_failed", "Token hatasi: " + text)
		return
	var json = JSON.parse_string(text)
	if json == null or not "access_token" in json:
		emit_signal("login_failed", "Token parse hatasi")
		return
	access_token = json["access_token"]
	emit_signal("status_changed", "Kullanici bilgisi aliniyor...")
	_fetch_me()

func _fetch_me() -> void:
	var headers = ["Authorization: Bearer " + access_token]
	_http_me.request(ME_URL, headers, HTTPClient.METHOD_GET)

func _on_me_response(_result, response_code, _headers, body) -> void:
	var text = body.get_string_from_utf8()
	if response_code != 200:
		emit_signal("login_failed", "/v2/me hatasi")
		return
	var json = JSON.parse_string(text)
	if json == null:
		emit_signal("login_failed", "Me parse hatasi")
		return
	user_data = json
	_fetch_coalitions()

func _fetch_coalitions() -> void:
	var user_id = int(user_data.get("id", 0))
	if user_id <= 0:
		emit_signal("login_success", user_data)
		return
	var url = COALITIONS_URL_FMT % user_id
	var headers = ["Authorization: Bearer " + access_token]
	_http_coalitions.request(url, headers, HTTPClient.METHOD_GET)

func _on_coalitions_response(_result, response_code, _headers, body) -> void:
	var text = body.get_string_from_utf8()
	if response_code == 200:
		var json = JSON.parse_string(text)
		if typeof(json) == TYPE_ARRAY and json.size() > 0:
			var primary = json[0]
			coalition = String(primary.get("name", ""))
			var slug = String(primary.get("slug", ""))
			element = _coalition_to_element(coalition, slug)
			user_data["coalition"] = coalition
			user_data["element"] = element
	emit_signal("login_success", user_data)

func _coalition_to_element(name: String, slug: String) -> String:
	var key = (name + " " + slug).to_lower()
	if "aqualis" in key: return "water"
	if "terranos" in key: return "wood"
	if "aerys" in key: return "air"
	if "ignatus" in key: return "fire"
	return "fire"
