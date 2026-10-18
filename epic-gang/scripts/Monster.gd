extends CharacterBody3D

signal player_detected
signal player_lost
signal monster_caught_player
signal reveal_state_changed(is_revealed: bool)
signal noise_heard(noise_position: Vector3)

enum State { PATROL, CHASE, SEARCH, INVESTIGATE }

const DIFFICULTY_META_KEY: String = "monster_difficulty"
const DEFAULT_DIFFICULTY: String = "medium"
const DIFFICULTY_ORDER: Array[String] = ["easy", "medium", "hard", "nightmare", "impossible"]

const DIFFICULTIES: Dictionary = {
	"easy": {
		"label": "Facile",
		"patrol_speed": 2.0,
		"chase_speed": 3.6,
		"chase_speed_max": 3.6,
		"chase_ramp": 0.0,
		"search_speed": 2.4,
		"investigate_speed": 2.6,
		"sight_range": 10.0,
		"fov_degrees": 90.0,
		"proximity_range": 2.0,
		"flashlight_bonus": 0.0,
		"lose_sight_time": 1.5,
		"search_look_time": 3.0,
		"search_points": 0,
		"hearing": 0.5,
		"noise_error": 4.0,
		"lead_time": 0.0,
		"intuition_interval": 0.0,
		"hide_find_time": 0.0,
		"capture_distance": 1.1,
	},
	"medium": {
		"label": "Moyen",
		"patrol_speed": 2.5,
		"chase_speed": 4.2,
		"chase_speed_max": 4.6,
		"chase_ramp": 0.05,
		"search_speed": 3.0,
		"investigate_speed": 3.2,
		"sight_range": 15.0,
		"fov_degrees": 110.0,
		"proximity_range": 3.0,
		"flashlight_bonus": 3.0,
		"lose_sight_time": 2.0,
		"search_look_time": 5.0,
		"search_points": 1,
		"hearing": 1.0,
		"noise_error": 2.0,
		"lead_time": 0.2,
		"intuition_interval": 0.0,
		"hide_find_time": 0.0,
		"capture_distance": 1.3,
	},
	"hard": {
		"label": "Difficile",
		"patrol_speed": 3.0,
		"chase_speed": 5.0,
		"chase_speed_max": 6.0,
		"chase_ramp": 0.1,
		"search_speed": 3.6,
		"investigate_speed": 4.0,
		"sight_range": 20.0,
		"fov_degrees": 130.0,
		"proximity_range": 4.0,
		"flashlight_bonus": 5.0,
		"lose_sight_time": 3.0,
		"search_look_time": 7.0,
		"search_points": 3,
		"hearing": 1.5,
		"noise_error": 1.0,
		"lead_time": 0.4,
		"intuition_interval": 0.0,
		"hide_find_time": 0.0,
		"capture_distance": 1.4,
	},
	"nightmare": {
		"label": "Cauchemar",
		"patrol_speed": 3.6,
		"chase_speed": 6.0,
		"chase_speed_max": 7.5,
		"chase_ramp": 0.2,
		"search_speed": 4.4,
		"investigate_speed": 5.0,
		"sight_range": 25.0,
		"fov_degrees": 150.0,
		"proximity_range": 5.0,
		"flashlight_bonus": 7.0,
		"lose_sight_time": 4.0,
		"search_look_time": 9.0,
		"search_points": 5,
		"hearing": 2.0,
		"noise_error": 0.5,
		"lead_time": 0.6,
		"intuition_interval": 25.0,
		"hide_find_time": 6.0,
		"capture_distance": 1.5,
	},
	"impossible": {
		"label": "Impossible",
		"patrol_speed": 4.2,
		"chase_speed": 7.0,
		"chase_speed_max": 9.0,
		"chase_ramp": 0.3,
		"search_speed": 5.0,
		"investigate_speed": 6.0,
		"sight_range": 35.0,
		"fov_degrees": 180.0,
		"proximity_range": 7.0,
		"flashlight_bonus": 10.0,
		"lose_sight_time": 6.0,
		"search_look_time": 12.0,
		"search_points": 8,
		"hearing": 3.0,
		"noise_error": 0.0,
		"lead_time": 0.9,
		"intuition_interval": 12.0,
		"hide_find_time": 4.0,
		"capture_distance": 1.6,
	},
}

