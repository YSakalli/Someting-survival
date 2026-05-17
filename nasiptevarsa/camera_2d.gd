extends Camera2D

@export var zoom_min: float = 2.0
@export var zoom_max: float = 8.0
@export var zoom_step: float = 0.5
@export var zoom_speed: float = 5.0

var target_zoom: float = 4.0

func _ready():
	target_zoom = zoom.x

func _process(delta):
	# Yumuşak zoom geçişi
	var current = zoom.x
	var new_zoom = lerp(current, target_zoom, zoom_speed * delta)
	zoom = Vector2(new_zoom, new_zoom)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				target_zoom = clamp(target_zoom + zoom_step, zoom_min, zoom_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom = clamp(target_zoom - zoom_step, zoom_min, zoom_max)
