extends CharacterBody3D
## LOST MEMORY - Personne 1 : joueur FPS, sprint, sacrifices permanents.
## Contrat V3. Player ne valide pas les sacrifices (PowerManager le fait)
## et ne possede pas la liste des pouvoirs.

signal sacrifice_applied(sacrifice_id: String)
signal player_died
## Hors contrat (bonus) : pour l'AudioManager / l'UI.
signal footstep(is_sprinting: bool)
signal flashlight_toggled(is_on: bool)
signal hidden_state_changed(is_hidden: bool)

# --- Valeurs du contrat -------------------------------------------------
const BASE_SPEED: float = 5.0
const LEG_MULTIPLIER: float = 0.75
## Hors contrat (valeur propre a Player, annoncee a l'equipe). Le sprint
## s'ajoute a get_movement_speed() uniquement tant que le joueur sprinte.
const SPRINT_MULTIPLIER: float = 1.6
const SPRINT_TIME_NORMAL: float = 4.0
const SPRINT_TIME_STAMINA: float = 2.0
const STAMINA_RECOVERY_TIME: float = 3.0

## Sacrifices du contrat (hearing, leg, vision, stamina) + sacrifices ajoutes :
##   arm       : les pouvoirs rechargent plus lentement (gere par PowerManager)
##   heart     : le souffle recupere deux fois moins vite
##   reflexes  : la camera repond moins bien (sensibilite reduite)
##   light     : la lampe torche faiblit
##   memory    : la mini-map disparait (HUD/MiniMap, gere par lecture de has_sacrifice)
const VALID_SACRIFICES: Array[String] = [
	"hearing", "leg", "vision", "stamina",
	"arm", "heart", "reflexes", "light", "memory",
]
const HEART_RECOVERY_MULTIPLIER: float = 0.5
const REFLEXES_SENSITIVITY_MULTIPLIER: float = 0.55
const LIGHT_ENERGY_MULTIPLIER: float = 0.45
const LIGHT_RANGE_MULTIPLIER: float = 0.55
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

# --- Bonus "corps" : mains et pieds proceduraux (aucun asset requis) -------
const SKIN_COLOR: Color = Color(0.78, 0.62, 0.52)
const SLEEVE_COLOR: Color = Color(0.55, 0.58, 0.6)   # blouse d'hopital
const PANTS_COLOR: Color = Color(0.5, 0.53, 0.55)
const SHOE_COLOR: Color = Color(0.14, 0.14, 0.16)
const HAND_REST_RIGHT: Vector3 = Vector3(0.24, -0.27, -0.45)
const HAND_REST_LEFT: Vector3 = Vector3(-0.24, -0.29, -0.43)
const FOOT_REST_Z: float = -0.08
const FOOT_SPACING: float = 0.11

## Hors contrat : mains visibles en vue FPS (la droite tient la lampe).
@export var show_hands: bool = true
## Hors contrat : pieds visibles quand on regarde vers le bas.
@export var show_feet: bool = true

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

var _is_hidden: bool = false
var _current_hiding_spot: Node3D = null
var _nearby_hiding_spot: Node3D = null
var _saved_collision_mask: int = 1
var _saved_collision_layer: int = 1
var _saved_flashlight_state: bool = false
var _hiding_yaw_center: float = 0.0
const HIDING_YAW_LIMIT: float = 1.05

var _hands_root: Node3D
var _right_hand: Node3D
var _left_hand: Node3D
var _feet_root: Node3D
var _left_foot: Node3D
var _right_foot: Node3D
var _lens_material: StandardMaterial3D
var _gesture_tween: Tween
var _look_delta: Vector2 = Vector2.ZERO

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
	_create_viewmodel()
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
	elif sacrifice_id == "light":
		_refresh_flashlight_stats()

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
	_update_lens()
	flashlight_toggled.emit(on)


func is_flashlight_on() -> bool:
	return _flashlight != null and _flashlight.visible


