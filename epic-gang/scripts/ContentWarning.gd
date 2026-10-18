extends Control
## Fiche préalable à chaque lancement depuis le menu, sans effet clignotant.

@onready var _continue_button: Button = %ContinueButton
@onready var _back_button: Button = %BackButton

var _leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_continue_button.pressed.connect(_continue)
	_back_button.pressed.connect(_back)
	for button: Button in [_continue_button, _back_button]:
		button.mouse_entered.connect(button.grab_focus)
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(button)
	_continue_button.focus_neighbor_left = _continue_button.get_path_to(_back_button)
	_continue_button.focus_neighbor_right = _continue_button.get_path_to(_back_button)
	_back_button.focus_neighbor_left = _back_button.get_path_to(_continue_button)
	_back_button.focus_neighbor_right = _back_button.get_path_to(_continue_button)
	_continue_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


func _continue() -> void:
	_leave(TutorialProgress.first_scene())


func _back() -> void:
	_leave("res://scenes/MainMenu.tscn")


func _leave(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_leaving = false
		push_error("ContentWarning : impossible de charger %s (%d)." % [path, error])
