extends Control
## "Maintenir [Échap] pour passer" : la jauge se remplit tant qu'on garde
## Échap enfoncé, et se vide dès qu'on relâche. Émet `skipped` une fois pleine.

signal skipped

const HOLD_DURATION := 1.0
const DRAIN_SPEED := 2.5

@export var text := "Maintenir Échap pour passer"

@onready var _label: Label = %Label
@onready var _gauge: ProgressBar = %Gauge

var _held := 0.0
var _done := false


func _ready() -> void:
	_label.text = text


func _process(delta: float) -> void:
	if _done:
		return
	if Input.is_action_pressed("ui_cancel"):
		_held += delta
	else:
		_held = maxf(_held - delta * DRAIN_SPEED, 0.0)
	_gauge.value = _held / HOLD_DURATION * 100.0
	if _held >= HOLD_DURATION:
		_done = true
		skipped.emit()
