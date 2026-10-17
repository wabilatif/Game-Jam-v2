extends Control
## Fiche "?" (menu principal et pause) : toutes les commandes et les pouvoirs.
## Les lignes sont générées depuis les données ci-dessous ; les lettres suivent
## le clavier du joueur (KeyNames). Échap ou Retour la ferme.

signal closed

const MOVEMENT_KEYS_WIDTH := 190
## La colonne de droite (pouvoirs + système) partage une même largeur de
## touches pour que les textes soient alignés.
const RIGHT_KEYS_WIDTH := 72
const POWER_TEXT_WIDTH := 350
const MOVEMENT: Array[Array] = [
	[[KEY_W, KEY_A, KEY_S, KEY_D], "Se déplacer"],
	[["Souris"], "Regarder"],
	[["Maj"], "Courir"],
	[[KEY_F], "Allumer ou éteindre la lampe"],
	[[KEY_E], "Se cacher, interagir"],
	[[KEY_M], "Plan de l'hôpital"],
]
const POWERS: Array[Array] = [
	[[KEY_1], "Onde de choc : étourdit le monstre 3 s, à moins de 8 m"],
	[[KEY_2], "Vision spectrale : le monstre visible à travers les murs, 5 s"],
	[[KEY_3], "Accélération : vitesse x1.5 pendant 5 s"],
	[[KEY_4], "Piège spectral : ralentit le monstre qui marche dessus"],
]
const SYSTEM: Array[Array] = [
	[["Échap"], "Pause"],
	[[KEY_F11], "Plein écran"],
	[["+", "-"], "Luminosité"],
]

@onready var _movement: VBoxContainer = %Movement
@onready var _powers: VBoxContainer = %Powers
@onready var _system: VBoxContainer = %System
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_fill(_movement, MOVEMENT, MOVEMENT_KEYS_WIDTH)
	_fill(_powers, POWERS, RIGHT_KEYS_WIDTH)
	_fill(_system, SYSTEM, RIGHT_KEYS_WIDTH)
	_back_button.pressed.connect(close)
	_back_button.mouse_entered.connect(_back_button.grab_focus)
	# Retour est le seul élément sélectionnable : les flèches ne sortent pas.
	for side: StringName in [&"focus_neighbor_top", &"focus_neighbor_bottom", &"focus_neighbor_left", &"focus_neighbor_right"]:
		_back_button.set(side, _back_button.get_path_to(_back_button))


func open() -> void:
	show()
	_back_button.grab_focus.call_deferred()


func close() -> void:
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _fill(column: VBoxContainer, rows: Array[Array], keys_width: float) -> void:
	for row: Array in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 6)
		keys.custom_minimum_size.x = keys_width
		keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for key: Variant in row[0]:
			keys.add_child(KeyNames.cap(key))
		line.add_child(keys)
		var action := Label.new()
		action.theme_type_variation = "FieldValueLabel"
		action.text = row[1]
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if column == _powers:
			action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			action.custom_minimum_size.x = POWER_TEXT_WIDTH
		line.add_child(action)
		column.add_child(line)