const GRAVITY: float = 20.0
const SEARCH_LOOK_SPEED: float = 2.0
const TURN_SPEED: float = 6.0
const EYE_HEIGHT: float = 1.5
const MIN_MOVE_DISTANCE: float = 0.05
const OBSTACLE_MASK: int = 1
const WAYPOINT_REACHED_DISTANCE: float = 1.0

const FOOTSTEP_WALK_LOUDNESS: float = 8.0
const FOOTSTEP_SPRINT_LOUDNESS: float = 16.0
const WALL_MUFFLE_FACTOR: float = 1.6
const NOISE_CHASE_GRACE: float = 0.5

const APPROACH_TIMEOUT: float = 12.0
const QUEUE_MIN_SPACING: float = 3.0
const QUEUE_LOOK_FACTOR: float = 0.4
const STUCK_LIMIT: float = 1.5
const STUCK_DISTANCE: float = 0.4

const HIDE_CHECK_DISTANCE: float = 2.2
const HIDE_SUSPICION_DURATION: float = 20.0
const HIDDEN_FLEE_RANGE: float = 25.0
const HIDDEN_FAR_DISTANCE: float = 18.0

## Bruits du monde (NoiseManager : portes, etc.). Le monstre ne reagit qu'a un
## bruit tout frais : un son vieux de quelques secondes ne l'attire plus.
const NOISE_MAX_AGE: float = 0.5
const NOISES_PER_TICK: int = 8

@export var default_difficulty: String = DEFAULT_DIFFICULTY

var _state: State = State.PATROL
var _target: Node3D = null
var _footstep_source: Node3D = null
var _agent: NavigationAgent3D = null
var _difficulty_id: String = DEFAULT_DIFFICULTY
var _cfg: Dictionary = DIFFICULTIES[DEFAULT_DIFFICULTY]
var _patrol_points: Array[Vector3] = []
var _patrol_index: int = 0
var _last_seen_position: Vector3 = Vector3.ZERO
var _search_position: Vector3 = Vector3.ZERO
var _search_queue: Array[Vector3] = []
var _search_arrived: bool = false
var _search_timer: float = 0.0
var _approach_time: float = 0.0
var _lose_sight_timer: float = 0.0
var _chase_time: float = 0.0
var _intuition_timer: float = 0.0
var _stun_time: float = 0.0
var _slow_time: float = 0.0
var _slow_factor: float = 1.0
var _reveal_time: float = 0.0
var _menu_paused: bool = false
var _caught: bool = false
var _was_hidden: bool = false
var _hide_suspicion_left: float = 0.0
var _hide_check_time: float = 0.0
var _move_intent: bool = false
var _stuck_time: float = 0.0
var _stuck_reference: Vector3 = Vector3.ZERO
var _noise_manager: Node = null


static func get_difficulty_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(DIFFICULTY_ORDER)
	return ids


func _ready() -> void:
	add_to_group("monster")
	_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	_noise_manager = get_node_or_null("/root/NoiseManager")
	var wanted: String = default_difficulty
	if Engine.has_meta(DIFFICULTY_META_KEY):
		wanted = str(Engine.get_meta(DIFFICULTY_META_KEY))
	if not set_difficulty(wanted):
		set_difficulty(DEFAULT_DIFFICULTY)
	_stuck_reference = global_position


func _exit_tree() -> void:
	_disconnect_target_signals()


func set_difficulty(difficulty_id: String) -> bool:
	if not DIFFICULTIES.has(difficulty_id):
		push_warning("Monster: difficulte inconnue '%s'." % difficulty_id)
		return false
	_difficulty_id = difficulty_id
	_cfg = DIFFICULTIES[difficulty_id]
	return true


func get_difficulty() -> String:
	return _difficulty_id


func get_difficulty_label() -> String:
	return str(_cfg["label"])


