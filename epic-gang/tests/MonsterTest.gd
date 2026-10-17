extends Node3D

const HOSPITAL_SCENE: PackedScene = preload("res://scenes/Hospital.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const MONSTER_SCENE: PackedScene = preload("res://scenes/Monster.tscn")

const FAR_PLAYER_POSITION: Vector3 = Vector3(-5.0, 0.0, 0.0)
const SEE_DISTANCE: float = 6.0

var _hospital: Node3D
var _player: CharacterBody3D
var _monster: CharacterBody3D
var _label: Label
var _auto: bool = false
var _detected_count: int = 0
var _lost_count: int = 0
var _caught_count: int = 0
var _reveal_events: Array[bool] = []
var _failures: int = 0
var _traveled: float = 0.0
var _last_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_auto = OS.get_cmdline_user_args().has("--auto")
	_spawn_world()
	_connect_monster_signals()
	_setup_label()
	_start_monster()
	if _auto:
		_run_scenarios()


func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_F1:
			_monster.stun_monster(3.0)
		KEY_F2:
			_monster.slow_down(5.0, 0.5)
		KEY_F3:
			_monster.reveal_monster(5.0)
		KEY_F4:
			_reset_all()
		KEY_F5:
			_monster.set_menu_paused(not _monster_is_paused())


func _physics_process(_delta: float) -> void:
	var step: Vector3 = _monster.global_position - _last_position
	step.y = 0.0
	if step.length() < 1.0:
		_traveled += step.length()
	_last_position = _monster.global_position


func _process(_delta: float) -> void:
	if _label == null:
		return
	var distance: float = _monster.global_position.distance_to(_player.global_position)
	_label.text = "F1 stun | F2 slow | F3 reveal | F4 reset | F5 pause\n"
	_label.text += "poursuite : %s | distance : %.1f\n" % [_monster.is_chasing_player(), distance]
	_label.text += "detected %d | lost %d | caught %d" % [_detected_count, _lost_count, _caught_count]


func _spawn_world() -> void:
	_hospital = HOSPITAL_SCENE.instantiate() as Node3D
	add_child(_hospital)
	_player = PLAYER_SCENE.instantiate() as CharacterBody3D
	_monster = MONSTER_SCENE.instantiate() as CharacterBody3D
	add_child(_player)
	add_child(_monster)
	_monster.add_to_group("monster")
	_player.global_position = _hospital.get_player_spawn_position()
	_monster.global_position = _hospital.get_monster_spawn_position()
	_last_position = _monster.global_position


func _start_monster() -> void:
	_monster.set_target(_player)
	_monster.start_patrol(_hospital.get_patrol_points())


func _connect_monster_signals() -> void:
	_monster.player_detected.connect(_on_detected)
	_monster.player_lost.connect(_on_lost)
	_monster.monster_caught_player.connect(_on_caught)
	_monster.reveal_state_changed.connect(_on_reveal_changed)


func _setup_label() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	layer.add_child(_label)
	add_child(layer)


func _monster_is_paused() -> bool:
	return _monster.get("_menu_paused") == true


func _on_detected() -> void:
	_detected_count += 1


func _on_lost() -> void:
	_lost_count += 1


func _on_caught() -> void:
	_caught_count += 1


func _on_reveal_changed(is_revealed: bool) -> void:
	_reveal_events.append(is_revealed)


func _reset_all() -> void:
	_monster.reset_monster()
	_monster.global_position = _hospital.get_monster_spawn_position()
	_last_position = _monster.global_position
	_player.global_position = _hospital.get_player_spawn_position()
	_detected_count = 0
	_lost_count = 0
	_caught_count = 0
	_reveal_events.clear()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS  ", name, "  ", detail)
		return
	_failures += 1
	print("FAIL  ", name, "  ", detail)


func _place_player_in_front(distance: float) -> void:
	var forward: Vector3 = -_monster.global_transform.basis.z
	forward.y = 0.0
	_player.global_position = _monster.global_position + forward.normalized() * distance
	_player.velocity = Vector3.ZERO


func _speed_over(seconds: float) -> float:
	var start: float = _traveled
	await _wait(seconds)
	return (_traveled - start) / seconds


func _run_scenarios() -> void:
	await _wait(1.0)
	await _scenario_patrol()
	await _scenario_detection_and_capture()
	await _scenario_lose_player()
	await _scenario_stun()
	await _scenario_slow()
	await _scenario_reveal()
	await _scenario_pause()
	await _scenario_reset()
	print("RESULT  ", _failures, " echec(s)")
	get_tree().quit(_failures)


func _scenario_patrol() -> void:
	var start: float = _traveled
	await _wait(3.0)
	var moved: float = _traveled - start
	_check("patrouille : le monstre avance", moved > 3.0, "deplacement %.1f m" % moved)
	_check("patrouille : pas de poursuite", not _monster.is_chasing_player())


func _scenario_detection_and_capture() -> void:
	_player.global_position = _monster.global_position
	_place_player_in_front(SEE_DISTANCE)
	await _wait(1.0)
	_check("detection : player_detected emis", _detected_count >= 1, "count %d" % _detected_count)
	_check("detection : poursuite active", _monster.is_chasing_player() or _caught_count > 0)
	await _wait(5.0)
	_check("capture : monster_caught_player emis une fois", _caught_count == 1, "count %d" % _caught_count)


func _scenario_lose_player() -> void:
	_reset_all()
	await _wait(0.5)
	_place_player_in_front(SEE_DISTANCE)
	await _wait(0.5)
	_player.global_position = FAR_PLAYER_POSITION
	await _wait(4.0)
	_check("perte : player_lost emis", _lost_count >= 1, "count %d" % _lost_count)
	_check("perte : plus de poursuite", not _monster.is_chasing_player())


func _scenario_stun() -> void:
	_reset_all()
	await _wait(0.5)
	_monster.stun_monster(2.0)
	var stunned_speed: float = await _speed_over(1.5)
	_check("stun : immobile pendant le stun", stunned_speed < 0.2, "vitesse %.2f" % stunned_speed)
	await _wait(1.0)
	var after_speed: float = await _speed_over(1.0)
	_check("stun : repart apres le stun", after_speed > 1.0, "vitesse %.2f" % after_speed)


func _scenario_slow() -> void:
	_reset_all()
	await _wait(0.5)
	var normal_speed: float = await _speed_over(1.0)
	_monster.slow_down(3.0, 0.5)
	var slow_speed: float = await _speed_over(1.0)
	var ratio: float = slow_speed / maxf(normal_speed, 0.001)
	_check("ralentissement : vitesse divisee par deux", ratio > 0.35 and ratio < 0.65, "ratio %.2f" % ratio)
	await _wait(3.0)
	var back_speed: float = await _speed_over(1.0)
	_check("ralentissement : vitesse normale ensuite", back_speed > normal_speed * 0.85, "vitesse %.2f" % back_speed)


func _scenario_reveal() -> void:
	_reset_all()
	_monster.reveal_monster(1.0)
	_monster.reveal_monster(1.0)
	await _wait(2.0)
	_check("reveal : true puis false, sans doublon", _reveal_events == [true, false], str(_reveal_events))


func _scenario_pause() -> void:
	_reset_all()
	await _wait(0.5)
	_monster.set_menu_paused(true)
	var paused_speed: float = await _speed_over(1.0)
	_check("pause : monstre fige", paused_speed < 0.05, "vitesse %.2f" % paused_speed)
	_monster.set_menu_paused(false)
	var resumed_speed: float = await _speed_over(1.0)
	_check("pause : reprise du mouvement", resumed_speed > 1.0, "vitesse %.2f" % resumed_speed)


func _scenario_reset() -> void:
	_monster.stun_monster(10.0)
	_monster.slow_down(10.0, 0.2)
	_monster.reveal_monster(10.0)
	_reset_all()
	var speed: float = await _speed_over(1.5)
	_check("reset : plus aucun effet temporaire", speed > 1.5, "vitesse %.2f" % speed)
	_check("reset : reveal ferme", _reveal_events.is_empty() or _reveal_events.back() == false)
