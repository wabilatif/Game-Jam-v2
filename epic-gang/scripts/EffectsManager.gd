extends Node
## EffectsManager — Personne 6 (Lost Memory)
## A enregistrer en Autoload sous le nom "EffectsManager".
## Gère les effets visuels : vignette de perte de vue, flashs d'écran, lumières de pouvoirs.
## N'a pas besoin d'accéder à la caméra du joueur : tout passe par un CanvasLayer.

var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _flash: ColorRect
var _vision_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	_setup_overlay()


# ---------------------------------------------------------------------------
# API PUBLIQUE
# ---------------------------------------------------------------------------

## Perte de vue : vignette sombre permanente (appelée par Main sur "vision").
func set_vision_effect(impaired: bool) -> void:
	if _vision_tween:
		_vision_tween.kill()
	_vision_tween = create_tween()
	_vision_tween.tween_property(_vignette_mat, "shader_parameter/strength", 0.9 if impaired else 0.0, 1.0)


## Flash plein écran qui s'estompe.
func flash_screen(color: Color, duration: float) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash.color = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, duration)


## Flash de lumière coloré à une position 3D (effet provisoire de pouvoir).
func spawn_power_light(position: Vector3, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = 10.0
	scene.add_child(light)
	light.global_position = position
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.6)
	tween.tween_callback(light.queue_free)


## A appeler par Main à la relance de partie.
func reset_effects() -> void:
	if _vision_tween:
		_vision_tween.kill()
	if _flash_tween:
		_flash_tween.kill()
	_vignette_mat.set_shader_parameter("strength", 0.0)
	_flash.color = Color(1, 1, 1, 0)


# ---------------------------------------------------------------------------
# PRIVE
# ---------------------------------------------------------------------------

func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float v = smoothstep(0.15, 0.75, length(uv));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("strength", 0.0)

	_vignette_mat = mat
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.material = mat
	layer.add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	layer.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
