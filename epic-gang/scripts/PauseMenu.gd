extends Control

signal resume_pressed
signal restart_pressed
signal main_menu_pressed

@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton


func _ready() -> void:
	for button: Button in [_resume_button, _restart_button, _main_menu_button]:
		button.mouse_entered.connect(button.grab_focus)
	_resume_button.pressed.connect(resume_pressed.emit)
	_restart_button.pressed.connect(restart_pressed.emit)
	_main_menu_button.pressed.connect(main_menu_pressed.emit)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_resume_button.grab_focus.call_deferred()
