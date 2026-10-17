extends Control

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const FADE_IN_DURATION := 1.2

@onready var _start_button: Button = %StartButton
@onready var _quit_button: Button = %QuitButton
@onready var _fade: ColorRect = %Fade


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for button: Button in [_start_button, _quit_button]:
		button.mouse_entered.connect(button.grab_focus)
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_start_button.grab_focus()
	create_tween().tween_property(_fade, "modulate:a", 0.0, FADE_IN_DURATION)


func _on_start_pressed() -> void:
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		push_warning("MainMenu: %s introuvable." % MAIN_SCENE_PATH)
		return
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
