extends CharacterBody3D
## LOST MEMORY - Personne 1 : joueur FPS, sprint, sacrifices permanents.
## Contrat V3. Player ne valide pas les sacrifices (PowerManager le fait)
## et ne possede pas la liste des pouvoirs.

signal sacrifice_applied(sacrifice_id: String)
signal player_died
## Hors contrat (bonus) : pour l'AudioManager / l'UI.
signal footstep(is_sprinting: bool)
signal flashlight_toggled(is_on: bool)

# --- Valeurs du contrat -------------------------------------------------
const BASE_SPEED: float = 5.0
const LEG_MULTIPLIER: float = 0.75
## Hors contrat (valeur propre a Player, annoncee a l'equipe). Le sprint
## s'ajoute a get_movement_speed() uniquement tant que le joueur sprinte.
const SPRINT_MULTIPLIER: float = 1.6
const SPRINT_TIME_NORMAL: float = 4.0
const SPRINT_TIME_STAMINA: float = 2.0
const STAMINA_RECOVERY_TIME: float = 3.0

const VALID_SACRIFICES: Array[String] = ["hearing", "leg", "vision", "stamina"]
const POWER_KEYS: Array[String] = [
	"shockwave", "spectral_vision", "speed_boost", "spectral_trap"
]

const MOUSE_SENSITIVITY: float = 0.002
const AIM_MAX_DISTANCE: float = 50.0
const MAX_PITCH: float = 1.553343 # 89 degres en radians (evite deg_to_rad en const)

# --- Bonus "feeling" (hors contrat, purement cosmetique) ------------------
const ACCELERATION: float = 40.0        # m/s^2 pour atteindre la vitesse voulue
const DECELERATION: float = 55.0        # m/s^2 pour s'arreter (freinage net)
const BOB_FREQUENCY: float = 1.3        # radians par metre parcouru
const BOB_AMPLITUDE: float = 0.035      # metres
const SPRINT_FOV_BONUS: float = 12.0
const SPRINT_BOB_MULTIPLIER: float = 1.8 # balancement plus fort en sprint
const SPRINT_ROLL: float = 0.026         # ~1.5 degres d'inclinaison a chaque pas
const ROLL_SMOOTHING: float = 8.0
const BOOST_FOV_BONUS: float = 5.0
const FOV_SMOOTHING: float = 8.0
const FLASHLIGHT_RANGE: float = 18.0
const FLASHLIGHT_ANGLE: float = 32.0
const FLASHLIGHT_ENERGY: float = 3.0

## Hors contrat : lampe torche (touche F), allumee au depart.
@export var flashlight_on_at_start: bool = true

## Hors contrat : si true, Player ecoute les touches 1 a 4 et appelle
## PowerManager.activate_power. Mettre a false si l'UI ou Main gere deja
## les raccourcis (evite le double declenchement).
@export var handle_power_keys: bool = true

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _applied_sacrifices: Array[String] = []
var _controls_enabled: bool = true
var _dead: bool = false

var _speed_modifier: float = 1.0
var _speed_modifier_time_left: float = 0.0

var _stamina: float = SPRINT_TIME_NORMAL
var _exhausted: bool = false
var _is_sprinting: bool = false

var _flashlight: SpotLight3D
var _base_fov: float = 75.0
var _camera_base_y: float = 0.0
var _bob_phase: float = 0.0
var _last_step_index: int = 0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("player")
	_register_default_inputs()
	camera.current = true
	_base_fov = camera.fov
	_camera_base_y = camera.position.y
	_create_flashlight()
	set_flashlight(flashlight_on_at_start)
	set_controls_enabled(true)


# =======================================================================
# API PUBLIQUE (contrat V3)
# =======================================================================

func apply_sacrifice(sacrifice_id: String) -> bool:
	if not VALID_SACRIFICES.has(sacrifice_id):
		push_warning("Player: sacrifice inconnu '%s'" % sacrifice_id)
		return false
	if has_sacrifice(sacrifice_id):
		return false

	_applied_sacrifices.append(sacrifice_id)

	# Effets geres par Player. hearing et vision sont geres par
	# AudioManager / EffectsManager via le signal ci-dessous (Main.gd).
	if sacrifice_id == "stamina":
		_stamina = minf(_stamina, _get_max_sprint_time())

	sacrifice_applied.emit(sacrifice_id)
	return true