func get_state_name() -> String:
	match _state:
		State.CHASE:
			return "chase"
		State.SEARCH:
			return "search"
		State.INVESTIGATE:
			return "investigate"
	return "patrol"


func set_target(target: Node3D) -> void:
	_disconnect_target_signals()
	_target = target
	_connect_target_signals()


func start_patrol(points: Array[Vector3]) -> void:
	_patrol_points.assign(points)
	_patrol_index = 0
	if _patrol_points.is_empty():
		push_warning("Monster: aucun point de patrouille fourni.")
	_enter_patrol()


func resume_patrol() -> void:
	if _is_target_hidden():
		_patrol_index = _get_farthest_patrol_index_from_target()
	else:
		_patrol_index = _get_nearest_patrol_index()
	_enter_patrol()


func set_menu_paused(paused: bool) -> void:
	_menu_paused = paused
	velocity = Vector3.ZERO


func stun_monster(duration: float) -> void:
	if duration <= 0.0:
		return
	_stun_time = maxf(_stun_time, duration)
	velocity.x = 0.0
	velocity.z = 0.0


func slow_down(duration: float, factor: float) -> void:
	if duration <= 0.0:
		return
	var clamped_factor: float = clampf(factor, 0.05, 1.0)
	if _slow_time > 0.0:
		_slow_factor = minf(_slow_factor, clamped_factor)
	else:
		_slow_factor = clamped_factor
	_slow_time = maxf(_slow_time, duration)


func reveal_monster(duration: float) -> void:
	if duration <= 0.0:
		return
	var was_revealed: bool = _reveal_time > 0.0
	_reveal_time = maxf(_reveal_time, duration)
	if not was_revealed:
		reveal_state_changed.emit(true)


func is_chasing_player() -> bool:
	return _state == State.CHASE


func get_monster_position() -> Vector3:
	return global_position


func hear_noise(noise_position: Vector3, loudness: float) -> void:
	if _caught or _menu_paused or _stun_time > 0.0 or loudness <= 0.0:
		return
	var distance: float = _flat_distance_to(noise_position)
	var reach: float = loudness * _p("hearing")
	if _is_noise_muffled(noise_position):
		distance *= WALL_MUFFLE_FACTOR
	if distance > reach:
		return
	var heard_position: Vector3 = _blur_noise_position(noise_position, distance, reach)
	noise_heard.emit(heard_position)
	_react_to_noise(heard_position)


func reset_monster() -> void:
	var was_revealed: bool = _reveal_time > 0.0
	_stun_time = 0.0
	_slow_time = 0.0
	_slow_factor = 1.0
	_reveal_time = 0.0
	_menu_paused = false
	_caught = false
	_lose_sight_timer = 0.0
	_chase_time = 0.0
	_intuition_timer = 0.0
	_search_arrived = false
	_search_timer = 0.0
	_approach_time = 0.0
	_search_queue.clear()
	_patrol_index = 0
	_was_hidden = false
	_hide_suspicion_left = 0.0
	_hide_check_time = 0.0
	_move_intent = false
	_stuck_time = 0.0
	_stuck_reference = global_position
	_state = State.PATROL
	velocity = Vector3.ZERO
	if was_revealed:
		reveal_state_changed.emit(false)


func _physics_process(delta: float) -> void:
	if _caught or _menu_paused:
		return
	_tick_effects(delta)
	_apply_gravity(delta)
	if _stun_time > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	_listen_to_world_noises()
	_move_intent = false
	_update_state(delta)
	move_and_slide()
	_track_stuck(delta)
	_check_capture()


func _p(key: String) -> float:
	return float(_cfg[key])


func _connect_target_signals() -> void:
	if _target == null or not _target.has_signal("footstep"):
		return
	_footstep_source = _target
	if not _footstep_source.is_connected("footstep", _on_target_footstep):
		_footstep_source.connect("footstep", _on_target_footstep)


func _disconnect_target_signals() -> void:
	if _footstep_source == null or not is_instance_valid(_footstep_source):
		_footstep_source = null
		return
	if _footstep_source.is_connected("footstep", _on_target_footstep):
		_footstep_source.disconnect("footstep", _on_target_footstep)
	_footstep_source = null


