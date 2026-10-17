extends CharacterBody3D
## LOST MEMORY - Personne 1 : joueur FPS, sprint, sacrifices permanents.
## Contrat V3. Player ne valide pas les sacrifices (PowerManager le fait)
## et ne possede pas la liste des pouvoirs.

signal sacrifice_applied(sacrifice_id: String)
signal player_died

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

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("player")
	_register_default_inputs()
	camera.current = true
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
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()


# =======================================================================
# PRIVE
# =======================================================================

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