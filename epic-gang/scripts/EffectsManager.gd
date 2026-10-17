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
var _xray_material: ShaderMaterial
var _revealed_meshes: Array[MeshInstance3D] = []
## Effets "dans le monde", sous le HUD : une seule passe (world_fx.gdshader).
var _world_fx: ColorRect
var _world_mat: ShaderMaterial
var _world_tweens: Dictionary[String, Tween] = {}

const WORLD_FX_LAYER := 1
const WORLD_UNIFORMS: Array[String] = ["vision", "spectral", "boost", "shock"]
const SHOCK_DURATION := 0.75
const SHAKE_DURATION := 0.35
const SHAKE_STRENGTH := 0.06
const BOOST_DURATION := 5.0

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
	_tween_world("vision", 1.0 if impaired else 0.0, 1.5)


## Vision spectrale : le monde passe en bleu froid qui tremble, et le monstre
## apparaît avec un contour rouge pulsant, à travers les murs. Indépendante de
## la perte de vue (set_vision_effect).
func set_spectral_vision(enabled: bool) -> void:
	_tween_world("spectral", 1.0 if enabled else 0.0, 0.4)
	_set_monster_xray(enabled)


## Effet visuel d'un pouvoir activé. `position` : poitrine du joueur.
func play_power_vfx(power_id: String, position: Vector3) -> void:
	match power_id:
		"shockwave":
			_play_shockwave(position)
		"speed_boost":
			_tween_world("boost", 1.0, 0.15)
			_world_tweens["boost"].tween_interval(BOOST_DURATION - 0.55)
			_world_tweens["boost"].tween_method(_set_world.bind("boost"), 1.0, 0.0, 0.4)


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
	# Assez pour marquer l'activation sans saturer le brouillard.
	light.light_energy = 2.5
	light.omni_range = 6.0
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
	for uniform: String in WORLD_UNIFORMS:
		if _world_tweens.has(uniform):
			_world_tweens[uniform].kill()
		_set_world(0.0, uniform)
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

	# Calque "monde" sous le HUD (couche 10) : le décor est touché, pas le texte.
	var world_layer := CanvasLayer.new()
	world_layer.layer = WORLD_FX_LAYER
	add_child(world_layer)
	_world_mat = ShaderMaterial.new()
	_world_mat.shader = load("res://assets/vfx/world_fx.gdshader")
	_world_fx = ColorRect.new()
	_world_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_fx.material = _world_mat
	_world_fx.visible = false
	world_layer.add_child(_world_fx)
	_world_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Contour du monstre en vision spectrale : ignore la profondeur, donc
	# visible à travers les murs.
	_xray_material = ShaderMaterial.new()
	_xray_material.shader = load("res://assets/vfx/spectral_outline.gdshader")
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


func _set_world(value: float, uniform: String) -> void:
	_world_mat.set_shader_parameter(uniform, value)
	# Le calque ne coûte rien quand aucun effet n'est actif.
	_world_fx.visible = WORLD_UNIFORMS.any(func(u: String) -> bool:
		var v: Variant = _world_mat.get_shader_parameter(u)
		return v != null and float(v) > 0.001)


func _tween_world(uniform: String, target: float, duration: float) -> void:
	if _world_tweens.has(uniform):
		_world_tweens[uniform].kill()
	var current: Variant = _world_mat.get_shader_parameter(uniform)
	var tween := create_tween()
	tween.tween_method(_set_world.bind(uniform), 0.0 if current == null else float(current), target, duration)
	_world_tweens[uniform] = tween


## Onde de choc : anneau qui déforme l'air autour du joueur, secousse de la
## caméra et poussière soulevée au sol.
func _play_shockwave(position: Vector3) -> void:
	# L'onde part du joueur, donc du centre de son regard.
	_world_mat.set_shader_parameter("shock_center", Vector2(0.5, 0.55))
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_shake(camera)
	if _world_tweens.has("shock"):
		_world_tweens["shock"].kill()
	var tween := create_tween()
	tween.tween_method(_set_world.bind("shock"), 0.001, 1.0, SHOCK_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_set_world.bind(0.0, "shock"))
	_world_tweens["shock"] = tween
	_spawn_dust(position - Vector3.UP * 1.2)


func _shake(camera: Camera3D) -> void:
	var tween := create_tween()
	var steps := 7
	for i in steps:
		var amount := SHAKE_STRENGTH * (1.0 - float(i) / steps)
		tween.tween_property(camera, "h_offset", randf_range(-amount, amount), SHAKE_DURATION / steps)
		tween.parallel().tween_property(camera, "v_offset", randf_range(-amount, amount), SHAKE_DURATION / steps)
	tween.tween_property(camera, "h_offset", 0.0, 0.05)
	tween.parallel().tween_property(camera, "v_offset", 0.0, 0.05)


## Anneau de poussière qui part du sol.
func _spawn_dust(ground: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.4
	process.emission_ring_inner_radius = 0.2
	process.emission_ring_height = 0.05
	process.direction = Vector3.UP
	process.spread = 25.0
	process.radial_velocity_min = 5.0
	process.radial_velocity_max = 8.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.0
	process.gravity = Vector3(0, -1.5, 0)
	process.damping_min = 4.0
	process.damping_max = 6.0
	process.scale_min = 0.6
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(0.75, 0.78, 0.82, 0.5))
	fade.set_color(1, Color(0.75, 0.78, 0.82, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	var dust := GPUParticles3D.new()
	dust.amount = 48
	dust.lifetime = 0.9
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.process_material = process
	dust.draw_pass_1 = quad
	scene.add_child(dust)
	dust.global_position = ground
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
