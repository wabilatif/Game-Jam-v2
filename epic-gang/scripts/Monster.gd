extends CharacterBody3D

signal player_detected
signal player_lost
signal monster_caught_player
signal reveal_state_changed(is_revealed: bool)

enum State { PATROL, CHASE, SEARCH }

const GRAVITY: float = 20.0
const PATROL_SPEED: float = 2.5
const CHASE_SPEED: float = 4.2
const SEARCH_SPEED: float = 3.0
const SIGHT_RANGE: float = 15.0
const SIGHT_FOV_DEGREES: float = 110.0
const PROXIMITY_DETECTION_RANGE: float = 3.0
const CAPTURE_DISTANCE: float = 1.3
const WAYPOINT_REACHED_DISTANCE: float = 1.0
const LOSE_SIGHT_TIME: float = 2.0
const SEARCH_LOOK_TIME: float = 5.0
const SEARCH_LOOK_SPEED: float = 2.0
const TURN_SPEED: float = 6.0
const EYE_HEIGHT: float = 1.5
const MIN_MOVE_DISTANCE: float = 0.05
const OBSTACLE_MASK: int = 1

var _state: State = State.PATROL
var _target: Node3D = null
var _agent: NavigationAgent3D = null
var _patrol_points: Array[Vector3] = []
var _patrol_index: int = 0
var _last_seen_position: Vector3 = Vector3.ZERO
var _search_position: Vector3 = Vector3.ZERO
var _search_arrived: bool = false
var _search_timer: float = 0.0
var _lose_sight_timer: float = 0.0
var _stun_time: float = 0.0
var _slow_time: float = 0.0
var _slow_factor: float = 1.0
var _reveal_time: float = 0.0
var _menu_paused: bool = false
var _caught: bool = false


func _ready() -> void:
	add_to_group("monster")
	_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D


func set_target(target: Node3D) -> void:
	_target = target


func start_patrol(points: Array[Vector3]) -> void:
	_patrol_points.assign(points)
	_patrol_index = 0
	if _patrol_points.is_empty():
		push_warning("Monster: aucun point de patrouille fourni.")
	_enter_patrol()


func resume_patrol() -> void:
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


func reset_monster() -> void:
	var was_revealed: bool = _reveal_time > 0.0
	_stun_time = 0.0
	_slow_time = 0.0
	_slow_factor = 1.0
	_reveal_time = 0.0
	_menu_paused = false
	_caught = false
	_lose_sight_timer = 0.0
	_search_arrived = false
	_search_timer = 0.0
	_patrol_index = 0
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
	_update_state(delta)
	move_and_slide()
	_check_capture()


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
	match _state:
		State.PATROL:
			_update_patrol()
		State.CHASE:
			_update_chase(delta)
		State.SEARCH:
			_update_search(delta)


func _update_patrol() -> void:
	if _can_see_target(false):
		_start_chase()
		return
	if _patrol_points.is_empty():
		_stop_horizontal()
		return
	var point: Vector3 = _patrol_points[_patrol_index]
	if _flat_distance_to(point) <= WAYPOINT_REACHED_DISTANCE:
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()
		return
	_move_toward(point, PATROL_SPEED)


func _update_chase(delta: float) -> void:
	if _can_see_target(true):
		_lose_sight_timer = 0.0
		_last_seen_position = _target.global_position
	else:
		_lose_sight_timer += delta
	if _lose_sight_timer >= LOSE_SIGHT_TIME:
		_start_search()
		return
	_move_toward(_last_seen_position, CHASE_SPEED)


func _update_search(delta: float) -> void:
	if _can_see_target(false):
		_start_chase()
		return
	if not _search_arrived:
		_update_search_approach()
		return
	_stop_horizontal()
	rotation.y += SEARCH_LOOK_SPEED * delta
	_search_timer -= delta
	if _search_timer <= 0.0:
		resume_patrol()


func _update_search_approach() -> void:
	if _flat_distance_to(_search_position) <= WAYPOINT_REACHED_DISTANCE:
		_search_arrived = true
		_search_timer = SEARCH_LOOK_TIME
		_stop_horizontal()
		return
	_move_toward(_search_position, SEARCH_SPEED)


func _enter_patrol() -> void:
	_state = State.PATROL
	_lose_sight_timer = 0.0
	_search_arrived = false


func _start_chase() -> void:
	_lose_sight_timer = 0.0
	if _state == State.CHASE:
		return
	_state = State.CHASE
	_last_seen_position = _target.global_position
	player_detected.emit()


func _start_search() -> void:
	_state = State.SEARCH
	_search_position = _last_seen_position
	_search_arrived = false
	_lose_sight_timer = 0.0
	player_lost.emit()


func _check_capture() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if global_position.distance_to(_target.global_position) > CAPTURE_DISTANCE:
		return
	_caught = true
	velocity = Vector3.ZERO
	monster_caught_player.emit()


func _can_see_target(ignore_fov: bool) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var to_target: Vector3 = _target.global_position - global_position
	var distance: float = to_target.length()
	if distance > SIGHT_RANGE:
		return false
	var needs_fov: bool = not ignore_fov and distance > PROXIMITY_DETECTION_RANGE
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
	return angle <= SIGHT_FOV_DEGREES * 0.5


func _has_line_of_sight() -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * EYE_HEIGHT
	var to: Vector3 = _target.global_position + Vector3.UP * EYE_HEIGHT
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, OBSTACLE_MASK)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return true
	return result["collider"] == _target


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
	_face_direction(direction, get_physics_process_delta_time())


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)


func _stop_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _flat_distance_to(point: Vector3) -> float:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	return offset.length()


func _get_nearest_patrol_index() -> int:
	var best_index: int = 0
	var best_distance: float = INF
	for i in range(_patrol_points.size()):
		var distance: float = _flat_distance_to(_patrol_points[i])
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index