func _on_target_footstep(is_sprinting: bool) -> void:
	if _target == null or not is_instance_valid(_target) or _is_target_hidden():
		return
	var loudness: float = FOOTSTEP_WALK_LOUDNESS
	if is_sprinting:
		loudness = FOOTSTEP_SPRINT_LOUDNESS
	hear_noise(_target.global_position, loudness)


func _tick_effects(delta: float) -> void:
	_tick_stun(delta)
	_tick_slow(delta)
	_tick_reveal(delta)


func _tick_stun(delta: float) -> void:
	if _stun_time > 0.0:
		_stun_time = maxf(_stun_time - delta, 0.0)


func _tick_slow(delta: float) -> void:
	if _slow_time <= 0.0:
		return
	_slow_time = maxf(_slow_time - delta, 0.0)
	if _slow_time <= 0.0:
		_slow_factor = 1.0


func _tick_reveal(delta: float) -> void:
	if _reveal_time <= 0.0:
		return
	_reveal_time = maxf(_reveal_time - delta, 0.0)
	if _reveal_time <= 0.0:
		reveal_state_changed.emit(false)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta


func _update_state(delta: float) -> void:
	_update_hidden_memory(delta)
	if _is_target_hidden():
		_update_target_hidden(delta)
		return
	match _state:
		State.PATROL:
			_update_patrol(delta)
		State.CHASE:
			_update_chase(delta)
		State.SEARCH, State.INVESTIGATE:
			_update_search(delta)


func _update_hidden_memory(delta: float) -> void:
	var hidden: bool = _is_target_hidden()
	if hidden and not _was_hidden:
		_hide_check_time = 0.0
		_hide_suspicion_left = 0.0
		if _p("hide_find_time") > 0.0 and _state != State.PATROL:
			_hide_suspicion_left = HIDE_SUSPICION_DURATION
	_was_hidden = hidden
	if hidden and _hide_suspicion_left > 0.0:
		_hide_suspicion_left = maxf(_hide_suspicion_left - delta, 0.0)


func _update_target_hidden(delta: float) -> void:
	if _hide_suspicion_left > 0.0:
		_hunt_hidden_target(delta)
		return
	if _state == State.CHASE:
		player_lost.emit()
	_state = State.PATROL
	_search_queue.clear()
	_lose_sight_timer = 0.0
	_search_arrived = false
	if _patrol_points.is_empty():
		_stop_horizontal()
		return
	var target_pos: Vector3 = _target.global_position
	if _flat_distance_to(target_pos) < HIDDEN_FLEE_RANGE:
		_patrol_index = _get_farthest_patrol_index_from_target()
		_move_toward(_patrol_points[_patrol_index], _p("patrol_speed"))
		return
	var current_point: Vector3 = _patrol_points[_patrol_index]
	var reached: bool = _flat_distance_to(current_point) <= WAYPOINT_REACHED_DISTANCE
	if reached or current_point.distance_to(target_pos) < HIDDEN_FAR_DISTANCE:
		_patrol_index = _get_next_far_patrol_index(HIDDEN_FAR_DISTANCE)
	_move_toward(_patrol_points[_patrol_index], _p("patrol_speed"))


func _hunt_hidden_target(delta: float) -> void:
	if _state == State.CHASE:
		player_lost.emit()
	_state = State.SEARCH
	var spot: Vector3 = _target.global_position
	if _flat_distance_to(spot) > HIDE_CHECK_DISTANCE:
		_move_toward(spot, _p("search_speed"))
		return
	_stop_horizontal()
	_hide_check_time += delta
	if _hide_check_time >= _p("hide_find_time"):
		_capture()


func _update_patrol(delta: float) -> void:
	if _can_see_target(false):
		_start_chase()
		return
	if _update_intuition(delta):
		return
	if _patrol_points.is_empty():
		_stop_horizontal()
		return
	var point: Vector3 = _patrol_points[_patrol_index]
	if _flat_distance_to(point) <= WAYPOINT_REACHED_DISTANCE:
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()
		return
	_move_toward(point, _p("patrol_speed"))