func is_hidden() -> bool:
	return _is_hidden


func get_current_hiding_spot() -> Node3D:
	return _current_hiding_spot


func set_nearby_hiding_spot(spot: Node3D) -> void:
	_nearby_hiding_spot = spot


func clear_nearby_hiding_spot(spot: Node3D) -> void:
	if _nearby_hiding_spot == spot:
		_nearby_hiding_spot = null


func hide_in_spot(spot: Node3D) -> bool:
	if _dead or _is_hidden or spot == null or not _controls_enabled:
		return false
	if spot.has_method("is_occupied") and spot.is_occupied():
		return false
	if spot.has_method("hide_player") and not spot.hide_player(self):
		return false

	_is_hidden = true
	_current_hiding_spot = spot
	_saved_flashlight_state = is_flashlight_on()
	set_flashlight(false)
	velocity = Vector3.ZERO
	_is_sprinting = false

	var audio_mgr: Node = get_node_or_null("/root/AudioManager")
	if audio_mgr != null and audio_mgr.has_method("play_sfx"):
		audio_mgr.play_sfx("door_open")

	var hide_pos: Vector3 = spot.global_position
	var hide_rot: Vector3 = spot.global_rotation
	if spot.has_method("get_hiding_position"):
		hide_pos = spot.get_hiding_position()
	if spot.has_method("get_hiding_rotation"):
		hide_rot = spot.get_hiding_rotation()

	global_position = hide_pos
	rotation.y = hide_rot.y
	_hiding_yaw_center = hide_rot.y
	head.rotation.x = 0.0

	_saved_collision_mask = collision_mask
	_saved_collision_layer = collision_layer
	collision_mask = 0
	collision_layer = 0

	var ui_mgr: Node = get_node_or_null("/root/UIManager")
	if ui_mgr != null and ui_mgr.has_method("show_message"):
		ui_mgr.show_message(tr("Vous êtes caché. Le monstre s'éloigne..."), 3.0)

	hidden_state_changed.emit(true)
	return true


func exit_hiding_spot() -> void:
	if not _is_hidden or _current_hiding_spot == null:
		return

	var spot: Node3D = _current_hiding_spot
	_is_hidden = false
	_current_hiding_spot = null

	if spot.has_method("release_player"):
		spot.release_player(self)

	collision_mask = _saved_collision_mask
	collision_layer = _saved_collision_layer

	var exit_pos: Vector3 = global_position
	if spot.has_method("get_exit_position"):
		exit_pos = spot.get_exit_position()
	global_position = exit_pos

	var audio_mgr: Node = get_node_or_null("/root/AudioManager")
	if audio_mgr != null and audio_mgr.has_method("play_sfx"):
		audio_mgr.play_sfx("door_open")

	if _saved_flashlight_state:
		set_flashlight(true)

	var ui_mgr: Node = get_node_or_null("/root/UIManager")
	if ui_mgr != null and ui_mgr.has_method("show_message"):
		ui_mgr.show_message(tr("Vous êtes sorti de la cachette."), 1.5)

	hidden_state_changed.emit(false)


