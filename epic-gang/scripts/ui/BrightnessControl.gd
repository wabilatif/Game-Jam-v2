extends HBoxContainer
## LOST MEMORY - Reglage de luminosite (menu pause et menu principal).
## Ne stocke rien : la valeur vit dans EffectsManager (sauvegardee entre les
## parties). Fleches gauche/droite quand le slider a le focus, ou souris.

@onready var _slider: HSlider = %Slider
@onready var _value_label: Label = %Value

var _effects: Node


func _ready() -> void:
	_effects = get_node_or_null("/root/EffectsManager")
	if _effects == null:
		visible = false
		return
	_slider.min_value = _effects.BRIGHTNESS_MIN * 100.0
	_slider.max_value = _effects.BRIGHTNESS_MAX * 100.0
	_slider.step = _effects.BRIGHTNESS_STEP * 100.0
	_slider.set_value_no_signal(_effects.get_brightness() * 100.0)
	_update_label(_effects.get_brightness())
	_slider.value_changed.connect(_on_slider_changed)
	_effects.brightness_changed.connect(_on_brightness_changed)
	_slider.mouse_entered.connect(_slider.grab_focus)


func _on_slider_changed(value: float) -> void:
	_effects.set_brightness(value / 100.0)


## Changement venu d'ailleurs (raccourcis clavier en jeu) : on suit.
func _on_brightness_changed(value: float) -> void:
	_slider.set_value_no_signal(value * 100.0)
	_update_label(value)


func _update_label(value: float) -> void:
	_value_label.text = "%d %%" % roundi(value * 100.0)