func _update_intuition(delta: float) -> bool:
	var interval: float = _p("intuition_interval")
	if interval <= 0.0 or _target == null or _patrol_points.is_empty():
		return false
	_intuition_timer += delta
	if _intuition_timer < interval:
		return false
	_intuition_timer = 0.0
	var index: int = _get_nearest_patrol_index_to(_target.global_position)
	_start_investigate(_patrol_points[index])
	return true


func _update_chase(delta: float) -> void:
	_chase_time += delta
	if _can_see_target(true):
		_lose_sight_timer = 0.0
		_last_seen_position = _get_predicted_target_position()
	else:
		_lose_sight_timer += delta
	if _lose_sight_timer >= _p("lose_sight_time"):
		_start_search()
		return
	_move_toward(_last_seen_position, _get_chase_speed())


func _update_search(delta: float) -> void:
	if _can_see_target(false):
		_start_chase()
		return
	if not _search_arrived:
		_update_search_approach(delta)
		return
	_stop_horizontal()
	rotation.y += SEARCH_LOOK_SPEED * delta
	_search_timer -= delta
	if _search_timer <= 0.0:
		_advance_search()


func _update_search_approach(delta: float) -> void:
	_approach_time += delta
	var arrived: bool = _flat_distance_to(_search_position) <= WAYPOINT_REACHED_DISTANCE
	if arrived or _approach_time >= APPROACH_TIMEOUT:
		_search_arrived = true
		_search_timer = _p("search_look_time")
		if not _search_queue.is_empty():
			_search_timer *= QUEUE_LOOK_FACTOR
		_stop_horizontal()
		return
	_move_toward(_search_position, _get_search_speed())


func _advance_search() -> void:
	if _search_queue.is_empty():
		resume_patrol()
		return
	_search_position = _search_queue.pop_front()
	_search_arrived = false
	_approach_time = 0.0


func _enter_patrol() -> void:
	_state = State.PATROL
	_lose_sight_timer = 0.0
	_search_arrived = false
	_search_queue.clear()


func _start_chase() -> void:
	_lose_sight_timer = 0.0
	if _state == State.CHASE:
		return
	_state = State.CHASE
	_chase_time = 0.0
	_search_queue.clear()
	_last_seen_position = _target.global_position
	player_detected.emit()


func _start_search() -> void:
	_state = State.SEARCH
	_begin_search(_last_seen_position, int(_p("search_points")))
	player_lost.emit()


func _start_investigate(position: Vector3) -> void:
	_state = State.INVESTIGATE
	_begin_search(position, floori(_p("search_points") * 0.5))


func _begin_search(origin: Vector3, extra_points: int) -> void:
	_search_position = origin
	_search_arrived = false
	_search_timer = 0.0
	_approach_time = 0.0
	_lose_sight_timer = 0.0
	_search_queue = _build_search_queue(origin, extra_points)


func _build_search_queue(origin: Vector3, count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if count <= 0 or _patrol_points.is_empty():
		return result
	var candidates: Array[Vector3] = []
	for point: Vector3 in _patrol_points:
		if point.distance_to(origin) > QUEUE_MIN_SPACING:
			candidates.append(point)
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_to(origin) < b.distance_to(origin))
	for i in range(mini(count, candidates.size())):
		result.append(candidates[i])
	return result


func _react_to_noise(heard_position: Vector3) -> void:
	match _state:
		State.CHASE:
			_track_by_sound(heard_position)
		_:
			_start_investigate(heard_position)


func _track_by_sound(heard_position: Vector3) -> void:
	if _lose_sight_timer <= 0.0:
		return
	_last_seen_position = heard_position
	_lose_sight_timer = minf(_lose_sight_timer, _p("lose_sight_time") * NOISE_CHASE_GRACE)


