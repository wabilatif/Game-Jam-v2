extends Control

const FADE_IN_DURATION := 1.2

@onready var _start_button: Button = %StartButton
@onready var _tutorial_button: Button = %TutorialButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings: Control = %SettingsMenu
@onready var _help_button: Button = %HelpButton
@onready var _help: Control = %HelpMenu
@onready var _fade: ColorRect = %Fade


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# On arrive ici de nulle part : aucun replay du tutoriel n'est en cours.
	TutorialProgress.replay = false
	for button: Button in [_start_button, _tutorial_button, _settings_button, _quit_button, _help_button]:
		button.mouse_entered.connect(button.grab_focus)
	_start_button.pressed.connect(_on_start_pressed)
	_tutorial_button.pressed.connect(_on_tutorial_pressed)
	_settings_button.pressed.connect(_settings.open)
	_settings.closed.connect(_settings_button.grab_focus)
	_quit_button.pressed.connect(get_tree().quit)
	_help_button.pressed.connect(_help.open)
	_help.closed.connect(_help_button.grab_focus)
	# Le "?" est en haut à droite : on y monte depuis le premier bouton.
	_start_button.focus_neighbor_top = _start_button.get_path_to(_help_button)
	_help_button.focus_neighbor_bottom = _help_button.get_path_to(_start_button)
	_start_button.grab_focus()
	create_tween().tween_property(_fade, "modulate:a", 0.0, FADE_IN_DURATION)


## Rejouer le tutoriel directement (l'avertissement a déjà été lu, l'intro est
## sautée) ; à la fin on revient ici.
func _on_tutorial_pressed() -> void:
	get_tree().change_scene_to_file(TutorialProgress.replay_scene())


## Lire l'avertissement avant l'intro ou la partie.
func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ContentWarning.tscn")
