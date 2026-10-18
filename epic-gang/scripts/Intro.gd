extends Control
## Intro : l'histoire en quelques fiches tapées à la machine.
## Entrée, Espace ou clic : termine la ligne en cours, puis passe à la suite.
## Maintenir Échap : passe directement au tutoriel.

const TUTORIAL_SCENE := "res://scenes/Tutorial.tscn"
const TYPE_SPEED := 0.035
const FADE_DURATION := 0.8

const CARDS: Array[String] = [
	"Tu te réveilles sur un brancard.\nTu ne te souviens de rien. Ni de ton nom, ni de la raison de ta présence ici.",
	"L'hôpital est vide. Les néons grésillent.\nQuelque chose marche dans les couloirs. Il t'entend.",
	"Quatre pouvoirs sont cachés dans les salles.\nChacun exige un sacrifice : une partie de toi, pour toujours.",
	"Retrouve tous les secrets pour ouvrir la sortie.\nLes pouvoirs peuvent t'aider, mais ils ne sont pas obligatoires.",
]

@onready var _card: Label = %Card
@onready var _counter: Label = %Counter
@onready var _hint: Label = %Hint
@onready var _skip: Control = %HoldToSkip
@onready var _fade: ColorRect = %Fade

var _index := -1
var _tween: Tween
var _leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_skip.skipped.connect(_leave)
	_next_card()


func _unhandled_input(event: InputEvent) -> void:
	var advance: bool = event.is_action_pressed("ui_accept") \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not advance or _leaving:
		return
	get_viewport().set_input_as_handled()
	if _card.visible_ratio < 1.0:
		_tween.kill()
		_card.visible_ratio = 1.0
		_hint.show()
	else:
		_next_card()


func _next_card() -> void:
	_index += 1
	if _index >= CARDS.size():
		_leave()
		return
	_card.text = CARDS[_index]
	_counter.text = "%d / %d" % [_index + 1, CARDS.size()]
	_card.visible_ratio = 0.0
	_hint.hide()
	_tween = create_tween()
	_tween.tween_property(_card, "visible_ratio", 1.0, tr(CARDS[_index]).length() * TYPE_SPEED)
	_tween.tween_callback(_hint.show)


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	var fade := create_tween()
	fade.tween_property(_fade, "modulate:a", 1.0, FADE_DURATION)
	fade.tween_callback(get_tree().change_scene_to_file.bind(TUTORIAL_SCENE))
