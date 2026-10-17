extends Node3D

const HOSPITAL_SCENE: PackedScene = preload("res://scenes/Hospital.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const MONSTER_SCENE: PackedScene = preload("res://scenes/Monster.tscn")

var _hospital: Node3D
var _player: CharacterBody3D
var _monster: CharacterBody3D
var _failures: int = 0
var _lost_emitted: bool = false


func _ready() -> void:
	_spawn_world()
	_run_tests()


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
	_monster.set_target(_player)
	_monster.start_patrol(_hospital.get_patrol_points())
	_monster.player_lost.connect(_on_player_lost)


func _on_player_lost() -> void:
	_lost_emitted = true


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS  ", name, "  ", detail)
	else:
		_failures += 1
		print("FAIL  ", name, "  ", detail)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run_tests() -> void:
	await _wait(0.5)

	# 1. Verification des cachettes dans la scene Hospital
	var spots := get_tree().get_nodes_in_group("hiding_spots")
	_check("map : taille augmentee avec 10 cachettes", spots.size() >= 10, "trouvees : %d" % spots.size())
	_check("map : sortie accessible sur la map agrandie", _hospital.call("is_exit_reachable"))

	var spot: HidingSpot = spots[0] as HidingSpot

	# 2. Test se cacher et orientation vers la piece
	_check("joueur : non cache initialement", not _player.is_hidden())
	_player.global_position = spot.get_exit_position()
	spot.call("_on_body_entered", _player)
	var hidden_ok := _player.hide_in_spot(spot)
	_check("joueur : se cacher dans l'armoire", hidden_ok and _player.is_hidden())
	_check("armoire : est occupee", spot.is_occupied())
	# Verifier que le joueur regarde vers l'avant du meuble (vers la piece a travers les portes)
	var aim_dir: Vector3 = _player.call("get_aim_direction")
	var spot_forward: Vector3 = spot.global_transform.basis.z.normalized()
	var dot_look: float = aim_dir.dot(spot_forward)
	_check("vision : joueur regarde vers la piece a travers la fente", dot_look > 0.8, "dot look vs front: %.2f" % dot_look)

	# 3. Test invisibilite vis-a-vis du monstre
	_monster.global_position = spot.global_position + Vector3(2.0, 0.0, 0.0)
	var can_see: bool = _monster.call("_can_see_target", true)
	_check("monstre : ne peut pas voir le joueur cache", not can_see)

	# 4. Test eloignement du monstre quand on est cache
	# Place le monstre pres du joueur
	_lost_emitted = false
	_monster.call("_start_chase")
	var initial_dist: float = _monster.global_position.distance_to(_player.global_position)

	# Simuler la physique quelques secondes
	await _wait(2.5)

	var new_dist: float = _monster.global_position.distance_to(_player.global_position)
	_check("monstre : s'eloigne activement du joueur cache", new_dist > initial_dist + 1.5, "initial: %.1fm -> nouveau: %.1fm" % [initial_dist, new_dist])
	_check("monstre : player_lost emis lors de la perte", _lost_emitted)

	# 5. Test sortie de la cachette
	_player.exit_hiding_spot()
	_check("joueur : sorti de la cachette", not _player.is_hidden())
	_check("armoire : liberee", not spot.is_occupied())
	var dist_to_exit: float = _player.global_position.distance_to(spot.get_exit_position())
	_check("joueur : repositionne devant l'armoire", dist_to_exit < 0.5, "distance: %.2fm" % dist_to_exit)

	print("HIDING TESTS FINISHED : %d echec(s)" % _failures)
	if OS.get_cmdline_user_args().has("--auto"):
		get_tree().quit(_failures)

