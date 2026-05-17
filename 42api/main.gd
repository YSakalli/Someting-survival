extends Control
##
## Login ekrani. Tum UI burada kodla olusturulur (basit ve tek dosya).
## OAuth42 singleton'i sinyalleri yayinlar, biz dinleyip UI'yi guncelleriz.
##

const GAME_SCENE_PATH := "res://nasiptevarsa/node_2d.tscn"

var _login_button: Button
var _status_label: Label
var _user_panel: PanelContainer
var _avatar_rect: TextureRect
var _info_label: Label
var _avatar_http: HTTPRequest
var _play_button: Button


func _ready() -> void:
	_build_ui()

	OAuth42.status_changed.connect(_on_status_changed)
	OAuth42.login_success.connect(_on_login_success)
	OAuth42.login_failed.connect(_on_login_failed)


func _build_ui() -> void:
	# Arka plan rengi (ColorRect)
	var bg := ColorRect.new()
	bg.color = Color("#0d1117")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "42-gamejam"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("#00babc"))
	vbox.add_child(title)

	_login_button = Button.new()
	_login_button.text = "Login with 42"
	_login_button.custom_minimum_size = Vector2(240, 48)
	_login_button.pressed.connect(_on_login_pressed)
	vbox.add_child(_login_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", Color("#8b949e"))
	vbox.add_child(_status_label)

	_user_panel = PanelContainer.new()
	_user_panel.visible = false
	_user_panel.custom_minimum_size = Vector2(0, 200)
	vbox.add_child(_user_panel)

	var user_hbox := HBoxContainer.new()
	user_hbox.add_theme_constant_override("separation", 24)
	_user_panel.add_child(user_hbox)

	_avatar_rect = TextureRect.new()
	_avatar_rect.custom_minimum_size = Vector2(160, 160)
	_avatar_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	user_hbox.add_child(_avatar_rect)

	_info_label = Label.new()
	_info_label.text = ""
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	user_hbox.add_child(_info_label)

	_play_button = Button.new()
	_play_button.text = "Oyuna Basla"
	_play_button.custom_minimum_size = Vector2(240, 48)
	_play_button.visible = false
	_play_button.pressed.connect(_on_play_pressed)
	vbox.add_child(_play_button)

	_avatar_http = HTTPRequest.new()
	add_child(_avatar_http)
	_avatar_http.request_completed.connect(_on_avatar_downloaded)


func _on_login_pressed() -> void:
	_login_button.disabled = true
	_user_panel.visible = false
	_status_label.text = "Hazirlaniyor..."
	OAuth42.start_login()


func _on_status_changed(message: String) -> void:
	_status_label.text = message


func _on_login_failed(error: String) -> void:
	_status_label.text = "HATA: " + error
	_login_button.disabled = false
	push_error("[OAuth42] " + error)


func _on_login_success(user_data: Dictionary) -> void:
	_login_button.visible = false
	_status_label.text = "Hosgeldin, %s!" % user_data.get("login", "?")
	_user_panel.visible = true
	_play_button.visible = true

	var login_name: String = user_data.get("login", "?")
	var display_name: String = user_data.get("displayname", "?")
	var email: String = user_data.get("email", "?")
	var level := 0.0
	var cursus: String = "?"
	var cursus_users: Array = user_data.get("cursus_users", [])
	if cursus_users.size() > 0:
		# Genelde son cursus_user en gunceldir (42cursus)
		var last_cu: Dictionary = cursus_users[cursus_users.size() - 1]
		level = last_cu.get("level", 0.0)
		var c_info: Dictionary = last_cu.get("cursus", {})
		cursus = c_info.get("name", "?")
	var wallet: int = user_data.get("wallet", 0)
	var correction_point: int = user_data.get("correction_point", 0)

	var coalition_name: String = user_data.get("coalition", "?")
	var element_name: String = user_data.get("element", "fire")
	_info_label.text = "Login: %s\nDisplay: %s\nEmail: %s\nCursus: %s\nLevel: %.2f\nWallet: %d Z\nCorrection points: %d\nCoalition: %s\nElement: %s" % [
		login_name, display_name, email, cursus, level, wallet, correction_point, coalition_name, element_name
	]

	# Avatar indir
	var image_info: Dictionary = user_data.get("image", {})
	var versions: Dictionary = image_info.get("versions", {})
	var avatar_url: String = versions.get("medium", image_info.get("link", ""))
	if avatar_url != "":
		_avatar_http.request(avatar_url)


func _on_play_pressed() -> void:
	_play_button.disabled = true
	var err := get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if err != OK:
		_status_label.text = "Oyun sahnesi yuklenemedi (err=%d)." % err
		_play_button.disabled = false


func _on_avatar_downloaded(_result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200 or body.size() == 0:
		push_warning("Avatar indirilemedi: %d" % response_code)
		return
	var img := Image.new()
	# Content-Type'a bakmak yerine srayla deneyelim
	var err := img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	if err != OK:
		err = img.load_webp_from_buffer(body)
	if err != OK:
		push_warning("Avatar formati tanimlanamadi.")
		return
	_avatar_rect.texture = ImageTexture.create_from_image(img)
