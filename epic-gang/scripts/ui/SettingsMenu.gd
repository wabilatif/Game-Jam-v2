extends Control
## Panneau Paramètres (menu principal et pause) : regroupe la luminosité,
## la langue et le plein écran. Chaque réglage garde sa propre logique et sa
## sauvegarde ; ce panneau ne fait que les afficher. Échap ou Retour le ferme.

signal closed

@onready var _brightness: Control = %BrightnessControl
@onready var _language_button: Button = %LanguageButton
@onready var _fullscreen_button: Button = %FullscreenButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(close)
	_back_button.mouse_entered.connect(_back_button.grab_focus)
	_wire_focus()


func open() -> void:
	show()
	_first_focus().grab_focus.call_deferred()


func close() -> void:
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _first_focus() -> Control:
	return _brightness.get_node("%Slider") if _brightness.visible else _language_button


## Navigation bornée au panneau : sans ça, les flèches pourraient sélectionner
## les boutons du menu caché derrière.
func _wire_focus() -> void:
	var items: Array[Control] = []
	if _brightness.visible:
		items.append(_brightness.get_node("%Slider"))
	for button: Button in [_language_button, _fullscreen_button, _back_button]:
		if button.visible:
			items.append(button)
	for i in items.size():
		var item := items[i]
		var above: Control = items[i - 1] if i > 0 else item
		var below: Control = items[i + 1] if i + 1 < items.size() else item
		item.focus_neighbor_top = item.get_path_to(above)
		item.focus_neighbor_bottom = item.get_path_to(below)
		if item is Button:
			item.focus_neighbor_left = item.get_path_to(item)
			item.focus_neighbor_right = item.get_path_to(item)
