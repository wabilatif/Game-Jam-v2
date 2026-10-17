extends Node
## LOST MEMORY - Autoload NoiseManager : le bruit que fait le joueur.
##
## Le jeu "emet" des bruits (une porte ouverte en courant, etc.) avec une
## position et un rayon. Le MONSTRE (ou tout autre ecouteur) "recoit" les
## bruits en demandant ce qu'il entend DEPUIS SA POSITION :
##
##     var heard: Dictionary = NoiseManager.get_noise_heard_at(global_position)
##     if not heard.is_empty():
##         # heard.position  : Vector3, ou le bruit a ete fait (point a aller voir)
##         # heard.intensity : 0..1 (1 = juste a cote, ~0 = a la limite d'audibilite)
##         # heard.distance  : distance monstre -> bruit (m)
##         # heard.age       : secondes depuis l'emission
##         # heard.source    : ex. "door_slam", "door_creak"
##
## Variante "ne reagir qu'une fois" : consume_noise_heard_at(position) renvoie
## le meme dictionnaire mais marque le bruit comme traite.
##
## DIFFICULTE : tout se regle ici, sans toucher au monstre.
##   - set_difficulty(DIFFICULTY_HARD) ou hearing_multiplier = 1.6
##     (agrandit la distance a laquelle le monstre entend : x1.0 = normal).
##   - les rayons de base de chaque bruit sont les constantes RADIUS_*.
##
## L'audibilite = distance a vol d'oiseau (les murs n'attenuent pas le son).

signal noise_emitted(position: Vector3, radius: float, source: StringName)

## Rayons de base (metres) : distance a laquelle un bruit est audible
## par un monstre avec hearing_multiplier = 1.0.
const RADIUS_DOOR_WALK: float = 7.0    # porte ouverte en marchant : grincement
const RADIUS_DOOR_RUN: float = 22.0    # porte ouverte en courant : claquement
const RADIUS_DOOR_CLOSE: float = 5.0   # porte refermee doucement

## Un bruit reste "entendable" ce temps (secondes de jeu, pause exclue).
const NOISE_LIFETIME: float = 8.0

enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE }
const DIFFICULTY_MULTIPLIERS: Dictionary = {
	Difficulty.EASY: 0.7,
	Difficulty.NORMAL: 1.0,
	Difficulty.HARD: 1.5,
	Difficulty.NIGHTMARE: 2.0,
}

## Multiplicateur global de l'ouie du monstre (voir set_difficulty).
var hearing_multiplier: float = 1.0

var _clock: float = 0.0
var _noises: Array[Dictionary] = []
var _next_id: int = 1


func _ready() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager != null:
		for signal_name: String in ["game_started", "game_restarted"]:
			if game_manager.has_signal(signal_name):
				game_manager.connect(signal_name, clear_noises)


func _process(delta: float) -> void:
	_clock += delta
	# Purge des bruits trop vieux.
	var i: int = _noises.size() - 1
	while i >= 0:
		if _clock - float(_noises[i]["time"]) > NOISE_LIFETIME:
			_noises.remove_at(i)
		i -= 1


# =======================================================================
# EMISSION (cote joueur / monde)
# =======================================================================

## Enregistre un bruit. radius = distance d'audibilite de base (m).
## player_made = false pour un bruit qui ne doit pas attirer le monstre
## (ex. la porte qu'il ouvre lui-meme).
func emit_noise(position: Vector3, radius: float, source: StringName = &"", player_made: bool = true) -> void:
	_noises.append({
		"id": _next_id,
		"position": position,
		"radius": radius,
		"source": source,
		"time": _clock,
		"player_made": player_made,
		"consumed": false,
	})
	_next_id += 1
	noise_emitted.emit(position, radius, source)


# =======================================================================
# RECEPTION (cote monstre)
# =======================================================================

## Le bruit le plus fort que l'on entend depuis listener_position, ou un
## dictionnaire vide s'il n'y en a pas. Ne modifie rien (peut etre appelee
## a chaque frame). listener_multiplier : ouie propre a l'ecouteur (x1.0).
func get_noise_heard_at(listener_position: Vector3, listener_multiplier: float = 1.0) -> Dictionary:
	return _find_best(listener_position, listener_multiplier, false)


## Comme get_noise_heard_at, mais marque le bruit comme traite : il ne sera
## plus renvoye (utile pour "aller voir" une seule fois).
func consume_noise_heard_at(listener_position: Vector3, listener_multiplier: float = 1.0) -> Dictionary:
	return _find_best(listener_position, listener_multiplier, true)


func has_noise_heard_at(listener_position: Vector3, listener_multiplier: float = 1.0) -> bool:
	return not get_noise_heard_at(listener_position, listener_multiplier).is_empty()


## Intensite (0..1) d'un bruit pour un ecouteur donne ; 0 si inaudible.
func get_intensity(noise_position: Vector3, noise_radius: float, listener_position: Vector3, listener_multiplier: float = 1.0) -> float:
	var effective: float = noise_radius * hearing_multiplier * listener_multiplier
	if effective <= 0.0:
		return 0.0
	var distance: float = _flat_distance(noise_position, listener_position)
	if distance > effective:
		return 0.0
	return 1.0 - distance / effective


# =======================================================================
# DIFFICULTE ET OUTILS
# =======================================================================

func set_difficulty(level: Difficulty) -> void:
	hearing_multiplier = float(DIFFICULTY_MULTIPLIERS.get(level, 1.0))


func clear_noises() -> void:
	_noises.clear()


func get_active_noise_count() -> int:
	return _noises.size()


# =======================================================================
# PRIVE
# =======================================================================

func _find_best(listener_position: Vector3, listener_multiplier: float, consume: bool) -> Dictionary:
	var best_index: int = -1
	var best_intensity: float = 0.0
	for i in _noises.size():
		var noise: Dictionary = _noises[i]
		if not bool(noise["player_made"]) or bool(noise["consumed"]):
			continue
		var intensity: float = get_intensity(
				noise["position"], float(noise["radius"]), listener_position, listener_multiplier)
		if intensity > best_intensity:
			best_intensity = intensity
			best_index = i
	if best_index < 0:
		return {}
	var found: Dictionary = _noises[best_index]
	if consume:
		found["consumed"] = true
	return {
		"position": found["position"],
		"intensity": best_intensity,
		"distance": _flat_distance(found["position"], listener_position),
		"age": _clock - float(found["time"]),
		"source": found["source"],
		"radius": float(found["radius"]),
	}


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
