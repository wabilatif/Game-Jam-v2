extends Control
## LOST MEMORY - Personne 5A : menu de sacrifice.
## Affiche le pouvoir decouvert et les sacrifices possibles, avec leur
## description. Emet seulement accepted / rejected (UIManager relaie).
## Ne valide rien : c'est PowerManager qui decide.

signal accepted(power_id: String, sacrifice_id: String)
signal rejected

const POWER_INFO: Dictionary = {
	"shockwave": {
		"name": "Onde de choc",
		"desc": "Étourdit le monstre 3 s, à moins de 8 m. Recharge 12 s.",
	},
	"spectral_vision": {
		"name": "Vision spectrale",
		"desc": "Révèle le monstre 5 s. Recharge 15 s.",
	},
	"speed_boost": {
		"name": "Accélération",
		"desc": "Vitesse x1.5 pendant 5 s. Recharge 12 s.",
	},
	"spectral_trap": {
		"name": "Piège spectral",
		"desc": "Piège au sol : ralentit le monstre de 50 % pendant 5 s. Recharge 15 s.",
	},
}
const SACRIFICE_INFO: Dictionary = {
	"hearing": {
		"name": "Ouïe",
		"desc": "vous n'entendrez plus le monstre approcher",
	},
	"leg": {
		"name": "Jambe",
		"desc": "vous marcherez 25 % moins vite",
	},
	"vision": {
		"name": "Vue",
		"desc": "votre vue restera troublée",
	},
	"stamina": {
		"name": "Souffle",
		"desc": "votre sprint durera 2 s au lieu de 4",
	},
	"arm": {
		"name": "Bras",
		"desc": "vos pouvoirs rechargeront 50 % plus lentement",
	},
	"heart": {
		"name": "Cœur",
		"desc": "votre souffle reviendra deux fois moins vite",
	},
	"reflexes": {
		"name": "Réflexes",
		"desc": "votre regard répondra mal, la caméra sera lourde",
	},
	"light": {
		"name": "Lumière",
		"desc": "votre lampe n'éclairera plus que faiblement",
	},
	"memory": {
		"name": "Mémoire",
		"desc": "vous perdrez votre mini-map : plus de plan de l\u2019hôpital",
	},
}

const CHOICE_WIDTH := 210

@onready var _title: Label = %Title
@onready var _power_name: Label = %PowerName
@onready var _power_description: Label = %PowerDescription
@onready var _choices: Container = %Choices
@onready var _accept_button: Button = %AcceptButton
@onready var _reject_button: Button = %RejectButton

var _power_id: String = ""
var _selected_sacrifice: String = ""
var _button_group: ButtonGroup = ButtonGroup.new()


func _ready() -> void:
	for button: Button in [_accept_button, _reject_button]:
		button.mouse_entered.connect(button.grab_focus)
	_accept_button.pressed.connect(_on_accept_pressed)
	_reject_button.pressed.connect(_on_reject_pressed)
	_accept_button.disabled = true


## Prepare le menu pour un pouvoir et une liste de sacrifices (ids du contrat).
func open(power_id: String, sacrifices: Array[String]) -> void:
	_power_id = power_id
	_selected_sacrifice = ""
	_accept_button.disabled = true

	var info: Dictionary = POWER_INFO.get(power_id, {})
	_power_name.text = tr(String(info.get("name", power_id))).to_upper()
	_power_description.text = tr(String(info.get("desc", "")))

	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()

	var choice_buttons: Array[Button] = []
	if sacrifices.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = "FieldLabel"
		empty.text = tr("Plus rien à céder.")
		_choices.add_child(empty)
	for sacrifice_id in sacrifices:
		var row := _make_choice(sacrifice_id)
		_choices.add_child(row)
		choice_buttons.append(row.get_child(0))

	_wire_focus(choice_buttons)
	var first: Button = choice_buttons[0] if not choice_buttons.is_empty() else _reject_button
	first.grab_focus.call_deferred()


## Navigation clavier/manette fixe : haut/bas parcourent les choix puis
## descendent sur Refuser ; Refuser <-> Signer avec gauche/droite.
## Une direction sans destination ne fait rien.
func _wire_focus(choice_buttons: Array[Button]) -> void:
	var last: Control = choice_buttons.back() if not choice_buttons.is_empty() else _reject_button
	for i in choice_buttons.size():
		var button := choice_buttons[i]
		var above: Control = choice_buttons[i - 1] if i > 0 else button
		var below: Control = choice_buttons[i + 1] if i + 1 < choice_buttons.size() else _reject_button
		_set_neighbors(button, above, below, button, button)
	_set_neighbors(_reject_button, last, _reject_button, _reject_button, _accept_button)
	_set_neighbors(_accept_button, last, _accept_button, _reject_button, _accept_button)


func _set_neighbors(control: Control, up: Control, down: Control, left: Control, right: Control) -> void:
	control.focus_neighbor_top = control.get_path_to(up)
	control.focus_neighbor_bottom = control.get_path_to(down)
	control.focus_neighbor_left = control.get_path_to(left)
	control.focus_neighbor_right = control.get_path_to(right)


## Une ligne du formulaire : "[ ]  OUÏE   vous n'entendrez plus...".
## La case devient [X] et la ligne s'éclaire une fois cochée.
func _make_choice(sacrifice_id: String) -> Control:
	var info: Dictionary = SACRIFICE_INFO.get(sacrifice_id, {})
	var sacrifice_name := tr(String(info.get("name", sacrifice_id))).to_upper()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)

	var button := Button.new()
	button.theme_type_variation = "ChoiceButton"
	button.toggle_mode = true
	button.button_group = _button_group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.x = CHOICE_WIDTH
	button.text = "[ ]  " + sacrifice_name
	row.add_child(button)

	var description := Label.new()
	description.theme_type_variation = "FieldLabel"
	description.text = tr(String(info.get("desc", "")))
	description.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(description)

	button.toggled.connect(func(pressed: bool) -> void:
		button.text = ("[X]  " if pressed else "[ ]  ") + sacrifice_name
		description.theme_type_variation = "FieldValueLabel" if pressed else "FieldLabel")
	button.toggled.connect(_on_choice_toggled.bind(sacrifice_id))
	button.mouse_entered.connect(button.grab_focus)
	return row


func _on_choice_toggled(pressed: bool, sacrifice_id: String) -> void:
	if pressed:
		_selected_sacrifice = sacrifice_id
		_accept_button.disabled = false


func _on_accept_pressed() -> void:
	if _selected_sacrifice == "":
		return
	accepted.emit(_power_id, _selected_sacrifice)


func _on_reject_pressed() -> void:
	rejected.emit()
