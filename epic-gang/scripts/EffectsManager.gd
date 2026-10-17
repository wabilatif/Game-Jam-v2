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
var _spectral_tint: ColorRect
var _spectral_tween: Tween
var _xray_material: StandardMaterial3D
var _revealed_meshes: Array[MeshInstance3D] = []

const SPECTRAL_TINT := Color(0.35, 0.55, 0.75, 0.16)

## Luminosite reglable par le joueur (1.0 = rendu d'origine du niveau, trop
## sombre pour beaucoup). Memorisee entre les parties dans user://settings.cfg.
signal brightness_changed(value: float)

const BRIGHTNESS_MIN: float = 0.6
const BRIGHTNESS_MAX: float = 3.0
const BRIGHTNESS_STEP: float = 0.1
const BRIGHTNESS_DEFAULT: float = 1.8
const SETTINGS_PATH: String = "user://settings.cfg"

var _brightness: float = BRIGHTNESS_DEFAULT


func _ready() -> void:
	_load_settings()
	_setup_overlay()


# ---------------------------------------------------------------------------
# API PUBLIQUE
# ---------------------------------------------------------------------------

## Luminosite actuelle (entre BRIGHTNESS_MIN et BRIGHTNESS_MAX).
func get_brightness() -> float:
	return _brightness


## Regle la luminosite (bornee, arrondie au pas), la sauvegarde et previent
## le niveau (Hospital) et les menus via brightness_changed.
func set_brightness(value: float) -> void:
	var clamped: float = snappedf(clampf(value, BRIGHTNESS_MIN, BRIGHTNESS_MAX), BRIGHTNESS_STEP)
	if is_equal_approx(clamped, _brightness):
		return
	_brightness = clamped
	_save_settings()
	brightness_changed.emit(_brightness)


func change_brightness(delta_steps: int) -> void:
	set_brightness(_brightness + delta_steps * BRIGHTNESS_STEP)


## Perte de vue : vignette sombre permanente (appelée par Main sur "vision").
func set_vision_effect(impaired: bool) -> void:
	if _vision_tween:
		_vision_tween.kill()
	_vision_tween = create_tween()
	_vision_tween.tween_property(_vignette_mat, "shader_parameter/strength", 0.9 if impaired else 0.0, 1.0)


## Vision spectrale : teinte froide à l'écran et monstre visible en rouge
## à travers les murs. Indépendante de la perte de vue (set_vision_effect).
func set_spectral_vision(enabled: bool) -> void:
	if _spectral_tween:
		_spectral_tween.kill()
	_spectral_tween = create_tween()
	_spectral_tween.tween_property(_spectral_tint, "color:a", SPECTRAL_TINT.a if enabled else 0.0, 0.4)
	_set_monster_xray(enabled)


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
	if _spectral_tween:
		_spectral_tween.kill()
	_spectral_tint.color.a = 0.0
	_set_monster_xray(false)
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

	_spectral_tint = ColorRect.new()
	_spectral_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectral_tint.color = Color(SPECTRAL_TINT, 0.0)
	layer.add_child(_spectral_tint)
	_spectral_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Matériau superposé au monstre : ignore la profondeur, donc visible
	# à travers les murs.
	_xray_material = StandardMaterial3D.new()
	_xray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_xray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_xray_material.no_depth_test = true
	_xray_material.disable_fog = true
	_xray_material.albedo_color = Color(0.95, 0.1, 0.06, 0.85)
	_xray_material.render_priority = 10

	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	layer.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var saved: float = float(config.get_value("display", "brightness", BRIGHTNESS_DEFAULT))
	_brightness = snappedf(clampf(saved, BRIGHTNESS_MIN, BRIGHTNESS_MAX), BRIGHTNESS_STEP)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH) # conserve les autres reglages eventuels
	config.set_value("display", "brightness", _brightness)
	config.save(SETTINGS_PATH)


func _set_monster_xray(enabled: bool) -> void:
	for mesh in _revealed_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
	_revealed_meshes.clear()
	if not enabled:
		return
	for monster in get_tree().get_nodes_in_group("monster"):
		for mesh: MeshInstance3D in monster.find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = _xray_material
			_revealed_meshes.append(mesh)
