class_name SacrificeMoment
extends Control
## Le moment où l'on perd quelque chose : l'écran bat en rouge comme un cœur,
## puis la phrase de la perte s'écrit en grand au centre avant de rejoindre la
## liste des sacrifices.

const PULSE_COLOR := Color(0.6, 0.02, 0.02)
const PHRASE_COLOR := Color("d23a2e")
const PHRASE_SIZE := 58
const WRITE_TIME := 1.1
const HOLD_TIME := 1.4
const FLY_TIME := 0.8
const FLY_SCALE := 0.35
## Double battement : [opacité, durée] pour chaque étape.
const HEARTBEAT: Array[Vector2] = [
	Vector2(0.75, 0.08), Vector2(0.2, 0.16), Vector2(0.6, 0.08), Vector2(0.0, 1.3),
]

var _pulse: TextureRect
var _phrase: Label
var _pulse_tween: Tween
var _phrase_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse = TextureRect.new()
	_pulse.texture = _vignette_texture()
	_pulse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pulse.stretch_mode = TextureRect.STRETCH_SCALE
	_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_pulse)
	_phrase = Label.new()
	_phrase.theme_type_variation = "HandLabel"
	_phrase.add_theme_font_size_override("font_size", PHRASE_SIZE)
	_phrase.add_theme_color_override("font_color", PHRASE_COLOR)
	_phrase.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_phrase.add_theme_constant_override("outline_size", 10)
	_phrase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phrase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phrase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phrase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_phrase)
	stop()


## Joue le moment pour la phrase donnée ; `target` est le point (global) de la
## liste des sacrifices que la phrase rejoint en s'effaçant.
func play(text: String, target: Vector2) -> void:
	stop()
	show()
	_phrase.text = text
	_phrase.visible_ratio = 0.0
	_phrase.pivot_offset = size / 2.0
	_pulse_tween = create_tween()
	for beat: Vector2 in HEARTBEAT:
		_pulse_tween.tween_property(_pulse, "modulate:a", beat.x, beat.y)
	_phrase_tween = create_tween()
	_phrase_tween.tween_property(_phrase, "visible_ratio", 1.0, WRITE_TIME)
	_phrase_tween.tween_interval(HOLD_TIME)
	_phrase_tween.set_parallel(true)
	_phrase_tween.tween_property(_phrase, "position", target - get_global_rect().get_center(), FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_phrase_tween.tween_property(_phrase, "scale", Vector2.ONE * FLY_SCALE, FLY_TIME)
	_phrase_tween.tween_property(_phrase, "modulate:a", 0.0, FLY_TIME)
	_phrase_tween.chain().tween_callback(hide)


func stop() -> void:
	for tween: Tween in [_pulse_tween, _phrase_tween]:
		if tween != null:
			tween.kill()
	_pulse.modulate.a = 0.0
	_phrase.position = Vector2.ZERO
	_phrase.scale = Vector2.ONE
	_phrase.modulate.a = 1.0
	hide()


## Bords rouges, centre transparent : le cœur bat dans la vision périphérique.
func _vignette_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(PULSE_COLOR, 0.0))
	gradient.set_color(1, Color(PULSE_COLOR, 0.95))
	gradient.add_point(0.62, Color(PULSE_COLOR, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