## Ecoute les bruits que le monde emet via NoiseManager (porte ouverte en
## courant = claquement, en marchant = grincement, porte refermee...). Le
## monstre les entend depuis SA position, avec l'ouie de sa difficulte. Seul le
## bruit le plus fort est traite a chaque passage, les autres sont ecartes :
## il ne change donc pas d'avis dix fois dans la meme image.
## Les bruits de porte sont emis dans l'ouverture du mur : on ne les attenue
## pas par les murs (le son passe par la porte). Ceux qu'il fait lui-meme ne
## sont jamais renvoyes par NoiseManager (player_made = false).
func _listen_to_world_noises() -> void:
	if _noise_manager == null or not is_instance_valid(_noise_manager):
		return
	if not _noise_manager.has_method("consume_noise_heard_at"):
		return
	if _is_target_hidden():
		return
	var loudest: Dictionary = {}
	for i in range(NOISES_PER_TICK):
		var heard: Dictionary = _noise_manager.consume_noise_heard_at(global_position, _p("hearing"))
		if heard.is_empty():
			break
		if float(heard.get("age", 0.0)) > NOISE_MAX_AGE:
			continue
		if loudest.is_empty():
			loudest = heard
	if loudest.is_empty():
		return
	var noise_position: Vector3 = loudest["position"]
	var global_multiplier: float = float(_noise_manager.get("hearing_multiplier"))
	var reach: float = float(loudest["radius"]) * global_multiplier * _p("hearing")
	var heard_position: Vector3 = _blur_noise_position(noise_position, float(loudest["distance"]), reach)
	noise_heard.emit(heard_position)
	_react_to_noise(heard_position)


func _blur_noise_position(noise_position: Vector3, distance: float, reach: float) -> Vector3:
	var error_radius: float = _p("noise_error")
	if error_radius <= 0.0:
		return noise_position
	var spread: float = clampf(distance / maxf(reach, 0.1), 0.25, 1.0)
	var angle: float = randf() * TAU
	var offset: float = randf() * error_radius * spread
	return noise_position + Vector3(cos(angle), 0.0, sin(angle)) * offset


func _is_noise_muffled(noise_position: Vector3) -> bool:
	var ear: Vector3 = global_position + Vector3.UP * EYE_HEIGHT
	return _is_blocked_between(ear, noise_position + Vector3.UP * EYE_HEIGHT)


func _get_chase_speed() -> float:
	var ramped: float = _p("chase_speed") + _p("chase_ramp") * _chase_time
	return minf(ramped, _p("chase_speed_max"))


func _get_search_speed() -> float:
	if _state == State.INVESTIGATE:
		return _p("investigate_speed")
	return _p("search_speed")


func _get_predicted_target_position() -> Vector3:
	var current: Vector3 = _target.global_position
	var lead: float = _p("lead_time")
	if lead <= 0.0:
		return current
	var target_velocity: Vector3 = Vector3.ZERO
	var raw_velocity: Variant = _target.get("velocity")
	if raw_velocity is Vector3:
		target_velocity = raw_velocity
	target_velocity.y = 0.0
	var predicted: Vector3 = current + target_velocity * lead
	var eye: Vector3 = global_position + Vector3.UP * EYE_HEIGHT
	if _is_blocked_between(eye, predicted + Vector3.UP * EYE_HEIGHT):
		return current
	return predicted


func _check_capture() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _is_target_hidden():
		return
	if global_position.distance_to(_target.global_position) > _p("capture_distance"):
		return
	_capture()


func _capture() -> void:
	if _caught:
		return
	_caught = true
	velocity = Vector3.ZERO
	monster_caught_player.emit()


func _is_target_hidden() -> bool:
	return _target != null and is_instance_valid(_target) and _target.has_method("is_hidden") and _target.is_hidden()


func _get_sight_range() -> float:
	var sight: float = _p("sight_range")
	if _target.has_method("is_flashlight_on") and _target.is_flashlight_on():
		sight += _p("flashlight_bonus")
	return sight


func _can_see_target(ignore_fov: bool) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if _is_target_hidden():
		return false
	var to_target: Vector3 = _target.global_position - global_position
	var distance: float = to_target.length()
	if distance > _get_sight_range():
		return false
	var needs_fov: bool = not ignore_fov and distance > _p("proximity_range")
	if needs_fov and not _is_in_field_of_view(to_target):
		return false
	return _has_line_of_sight()


