extends Node

signal power_discovered(power_id: String)
signal sacrifice_choice_requested(power_id: String, sacrifices: Array[String])
signal sacrifice_completed(power_id: String, sacrifice_id: String)
signal power_activated(power_id: String)
signal power_activation_failed(power_id: String, reason: String)

const POWER_IDS: Array[String] = ["shockwave", "spectral_vision", "speed_boost", "spectral_trap"]
const SACRIFICE_IDS: Array[String] = [
	"hearing", "leg", "vision", "stamina",
	"arm", "heart", "reflexes", "light", "memory",
]
## Sacrifice "arm" : les pouvoirs rechargent 50 % plus lentement.
const ARM_COOLDOWN_MULTIPLIER := 1.5
## Le menu propose au plus ce nombre de sacrifices, tires au hasard parmi ceux
## qui restent (le formulaire doit tenir a l'ecran, et chaque partie change).
const MAX_OFFERED_SACRIFICES := 5
const COOLDOWNS: Dictionary[String, float] = {
	"shockwave": 12.0,
	"spectral_vision": 15.0,
	"speed_boost": 12.0,
	"spectral_trap": 15.0,
}

const SHOCKWAVE_STUN_DURATION := 3.0
const SHOCKWAVE_RANGE := 8.0
const SPECTRAL_VISION_DURATION := 5.0
const SPEED_BOOST_FACTOR := 1.5
const SPEED_BOOST_DURATION := 5.0
const TRAP_SLOW_DURATION := 5.0
const TRAP_SLOW_FACTOR := 0.5

const SPECTRAL_TRAP_SCENE: PackedScene = preload("res://scenes/SpectralTrap.tscn")

var _unlocked_powers: Array[String] = []
var _used_sacrifices: Array[String] = []
var _choice_in_progress := false
var _pending_power_id := ""
var _cooldowns: Dictionary[String, float] = {}
var _offered_sacrifices: Dictionary = {} # power_id -> Array[String] (offre figee)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	for power_id: String in _cooldowns.keys():
		_cooldowns[power_id] -= delta
		if _cooldowns[power_id] <= 0.0:
			_cooldowns.erase(power_id)
	if _cooldowns.is_empty():
		set_process(false)


func discover_power(power_id: String) -> void:
	if not POWER_IDS.has(power_id) or has_power(power_id) or _choice_in_progress:
		return
	_choice_in_progress = true
	_pending_power_id = power_id
	power_discovered.emit(power_id)
	sacrifice_choice_requested.emit(power_id, get_offered_sacrifices(power_id))


func get_available_sacrifices(power_id: String) -> Array[String]:
	var available: Array[String] = []
	if not POWER_IDS.has(power_id) or has_power(power_id):
		return available
	for sacrifice_id in SACRIFICE_IDS:
		if not _used_sacrifices.has(sacrifice_id):
			available.append(sacrifice_id)
	return available


## Sacrifices proposes pour ce pouvoir : MAX_OFFERED_SACRIFICES au hasard parmi
## les disponibles. L'offre est memorisee : refuser puis revenir ne la change pas
## (elle est seulement completee si un sacrifice a ete pris entre-temps).
func get_offered_sacrifices(power_id: String) -> Array[String]:
	var available: Array[String] = get_available_sacrifices(power_id)
	var offered: Array[String] = []
	for sacrifice_id: String in _offered_sacrifices.get(power_id, []):
		if available.has(sacrifice_id):
			offered.append(sacrifice_id)
	var pool: Array[String] = []
	for sacrifice_id in available:
		if not offered.has(sacrifice_id):
			pool.append(sacrifice_id)
	pool.shuffle()
	while offered.size() < MAX_OFFERED_SACRIFICES and not pool.is_empty():
		offered.append(pool.pop_back())
	_offered_sacrifices[power_id] = offered.duplicate()
	return offered


func accept_sacrifice(power_id: String, sacrifice_id: String) -> bool:
	if not _choice_in_progress or power_id != _pending_power_id:
		return false
	if not get_available_sacrifices(power_id).has(sacrifice_id):
		return false
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.apply_sacrifice(sacrifice_id):
		return false
	_used_sacrifices.append(sacrifice_id)
	_unlocked_powers.append(power_id)
	_clear_pending_choice()
	sacrifice_completed.emit(power_id, sacrifice_id)
	return true


func reject_sacrifice() -> void:
	_clear_pending_choice()


func activate_power(power_id: String) -> bool:
	if not has_power(power_id):
		power_activation_failed.emit(power_id, "locked")
		return false
	if is_power_on_cooldown(power_id):
		power_activation_failed.emit(power_id, "cooldown")
		return false
	var failure_reason := _apply_power_effect(power_id)
	if not failure_reason.is_empty():
		power_activation_failed.emit(power_id, failure_reason)
		return false
	_cooldowns[power_id] = COOLDOWNS[power_id] * _get_cooldown_multiplier()
	set_process(true)
	power_activated.emit(power_id)
	return true


func _get_cooldown_multiplier() -> float:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("has_sacrifice") and player.has_sacrifice("arm"):
		return ARM_COOLDOWN_MULTIPLIER
	return 1.0


func has_power(power_id: String) -> bool:
	return _unlocked_powers.has(power_id)


func is_power_on_cooldown(power_id: String) -> bool:
	return _cooldowns.has(power_id)


func get_cooldown_remaining(power_id: String) -> float:
	return _cooldowns.get(power_id, 0.0)


func get_unlocked_powers() -> Array[String]:
	return _unlocked_powers.duplicate()


func reset_powers() -> void:
	_unlocked_powers.clear()
	_used_sacrifices.clear()
	_cooldowns.clear()
	_offered_sacrifices.clear()
	_clear_pending_choice()
	set_process(false)


func _clear_pending_choice() -> void:
	_choice_in_progress = false
	_pending_power_id = ""


## Renvoie "" si l'effet est appliqué, sinon la raison de l'échec.
func _apply_power_effect(power_id: String) -> String:
	var tree := get_tree()
	var player := tree.get_first_node_in_group("player") as Node3D
	var monster := tree.get_first_node_in_group("monster") as Node3D
	match power_id:
		"shockwave":
			if player == null or monster == null:
				return "no_target"
			if player.global_position.distance_to(monster.global_position) > SHOCKWAVE_RANGE:
				return "out_of_range"
			monster.stun_monster(SHOCKWAVE_STUN_DURATION)
		"spectral_vision":
			if monster == null:
				return "no_target"
			monster.reveal_monster(SPECTRAL_VISION_DURATION)
		"speed_boost":
			if player == null:
				return "no_target"
			player.apply_speed_modifier(SPEED_BOOST_FACTOR, SPEED_BOOST_DURATION)
		"spectral_trap":
			if player == null or tree.current_scene == null:
				return "no_target"
			var trap: Node3D = SPECTRAL_TRAP_SCENE.instantiate()
			tree.current_scene.add_child(trap)
			trap.global_position = player.global_position
			trap.monster_triggered.connect(_on_trap_monster_triggered)
	return ""


func _on_trap_monster_triggered(monster: Node3D) -> void:
	if is_instance_valid(monster):
		monster.slow_down(TRAP_SLOW_DURATION, TRAP_SLOW_FACTOR)
