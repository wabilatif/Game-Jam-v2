extends Control

signal resume_pressed
signal restart_pressed
signal main_menu_pressed

@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _settings_button: Button = %SettingsButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _settings: Control = %SettingsMenu
@onready var _help_button: Button = %HelpButton
@onready var _help: Control = %HelpMenu


func _ready() -> void:
	for button: Button in [_resume_button, _restart_button, _settings_button, _main_menu_button, _help_button]:
		button.mouse_entered.connect(button.grab_focus)
	_resume_button.pressed.connect(resume_pressed.emit)
	_restart_button.pressed.connect(restart_pressed.emit)
	_settings_button.pressed.connect(_settings.open)
	_settings.closed.connect(_settings_button.grab_focus)
	_main_menu_button.pressed.connect(main_menu_pressed.emit)
	_help_button.pressed.connect(_help.open)
	_help.closed.connect(_help_button.grab_focus)
	_resume_button.focus_neighbor_top = _resume_button.get_path_to(_help_button)
	_help_button.focus_neighbor_bottom = _help_button.get_path_to(_resume_button)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	# La pause se rouvre toujours sur sa liste, jamais sur un panneau.
	_settings.hide()
	_help.hide()
	if is_visible_in_tree():
		_resume_button.grab_focus.call_deferred()