func _is_in_field_of_view(to_target: Vector3) -> bool:
	var flat_direction: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	if flat_direction.length() < MIN_MOVE_DISTANCE:
		return true
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	var angle: float = rad_to_deg(forward.normalized().angle_to(flat_direction.normalized()))
	return angle <= _p("fov_degrees") * 0.5


func _has_line_of_sight() -> bool:
	var from: Vector3 = global_position + Vector3.UP * EYE_HEIGHT
	var to: Vector3 = _target.global_position + Vector3.UP * EYE_HEIGHT
	return not _is_blocked_between(from, to)


func _is_blocked_between(from_point: Vector3, to_point: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_point, to_point, OBSTACLE_MASK)
	var excluded: Array[RID] = [get_rid()]
	var target_body: CollisionObject3D = _target as CollisionObject3D
	if target_body != null and is_instance_valid(target_body):
		excluded.append(target_body.get_rid())
	query.exclude = excluded
	return not space.intersect_ray(query).is_empty()


func _has_navigation() -> bool:
	if _agent == null:
		return false
	var map: RID = _agent.get_navigation_map()
	return NavigationServer3D.map_get_regions(map).size() > 0


func _move_toward(destination: Vector3, speed: float) -> void:
	var next_position: Vector3 = destination
	if _has_navigation():
		_agent.target_position = destination
		next_position = _agent.get_next_path_position()
	var direction: Vector3 = next_position - global_position
	direction.y = 0.0
	if direction.length() < MIN_MOVE_DISTANCE:
		_stop_horizontal()
		return
	direction = direction.normalized()
	var final_speed: float = speed * _slow_factor
	velocity.x = direction.x * final_speed
	velocity.z = direction.z * final_speed
	_move_intent = true
	_face_direction(direction, get_physics_process_delta_time())


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)


func _stop_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _track_stuck(delta: float) -> void:
	if not _move_intent:
		_stuck_time = 0.0
		_stuck_reference = global_position
		return
	if global_position.distance_to(_stuck_reference) > STUCK_DISTANCE:
		_stuck_time = 0.0
		_stuck_reference = global_position
		return
	_stuck_time += delta
	if _stuck_time < STUCK_LIMIT:
		return
	_stuck_time = 0.0
	_stuck_reference = global_position
	_resolve_stuck()


func _resolve_stuck() -> void:
	match _state:
		State.PATROL:
			if not _patrol_points.is_empty():
				_patrol_index = (_patrol_index + 1) % _patrol_points.size()
		State.SEARCH, State.INVESTIGATE:
			_approach_time = APPROACH_TIMEOUT


func _flat_distance_to(point: Vector3) -> float:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	return offset.length()


func _get_nearest_patrol_index() -> int:
	return _get_nearest_patrol_index_to(global_position)


func _get_nearest_patrol_index_to(point: Vector3) -> int:
	var best_index: int = 0
	var best_distance: float = INF
	for i in range(_patrol_points.size()):
		var offset: Vector3 = _patrol_points[i] - point
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			best_index = i
	return best_index


func _get_farthest_patrol_index_from_target() -> int:
	if _patrol_points.is_empty() or _target == null or not is_instance_valid(_target):
		return 0
	var target_pos: Vector3 = _target.global_position
	var best_index: int = 0
	var best_dist: float = -1.0
	for i in range(_patrol_points.size()):
		var d: float = _patrol_points[i].distance_to(target_pos)
		if d > best_dist:
			best_dist = d
			best_index = i
	return best_index


func _get_next_far_patrol_index(min_dist: float) -> int:
	if _patrol_points.is_empty() or _target == null or not is_instance_valid(_target):
		return 0
	var target_pos: Vector3 = _target.global_position
	var candidates: Array[int] = []
	for i in range(_patrol_points.size()):
		if _patrol_points[i].distance_to(target_pos) >= min_dist:
			candidates.append(i)
	if candidates.is_empty():
		return _get_farthest_patrol_index_from_target()
	for idx: int in candidates:
		if idx > _patrol_index:
			return idx
	return candidates[0]