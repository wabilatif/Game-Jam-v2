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
		"desc": "Étourdit le monstre pendant 3 s. Recharge : 12 s.",
	},
	"spectral_vision": {
		"name": "Vision spectrale",
		"desc": "Révèle le monstre pendant 5 s. Recharge : 15 s.",
	},
	"speed_boost": {
		"name": "Accélération",
		"desc": "Vitesse x1.5 pendant 5 s. Recharge : 12 s.",
	},
	"spectral_trap": {
		"name": "Piège spectral",
		"desc": "Pose un piège qui ralentit le monstre de 50 % pendant 5 s. Recharge : 15 s.",
	},
}
const SACRIFICE_INFO: Dictionary = {
	"hearing": {
		"name": "Ouïe",
		"desc": "Les bruits qui permettent de repérer le monstre deviennent presque inaudibles. Permanent.",
	},
	"leg": {
		"name": "Jambe",
		"desc": "Votre vitesse de déplacement est réduite de 25 %. Permanent.",
	},
	"vision": {
		"name": "Vue",
		"desc": "Votre vision est altérée en permanence. Permanent.",
	},
	"stamina": {
		"name": "Souffle",
		"desc": "Votre sprint dure deux fois moins longtemps (4 s -> 2 s). Permanent.",
	},
}

@onready var _title: Label = %Title
@onready var _power_name: Label = %PowerName
@onready var _power_description: Label = %PowerDescription
@onready var _choices: VBoxContainer = %Choices
@onready var _accept_button: Button = %AcceptButton
@onready var _reject_button: Button = %RejectButton

var _power_id: String = ""
var _selected_sacrifice: String = ""
var _button_group: ButtonGroup = ButtonGroup.new()


func _ready() -> void:
	_accept_button.pressed.connect(_on_accept_pressed)
	_reject_button.pressed.connect(_on_reject_pressed)
	_accept_button.disabled = true


## Prepare le menu pour un pouvoir et une liste de sacrifices (ids du contrat).
func open(power_id: String, sacrifices: Array[String]) -> void:
	_power_id = power_id
	_selected_sacrifice = ""
	_accept_button.disabled = true

	var info: Dictionary = POWER_INFO.get(power_id, {})
	_power_name.text = String(info.get("name", power_id))
	_power_description.text = String(info.get("desc", ""))

	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()

	if sacrifices.is_empty():
		var empty := Label.new()
		empty.text = "Aucun sacrifice disponible."
		_choices.add_child(empty)
		return

	for sacrifice_id in sacrifices:
		_choices.add_child(_make_choice(sacrifice_id))

	_reject_button.grab_focus()


func _make_choice(sacrifice_id: String) -> Control:
	var info: Dictionary = SACRIFICE_INFO.get(sacrifice_id, {})
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _button_group
	button.text = String(info.get("name", sacrifice_id))
	button.custom_minimum_size = Vector2(0, 40)
	button.toggled.connect(_on_choice_toggled.bind(sacrifice_id))
	card.add_child(button)

	var description := Label.new()
	description.text = String(info.get("desc", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.modulate = Color(0.75, 0.75, 0.75)
	card.add_child(description)
	return card


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