func reset_player() -> void:
	if _is_hidden and _current_hiding_spot != null:
		if _current_hiding_spot.has_method("release_player"):
			_current_hiding_spot.release_player(self)
	_is_hidden = false
	_current_hiding_spot = null
	_nearby_hiding_spot = null
	if _saved_collision_mask != 0:
		collision_mask = _saved_collision_mask
		collision_layer = _saved_collision_layer
	_applied_sacrifices.clear()
	_refresh_flashlight_stats()
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
	_look_delta = Vector2.ZERO
	if _gesture_tween != null:
		_gesture_tween.kill()
	if _hands_root != null:
		_hands_root.position = Vector3.ZERO
		_hands_root.rotation = Vector3.ZERO
		_right_hand.position = HAND_REST_RIGHT
		_right_hand.rotation = Vector3.ZERO
		_left_hand.position = HAND_REST_LEFT
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
		_look_delta = (_look_delta + motion.relative).limit_length(80.0)
		if _is_hidden:
			rotate_y(-motion.relative.x * _get_mouse_sensitivity())
			var diff := wrapf(rotation.y - _hiding_yaw_center, -PI, PI)
			diff = clampf(diff, -HIDING_YAW_LIMIT, HIDING_YAW_LIMIT)
			rotation.y = _hiding_yaw_center + diff
			head.rotate_x(-motion.relative.y * _get_mouse_sensitivity())
			head.rotation.x = clampf(head.rotation.x, -0.6, 0.6)
		else:
			rotate_y(-motion.relative.x * _get_mouse_sensitivity())
			head.rotate_x(-motion.relative.y * _get_mouse_sensitivity())
			head.rotation.x = clampf(head.rotation.x, -MAX_PITCH, MAX_PITCH)
		return

	if event.is_action_pressed("interact"):
		if _is_hidden:
			exit_hiding_spot()
		elif _nearby_hiding_spot != null and is_instance_valid(_nearby_hiding_spot):
			hide_in_spot(_nearby_hiding_spot)
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
	if _is_hidden:
		velocity = Vector3.ZERO
		return

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
	_update_hands(delta)
	_update_feet(delta)


