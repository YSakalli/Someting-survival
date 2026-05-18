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
var _subtitle_label: Label
var _pixel_font: SystemFont


func _ready() -> void:
	_pixel_font = SystemFont.new()
	_pixel_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_pixel_font.hinting = TextServer.HINTING_NONE

	_build_ui()

	OAuth42.status_changed.connect(_on_status_changed)
	OAuth42.login_success.connect(_on_login_success)
	OAuth42.login_failed.connect(_on_login_failed)


func _make_button_style(bg: Color, border: Color, fcol: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = fcol
	return sb


func _style_button(btn: Button, accent: Color) -> void:
	var normal := _make_button_style(Color(0.07, 0.09, 0.12, 1.0), accent, accent)
	var hover := _make_button_style(accent * Color(1, 1, 1, 0.18), accent, accent)
	hover.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
	var pressed := _make_button_style(Color(accent.r, accent.g, accent.b, 0.30), accent, accent)
	var disabled := _make_button_style(Color(0.1, 0.1, 0.12, 1.0), Color(0.3, 0.3, 0.34, 1.0), Color(0.5, 0.5, 0.5, 1.0))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", _pixel_font)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", accent)
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))


func _build_ui() -> void:
	# Tam ekran koyu arkaplan
	var bg := ColorRect.new()
	bg.color = Color("#0b0d12")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Hafif vinyet ust serit
	var top_strip := ColorRect.new()
	top_strip.color = Color(0.25, 0.85, 1, 0.10)
	top_strip.anchor_right = 1.0
	top_strip.offset_bottom = 4.0
	add_child(top_strip)

	# Ortalanmis konteyner
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(640, 0)
	center.add_child(vbox)

	# Baslik
	var title := Label.new()
	title.text = "42-GAMEJAM"
	title.add_theme_font_override("font", _pixel_font)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color("#40d9ff"))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Alt baslik
	_subtitle_label = Label.new()
	_subtitle_label.text = "SIGN IN WITH YOUR 42 ACCOUNT"
	_subtitle_label.add_theme_font_override("font", _pixel_font)
	_subtitle_label.add_theme_font_size_override("font_size", 20)
	_subtitle_label.add_theme_color_override("font_color", Color("#8b949e"))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_subtitle_label)

	# Ayirici bosluk
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	# Login butonu (ortalanmis)
	var login_wrap := CenterContainer.new()
	vbox.add_child(login_wrap)
	_login_button = Button.new()
	_login_button.text = "LOGIN WITH 42"
	_login_button.custom_minimum_size = Vector2(320, 60)
	_login_button.focus_mode = Control.FOCUS_NONE
	_style_button(_login_button, Color("#40d9ff"))
	_login_button.pressed.connect(_on_login_pressed)
	login_wrap.add_child(_login_button)

	# Durum etiketi
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_override("font", _pixel_font)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("#8b949e"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	# Kullanici karti (giris sonrasi)
	_user_panel = PanelContainer.new()
	_user_panel.visible = false
	_user_panel.custom_minimum_size = Vector2(640, 240)
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.07, 0.09, 0.12, 1.0)
	card_sb.border_color = Color("#40d9ff")
	card_sb.border_width_left = 2
	card_sb.border_width_right = 2
	card_sb.border_width_top = 2
	card_sb.border_width_bottom = 2
	card_sb.corner_radius_top_left = 10
	card_sb.corner_radius_top_right = 10
	card_sb.corner_radius_bottom_left = 10
	card_sb.corner_radius_bottom_right = 10
	card_sb.content_margin_left = 24
	card_sb.content_margin_right = 24
	card_sb.content_margin_top = 20
	card_sb.content_margin_bottom = 20
	_user_panel.add_theme_stylebox_override("panel", card_sb)
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
	_info_label.add_theme_font_override("font", _pixel_font)
	_info_label.add_theme_font_size_override("font_size", 18)
	_info_label.add_theme_color_override("font_color", Color("#e6edf3"))
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	user_hbox.add_child(_info_label)

	# Play butonu (ortalanmis)
	var play_wrap := CenterContainer.new()
	vbox.add_child(play_wrap)
	_play_button = Button.new()
	_play_button.text = "OYUNA BASLA"
	_play_button.custom_minimum_size = Vector2(320, 64)
	_play_button.focus_mode = Control.FOCUS_NONE
	_style_button(_play_button, Color("#ffd633"))
	_play_button.visible = false
	_play_button.pressed.connect(_on_play_pressed)
	play_wrap.add_child(_play_button)

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
	_subtitle_label.visible = false
	_status_label.text = "WELCOME, %s" % user_data.get("login", "?").to_upper()
	_status_label.add_theme_color_override("font_color", Color("#40d9ff"))
	_user_panel.visible = true
	_play_button.visible = true

	var login_name: String = user_data.get("login", "?")
	var display_name: String = user_data.get("displayname", "?")
	var level := 0.0
	var cursus: String = "?"
	var cursus_users: Array = user_data.get("cursus_users", [])
	if cursus_users.size() > 0:
		var last_cu: Dictionary = cursus_users[cursus_users.size() - 1]
		level = last_cu.get("level", 0.0)
		var c_info: Dictionary = last_cu.get("cursus", {})
		cursus = c_info.get("name", "?")
	var wallet: int = user_data.get("wallet", 0)
	var correction_point: int = user_data.get("correction_point", 0)
	var coalition_name: String = user_data.get("coalition", "?")
	var element_name: String = user_data.get("element", "fire")

	_info_label.text = "%s\n%s\n\nCURSUS  %s\nLEVEL   %.2f\nWALLET  %d Z\nEVALS   %d\nCOALIT. %s\nELEMENT %s" % [
		display_name, login_name, cursus, level, wallet, correction_point, coalition_name, element_name
	]
	print("[main] coalitions HTTP=%d full body=%s" % [OAuth42.last_coalitions_status, OAuth42.last_coalitions_body])

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