func has_sacrifice(sacrifice_id: String) -> bool:
	return _applied_sacrifices.has(sacrifice_id)


func get_applied_sacrifices() -> Array[String]:
	return _applied_sacrifices.duplicate()


## Vitesse effective actuelle = base x sacrifice x temporaire (x sprint si actif).
func get_movement_speed() -> float:
	var speed: float = BASE_SPEED
	if has_sacrifice("leg"):
		speed *= LEG_MULTIPLIER
	speed *= _speed_modifier
	if _is_sprinting:
		speed *= SPRINT_MULTIPLIER
	return speed


## Multiplicateur temporaire. Un nouvel appel remplace le precedent.
func apply_speed_modifier(factor: float, duration: float) -> void:
	if factor <= 0.0 or duration <= 0.0:
		return
	_speed_modifier = factor
	_speed_modifier_time_left = duration


func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		velocity.x = 0.0
		velocity.z = 0.0
		_is_sprinting = false


func get_aim_position() -> Vector3:
	var origin: Vector3 = camera.global_position
	var target: Vector3 = origin + get_aim_direction() * AIM_MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return target
	return hit["position"]


func get_aim_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized()


## Bonus : endurance restante entre 0.0 et 1.0 (pour une barre de sprint).
func get_stamina_ratio() -> float:
	return clampf(_stamina / _get_max_sprint_time(), 0.0, 1.0)


## Bonus : true si le joueur est en train de sprinter.
func is_sprinting() -> bool:
	return _is_sprinting


## Bonus : true si le joueur est epuise (sprint bloque jusqu'a recuperation).
func is_exhausted() -> bool:
	return _exhausted


func set_flashlight(on: bool) -> void:
	if _flashlight == null:
		return
	if _flashlight.visible == on:
		return
	_flashlight.visible = on
	flashlight_toggled.emit(on)


func is_flashlight_on() -> bool:
	return _flashlight != null and _flashlight.visible


func reset_player() -> void:
	_applied_sacrifices.clear()
	_speed_modifier = 1.0
	_speed_modifier_time_left = 0.0
	_stamina = SPRINT_TIME_NORMAL
	_exhausted = false
	_is_sprinting = false
	_dead = false
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	_bob_phase = 0.0
	_last_step_index = 0
	camera.position.y = _camera_base_y
	camera.rotation.z = 0.0
	camera.fov = _base_fov
	set_flashlight(flashlight_on_at_start)
	set_controls_enabled(true)


## Hors contrat : utile pour tests et dangers (non utilise par le monstre,
## qui emet monster_caught_player). Emet player_died, que Main/GameManager
## relie a end_game(false, "player_died").
func die() -> void:
	if _dead:
		return
	_dead = true
	set_controls_enabled(false)
	player_died.emit()


# =======================================================================
# BOUCLE
# =======================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled or _dead:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-motion.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, -MAX_PITCH, MAX_PITCH)
		return

	if event.is_action_pressed("flashlight"):
		set_flashlight(not is_flashlight_on())
		return

	if not handle_power_keys:
		return
	for i in range(POWER_KEYS.size()):
		if event.is_action_pressed("power_%d" % (i + 1)):
			_request_power(POWER_KEYS[i])
			return