# =======================================================================
# PRIVE
# =======================================================================

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _add_mesh(parent: Node3D, mesh: Mesh, material: Material,
		pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _create_viewmodel() -> void:
	if show_hands:
		_hands_root = Node3D.new()
		_hands_root.name = "Hands"
		camera.add_child(_hands_root)
		_right_hand = _build_hand(true)
		_right_hand.position = HAND_REST_RIGHT
		_hands_root.add_child(_right_hand)
		_left_hand = _build_hand(false)
		_left_hand.position = HAND_REST_LEFT
		_hands_root.add_child(_left_hand)
		_attach_flashlight_to_hand()
	if show_feet:
		_feet_root = Node3D.new()
		_feet_root.name = "Feet"
		add_child(_feet_root)
		_left_foot = _build_foot()
		_left_foot.position = Vector3(-FOOT_SPACING, 0.0, FOOT_REST_Z)
		_feet_root.add_child(_left_foot)
		_right_foot = _build_foot()
		_right_foot.position = Vector3(FOOT_SPACING, 0.0, FOOT_REST_Z)
		_feet_root.add_child(_right_foot)
	_update_lens()


## Main faite de boites et cylindres : avant-bras, manche, paume, 4 doigts
## replies, pouce. Le "devant" de la main est l'axe -Z.
func _build_hand(is_right: bool) -> Node3D:
	var hand := Node3D.new()
	hand.name = "RightHand" if is_right else "LeftHand"
	var side: float = 1.0 if is_right else -1.0
	var skin: StandardMaterial3D = _make_material(SKIN_COLOR)

	var palm := BoxMesh.new()
	palm.size = Vector3(0.085, 0.03, 0.09)
	_add_mesh(hand, palm, skin, Vector3.ZERO, Vector3.ZERO)

	for i in range(4):
		var finger := BoxMesh.new()
		finger.size = Vector3(0.017, 0.017, 0.07)
		_add_mesh(hand, finger, skin,
			Vector3(-0.03 + 0.02 * i, -0.008, -0.08), Vector3(-0.35, 0.0, 0.0))

	var thumb := BoxMesh.new()
	thumb.size = Vector3(0.02, 0.018, 0.05)
	_add_mesh(hand, thumb, skin,
		Vector3(-side * 0.05, -0.004, -0.02), Vector3(0.0, side * 0.5, 0.0))

	var forearm := CylinderMesh.new()
	forearm.top_radius = 0.042
	forearm.bottom_radius = 0.03
	forearm.height = 0.5
	_add_mesh(hand, forearm, skin, Vector3(0.0, 0.0, 0.30), Vector3(PI / 2.0, 0.0, 0.0))

	var sleeve := CylinderMesh.new()
	sleeve.top_radius = 0.058
	sleeve.bottom_radius = 0.05
	sleeve.height = 0.22
	_add_mesh(hand, sleeve, _make_material(SLEEVE_COLOR),
		Vector3(0.0, 0.0, 0.42), Vector3(PI / 2.0, 0.0, 0.0))
	return hand


func _build_foot() -> Node3D:
	var foot := Node3D.new()
	var shoe := BoxMesh.new()
	shoe.size = Vector3(0.10, 0.07, 0.26)
	_add_mesh(foot, shoe, _make_material(SHOE_COLOR), Vector3(0.0, 0.035, -0.04), Vector3.ZERO)
	var shin := CylinderMesh.new()
	shin.top_radius = 0.04
	shin.bottom_radius = 0.045
	shin.height = 0.3
	_add_mesh(foot, shin, _make_material(PANTS_COLOR), Vector3(0.0, 0.22, 0.04), Vector3.ZERO)
	return foot


## La lampe est tenue par la main droite : corps metal + verre qui s'allume.
func _attach_flashlight_to_hand() -> void:
	var metal: StandardMaterial3D = _make_material(Color(0.12, 0.12, 0.13))
	metal.metallic = 0.6
	var body := CylinderMesh.new()
	body.top_radius = 0.03
	body.bottom_radius = 0.03
	body.height = 0.18
	_add_mesh(_right_hand, body, metal, Vector3(0.0, 0.0, -0.06), Vector3(PI / 2.0, 0.0, 0.0))

	_lens_material = StandardMaterial3D.new()
	_lens_material.albedo_color = Color(0.9, 0.9, 0.8)
	_lens_material.emission_enabled = true
	_lens_material.emission = Color(1.0, 0.95, 0.75)
	var lens := CylinderMesh.new()
	lens.top_radius = 0.042
	lens.bottom_radius = 0.032
	lens.height = 0.035
	_add_mesh(_right_hand, lens, _lens_material, Vector3(0.0, 0.0, -0.16), Vector3(PI / 2.0, 0.0, 0.0))

	if _flashlight != null:
		_flashlight.get_parent().remove_child(_flashlight)
		_right_hand.add_child(_flashlight)
		_flashlight.position = Vector3(0.0, 0.0, -0.19)
		_flashlight.rotation = Vector3.ZERO


func _update_lens() -> void:
	if _lens_material == null:
		return
	_lens_material.emission_energy_multiplier = 2.0 if is_flashlight_on() else 0.0


## Geste rapide de la main droite quand un pouvoir est active avec succes.
func _play_hand_gesture() -> void:
	if _right_hand == null:
		return
	if _gesture_tween != null:
		_gesture_tween.kill()
	_right_hand.position = HAND_REST_RIGHT
	_gesture_tween = create_tween()
	_gesture_tween.tween_property(
		_right_hand, "position", HAND_REST_RIGHT + Vector3(0.0, 0.07, -0.16), 0.10
	).set_ease(Tween.EASE_OUT)
	_gesture_tween.tween_property(_right_hand, "position", HAND_REST_RIGHT, 0.28)


func _update_hands(delta: float) -> void:
	if _hands_root == null:
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var moving: bool = horizontal_speed > 0.5 and is_on_floor()
	var target_pos: Vector3 = Vector3.ZERO
	var target_rot: Vector3 = Vector3.ZERO

	if moving:
		target_pos.x = cos(_bob_phase * 0.5) * 0.008
		target_pos.y = sin(_bob_phase - 0.6) * 0.012 * (SPRINT_BOB_MULTIPLIER if _is_sprinting else 1.0)
	if _is_sprinting:
		target_pos += Vector3(0.0, -0.05, 0.04)
		target_rot.x = -0.25
	# Retard des mains quand on bouge la souris (effet de poids).
	target_rot.y += _look_delta.x * 0.003
	target_rot.x += _look_delta.y * 0.003
	_look_delta = _look_delta.lerp(Vector2.ZERO, minf(12.0 * delta, 1.0))
	# Epuise : les mains tremblent.
	if _exhausted:
		target_pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.004
	# Mort ou cache : les mains retombent pour degager la vue
	if _dead or _is_hidden:
		target_pos.y = -0.45

	var weight: float = minf(10.0 * delta, 1.0)
	_hands_root.position = _hands_root.position.lerp(target_pos, weight)
	_hands_root.rotation = _hands_root.rotation.lerp(target_rot, weight)


func _update_feet(delta: float) -> void:
	if _feet_root == null:
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var moving: bool = horizontal_speed > 0.5 and is_on_floor()
	var left_target := Vector3(-FOOT_SPACING, 0.0, FOOT_REST_Z)
	var right_target := Vector3(FOOT_SPACING, 0.0, FOOT_REST_Z)
	if moving:
		var limp: bool = has_sacrifice("leg")
		var amplitude: float = 0.16
		if limp:
			amplitude *= 0.6
		if _is_sprinting:
			amplitude *= 1.3
		var s: float = sin(_bob_phase)
		var c: float = cos(_bob_phase)
		left_target.z -= s * amplitude
		right_target.z += s * amplitude
		left_target.y = maxf(0.0, c) * 0.08
		right_target.y = maxf(0.0, -c) * 0.08
		if limp:
			left_target.y *= 0.3 # la jambe blessee traine
	var weight: float = minf(20.0 * delta, 1.0)
	_left_foot.position = _left_foot.position.lerp(left_target, weight)
	_right_foot.position = _right_foot.position.lerp(right_target, weight)


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
		if _is_sprinting:
			# En sprint, la tete penche d'un cote puis de l'autre a chaque pas.
			target_roll = sin(_bob_phase * 0.5) * SPRINT_ROLL
		elif has_sacrifice("leg"):
			# Sacrifice "leg" : la camera penche legerement a chaque pas (boiterie).
			target_roll = sin(_bob_phase) * 0.015
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


func _get_mouse_sensitivity() -> float:
	if has_sacrifice("reflexes"):
		return MOUSE_SENSITIVITY * REFLEXES_SENSITIVITY_MULTIPLIER
	return MOUSE_SENSITIVITY


func _get_stamina_recovery_multiplier() -> float:
	return HEART_RECOVERY_MULTIPLIER if has_sacrifice("heart") else 1.0


## Sacrifice "light" : portee et intensite de la lampe reduites.
func _refresh_flashlight_stats() -> void:
	if _flashlight == null:
		return
	var weak: bool = has_sacrifice("light")
	_flashlight.light_energy = FLASHLIGHT_ENERGY * (LIGHT_ENERGY_MULTIPLIER if weak else 1.0)
	_flashlight.spot_range = FLASHLIGHT_RANGE * (LIGHT_RANGE_MULTIPLIER if weak else 1.0)


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
		var recovery: float = (max_time / STAMINA_RECOVERY_TIME) * _get_stamina_recovery_multiplier()
		_stamina = minf(_stamina + recovery * delta, max_time)
		if _exhausted and _stamina >= max_time:
			_exhausted = false


func _request_power(power_id: String) -> void:
	# get_node_or_null : Player peut etre teste seul, sans l'Autoload.
	var power_manager: Node = get_node_or_null("/root/PowerManager")
	if power_manager == null:
		push_warning("Player: PowerManager introuvable (test isole ?)")
		return
	if power_manager.has_method("activate_power"):
		var result: Variant = power_manager.activate_power(power_id)
		if result is bool and result:
			_play_hand_gesture()


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
		"interact": KEY_E,
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