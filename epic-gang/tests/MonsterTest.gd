extends Node3D

const HOSPITAL_SCENE: PackedScene = preload("res://scenes/Hospital.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const MONSTER_SCENE: PackedScene = preload("res://scenes/Monster.tscn")

const MONSTER_SCRIPT: GDScript = preload("res://scripts/Monster.gd")
const FAR_PLAYER_POSITION: Vector3 = Vector3(-5.0, 0.0, 0.0)
const PARKED_PLAYER_POSITION: Vector3 = Vector3(500.0, 0.0, 500.0)
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
var _noise_count: int = 0
var _capture_notice: bool = false
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
		KEY_F7:
			_cycle_difficulty()
		KEY_F8:
			get_tree().call_group("monster", "hear_noise", _player.global_position, 14.0)


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
	_label.text = "F1 stun | F2 slow | F3 reveal | F4 reset | F5 pause | F7 difficulte | F8 bruit de porte\n"
	_label.text += "difficulte : %s | etat : %s | bruits entendus : %d\n" % [_monster.get_difficulty_label(), _monster.get_state_name(), _noise_count]
	_label.text += "poursuite : %s | distance : %.1f\n" % [_monster.is_chasing_player(), distance]
	_label.text += "detected %d | lost %d | caught %d" % [_detected_count, _lost_count, _caught_count]
	if _capture_notice:
		_label.text += "\nCAPTURE ! (game over dans le vrai jeu) - reset dans 2 s"


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
	_monster.noise_heard.connect(_on_noise_heard)


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
	if _auto:
		return
	_restart_after_capture()


func _restart_after_capture() -> void:
	_capture_notice = true
	await _wait(2.0)
	_capture_notice = false
	_reset_all()


func _on_noise_heard(_noise_position: Vector3) -> void:
	_noise_count += 1


func _cycle_difficulty() -> void:
	var ids: Array[String] = MONSTER_SCRIPT.get_difficulty_ids()
	var next_index: int = (ids.find(_monster.get_difficulty()) + 1) % ids.size()
	_monster.set_difficulty(ids[next_index])


func _park_player() -> void:
	_player.global_position = PARKED_PLAYER_POSITION
	_player.velocity = Vector3.ZERO


func _on_reveal_changed(is_revealed: bool) -> void:
	_reveal_events.append(is_revealed)


func _reset_all() -> void:
	_player.reset_player()
	_monster.reset_monster()
	_monster.global_position = _hospital.get_monster_spawn_position()
	_last_position = _monster.global_position
	_player.global_position = _hospital.get_player_spawn_position()
	_detected_count = 0
	_lost_count = 0
	_caught_count = 0
	_noise_count = 0
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
	await _scenario_difficulties()
	await _scenario_hearing_levels()
	await _scenario_noise_investigation()
	await _scenario_chase_ramp()
	await _scenario_intuition()
	await _scenario_hide_medium()
	await _scenario_hide_impossible()
	_monster.set_difficulty("medium")
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


func _scenario_difficulties() -> void:
	var previous: float = 0.0
	var ids: Array[String] = MONSTER_SCRIPT.get_difficulty_ids()
	for id: String in ids:
		_monster.set_difficulty(id)
		_reset_all()
		_park_player()
		await _wait(0.6)
		var speed: float = await _speed_over(1.2)
		var expected: float = float(MONSTER_SCRIPT.DIFFICULTIES[id]["patrol_speed"])
		_check("difficulte %s : vitesse de patrouille" % id, absf(speed - expected) < expected * 0.2, "%.2f (attendu %.2f)" % [speed, expected])
		_check("difficulte %s : plus rapide que la precedente" % id, speed > previous, "%.2f > %.2f" % [speed, previous])
		previous = speed
	_check("difficulte inconnue refusee", not _monster.set_difficulty("zzz"))
	_check("difficulte inconnue : ancienne conservee", _monster.get_difficulty() == "impossible")
	_monster.set_difficulty("medium")
	_reset_all()


func _count_noise_for(difficulty_id: String, loudness: float, distance: float) -> int:
	_monster.set_difficulty(difficulty_id)
	_reset_all()
	_park_player()
	var noise_position: Vector3 = _monster.global_position + Vector3(distance, 0.0, 0.0)
	get_tree().call_group("monster", "hear_noise", noise_position, loudness)
	return _noise_count


func _scenario_hearing_levels() -> void:
	_check("ouie : facile n'entend pas un bruit lointain", _count_noise_for("easy", 14.0, 20.0) == 0)
	_check("ouie : moyen n'entend pas non plus", _count_noise_for("medium", 14.0, 20.0) == 0)
	_check("ouie : impossible l'entend", _count_noise_for("impossible", 14.0, 20.0) == 1)
	_check("ouie : bruit trop faible ignore", _count_noise_for("impossible", 2.0, 40.0) == 0)
	_monster.set_difficulty("easy")
	_reset_all()
	_player.global_position = _monster.global_position + Vector3(12.0, 0.0, 0.0)
	_player.footstep.emit(true)
	_check("ouie : pas de sprint non entendus (facile, 12 m)", _noise_count == 0)
	_monster.set_difficulty("impossible")
	_reset_all()
	_player.global_position = _monster.global_position + Vector3(12.0, 0.0, 0.0)
	_player.footstep.emit(false)
	_check("ouie : pas du joueur entendus via le signal footstep", _noise_count == 1)
	_monster.set_difficulty("medium")
	_reset_all()


func _scenario_noise_investigation() -> void:
	_monster.set_difficulty("medium")
	_reset_all()
	_park_player()
	await _wait(0.5)
	var index: int = int(_monster.get("_patrol_index"))
	var points: Array[Vector3] = _hospital.get_patrol_points()
	var target_point: Vector3 = points[index]
	get_tree().call_group("monster", "hear_noise", target_point, 60.0)
	_check("bruit : le monstre passe en enquete", _monster.get_state_name() == "investigate", _monster.get_state_name())
	var elapsed: float = 0.0
	while elapsed < 40.0 and _monster.get_state_name() != "patrol":
		await _wait(0.5)
		elapsed += 0.5
	_check("bruit : enquete terminee puis retour en patrouille", _monster.get_state_name() == "patrol", "%.1f s" % elapsed)
	_noise_count = 0
	_monster.stun_monster(1.0)
	get_tree().call_group("monster", "hear_noise", target_point, 60.0)
	_check("bruit : un monstre etourdi n'entend rien", _noise_count == 0)


func _scenario_chase_ramp() -> void:
	_monster.set_difficulty("hard")
	_reset_all()
	_monster.set("_chase_time", 0.0)
	var start_speed: float = _monster.call("_get_chase_speed")
	_monster.set("_chase_time", 5.0)
	var later_speed: float = _monster.call("_get_chase_speed")
	_monster.set("_chase_time", 500.0)
	var capped_speed: float = _monster.call("_get_chase_speed")
	var max_speed: float = float(MONSTER_SCRIPT.DIFFICULTIES["hard"]["chase_speed_max"])
	_check("poursuite : le monstre accelere avec le temps", later_speed > start_speed, "%.2f -> %.2f" % [start_speed, later_speed])
	_check("poursuite : vitesse plafonnee", absf(capped_speed - max_speed) < 0.001, "%.2f" % capped_speed)
	_monster.set_difficulty("medium")


func _scenario_intuition() -> void:
	_monster.set_difficulty("impossible")
	_reset_all()
	_park_player()
	var interval: float = float(MONSTER_SCRIPT.DIFFICULTIES["impossible"]["intuition_interval"])
	_monster.set("_intuition_timer", interval - 0.05)
	await _wait(0.4)
	_check("intuition : impossible flaire le joueur", _monster.get_state_name() == "investigate", _monster.get_state_name())
	_monster.set_difficulty("medium")
	_reset_all()
	_park_player()
	_monster.set("_intuition_timer", 1000.0)
	await _wait(0.4)
	_check("intuition : moyen n'a pas d'intuition", _monster.get_state_name() == "patrol", _monster.get_state_name())


func _hide_player_with_monster_near(difficulty_id: String) -> HidingSpot:
	_monster.set_difficulty(difficulty_id)
	_reset_all()
	var spots: Array[Node] = get_tree().get_nodes_in_group("hiding_spots")
	var spot: HidingSpot = spots[0] as HidingSpot
	_player.global_position = spot.get_exit_position()
	spot.call("_on_body_entered", _player)
	_monster.global_position = spot.global_position + Vector3(3.5, 0.0, 0.0)
	_monster.call("_start_chase")
	var hidden_ok: bool = _player.hide_in_spot(spot)
	_check("cachette (%s) : joueur bien cache" % difficulty_id, hidden_ok and _player.is_hidden())
	return spot


func _scenario_hide_medium() -> void:
	var spot: HidingSpot = await _hide_player_with_monster_near("medium")
	await _wait(10.0)
	_check("cachette : moyen ne trouve pas le joueur cache", _caught_count == 0, "captures %d" % _caught_count)
	_player.exit_hiding_spot()
	_check("cachette : joueur sorti (moyen)", not _player.is_hidden() and not spot.is_occupied())


func _scenario_hide_impossible() -> void:
	var spot: HidingSpot = await _hide_player_with_monster_near("impossible")
	var elapsed: float = 0.0
	while elapsed < 20.0 and _caught_count == 0:
		await _wait(0.5)
		elapsed += 0.5
	_check("cachette : impossible fouille et trouve le joueur", _caught_count == 1, "%.1f s" % elapsed)
	_player.exit_hiding_spot()
	_check("cachette : joueur sorti (impossible)", not _player.is_hidden() and not spot.is_occupied())
	_reset_all()