func _physics_process(delta: float) -> void:
	_update_speed_modifier(delta)

	var direction: Vector3 = Vector3.ZERO
	var wants_sprint: bool = false
	if _controls_enabled and not _dead:
		var input_dir: Vector2 = Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
		direction = (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		wants_sprint = Input.is_action_pressed("sprint") and input_dir != Vector2.ZERO

	_update_stamina(delta, wants_sprint)

	var speed: float = get_movement_speed()
	var target_velocity := Vector2(direction.x, direction.z) * speed
	var current_velocity := Vector2(velocity.x, velocity.z)
	var rate: float = ACCELERATION if target_velocity != Vector2.ZERO else DECELERATION
	current_velocity = current_velocity.move_toward(target_velocity, rate * delta)
	velocity.x = current_velocity.x
	velocity.z = current_velocity.y

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()


func _process(delta: float) -> void:
	_update_head_bob(delta)
	_update_fov(delta)


# =======================================================================
# PRIVE
# =======================================================================

func _create_flashlight() -> void:
	_flashlight = SpotLight3D.new()
	_flashlight.name = "Flashlight"
	_flashlight.spot_range = FLASHLIGHT_RANGE
	_flashlight.spot_angle = FLASHLIGHT_ANGLE
	_flashlight.spot_attenuation = 0.8
	_flashlight.light_energy = FLASHLIGHT_ENERGY
	_flashlight.shadow_enabled = true
	camera.add_child(_flashlight)


func _update_head_bob(delta: float) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var moving: bool = horizontal_speed > 0.5 and is_on_floor()
	var target_roll: float = 0.0
	if moving:
		_bob_phase += horizontal_speed * BOB_FREQUENCY * delta
		var step_index: int = int(floor(_bob_phase / PI))
		if step_index != _last_step_index:
			_last_step_index = step_index
			footstep.emit(_is_sprinting)
		var amplitude: float = BOB_AMPLITUDE * (SPRINT_BOB_MULTIPLIER if _is_sprinting else 1.0)
		camera.position.y = _camera_base_y + sin(_bob_phase) * amplitude
		# En sprint, la tete penche d'un cote puis de l'autre a chaque pas.
		if _is_sprinting:
			target_roll = sin(_bob_phase * 0.5) * SPRINT_ROLL
	else:
		camera.position.y = lerpf(camera.position.y, _camera_base_y, minf(10.0 * delta, 1.0))
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, minf(ROLL_SMOOTHING * delta, 1.0))


func _update_fov(delta: float) -> void:
	var target_fov: float = _base_fov
	if _is_sprinting:
		target_fov += SPRINT_FOV_BONUS
	if _speed_modifier > 1.0:
		target_fov += BOOST_FOV_BONUS
	camera.fov = lerpf(camera.fov, target_fov, minf(FOV_SMOOTHING * delta, 1.0))


func _get_max_sprint_time() -> float:
	return SPRINT_TIME_STAMINA if has_sacrifice("stamina") else SPRINT_TIME_NORMAL


func _update_speed_modifier(delta: float) -> void:
	if _speed_modifier_time_left <= 0.0:
		return
	_speed_modifier_time_left -= delta
	if _speed_modifier_time_left <= 0.0:
		_speed_modifier = 1.0
		_speed_modifier_time_left = 0.0


func _update_stamina(delta: float, wants_sprint: bool) -> void:
	var max_time: float = _get_max_sprint_time()
	if wants_sprint and not _exhausted and _stamina > 0.0:
		_is_sprinting = true
		_stamina = maxf(_stamina - delta, 0.0)
		if _stamina <= 0.0:
			_exhausted = true
			_is_sprinting = false
	else:
		_is_sprinting = false
		# Recuperation complete (depuis zero) en STAMINA_RECOVERY_TIME secondes.
		_stamina = minf(_stamina + (max_time / STAMINA_RECOVERY_TIME) * delta, max_time)
		if _exhausted and _stamina >= max_time:
			_exhausted = false


func _request_power(power_id: String) -> void:
	# get_node_or_null : Player peut etre teste seul, sans l'Autoload.
	var power_manager: Node = get_node_or_null("/root/PowerManager")
	if power_manager == null:
		push_warning("Player: PowerManager introuvable (test isole ?)")
		return
	if power_manager.has_method("activate_power"):
		power_manager.activate_power(power_id)


## Cree les actions d'entree si elles n'existent pas (touches physiques :
## sur AZERTY, W/A/S/D physiques = Z/Q/S/D). Modifiable dans Project Settings.
func _register_default_inputs() -> void:
	var defaults: Dictionary = {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"sprint": KEY_SHIFT,
		"flashlight": KEY_F,
		"power_1": KEY_1,
		"power_2": KEY_2,
		"power_3": KEY_3,
		"power_4": KEY_4,
	}
	for action: String in defaults:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = defaults[action]
		InputMap.action_add_event(action, key_event)