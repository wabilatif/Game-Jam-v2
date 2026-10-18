extends Node3D
## LOST MEMORY - Personne 2 : niveau (Hospital).
## Le niveau fournit des positions GLOBALES et des collisions. Il ne cree
## ni le joueur, ni le monstre, ni les objets, et ne decide pas de la
## victoire : Main recupere les positions et place les instances.
##
## La scene doit etre dans l'arbre avant d'appeler les fonctions
## (global_position n'est valide que dans l'arbre).
##
## POUVOIRS ET SECRETS : leurs positions sont tirees AU HASARD a chaque
## lancement. Hospital lit lui-meme les murs et les meubles de la scene
## (aucune zone a dessiner : si la map change, le tirage s'adapte), repere
## le sol atteignable depuis le depart du joueur, et ne place un objet que
## sur une case bien degagee (jamais dans un meuble ni contre un mur), loin
## du joueur et de la sortie, et espace des autres objets.
## Index de spawn des pouvoirs (ordre du tableau renvoye) :
##   0 shockwave | 1 spectral_vision | 2 speed_boost | 3 spectral_trap

const POWER_SPAWN_COUNT: int = 4
const POWER_IDS: Array[String] = [
	"shockwave", "spectral_vision", "speed_boost", "spectral_trap"
]

## --- Tirage aleatoire des objets ----------------------------------------
## Hauteur du point renvoye au-dessus du sol (comme les anciens marqueurs).
const ITEM_HEIGHT: float = 0.5
## Taille d'une case de la grille d'analyse (m).
const CELL_SIZE: float = 0.25
## Marge autour des obstacles pour que le joueur (rayon 0.35) puisse passer.
const WALK_CLEARANCE: float = 0.4
## Marge autour des obstacles pour qu'un objet y soit pose.
const ITEM_CLEARANCE: float = 1.0
## Hauteurs (m) entre lesquelles un solide gene le passage du joueur.
const BODY_MIN_Y: float = 0.1
const BODY_MAX_Y: float = 1.8
const MIN_DISTANCE_FROM_PLAYER: float = 8.0
const MIN_DISTANCE_FROM_EXIT: float = 6.0
## Nombre de candidats testes par objet : on garde le plus isole (les objets
## restent disperses sans former de motif fixe).
const CANDIDATES_PER_ITEM: int = 40
const FALLBACK_ATTEMPTS: int = 400

## --- Depart aleatoire du monstre -----------------------------------------
const MONSTER_MIN_DISTANCE_FROM_PLAYER: float = 20.0
const MONSTER_MIN_DISTANCE_FROM_EXIT: float = 6.0
## Marge (m) autour d'une porte ou le monstre ne peut pas apparaitre.
const MONSTER_DOOR_MARGIN: float = 1.0
const MONSTER_SPAWN_ATTEMPTS: int = 80

## Nombre de secrets a retrouver pour pouvoir gagner.
@export var secret_count: int = 5
## 0 = aleatoire a chaque lancement. Autre valeur = placement reproductible
## (utile pour deboguer).
@export var random_seed: int = 0

## --- Verification d'accessibilite de la sortie (grille + physique) -------
const GRID_STEP: float = 0.5
const AGENT_RADIUS: float = 0.35
const AGENT_HEIGHT: float = 1.8
const EXIT_TOLERANCE: float = 1.0
## Emprise de la map (x, z, largeur, profondeur) en coordonnees globales.
## Utilisee seulement si Geometry/Floor est absent (sinon deduite du sol).
@export var walkable_bounds: Rect2 = Rect2(-10.0, -22.0, 62.0, 44.0)

## Portes : seulement quelques passages du niveau en recoivent une (pas
## partout), tires au hasard a chaque lancement.
@export var door_count: int = 5
const DOOR_STEP: float = 0.25
const DOOR_MIN_WIDTH: float = 1.1
const DOOR_MAX_WIDTH: float = 2.8
const DOOR_WALL_CELLS: int = 4         # mur requis de chaque cote (1 m)
const DOOR_CLEAR_CELLS: int = 3        # passage libre devant / derriere (0.75 m)
const DOOR_MIN_SPACING: float = 7.0
const DOOR_MIN_FROM_PLAYER: float = 3.5
const DOOR_MIN_FROM_EXIT: float = 4.0

## Luminosite : part du reglage appliquee a la luminosite d'ecran et a
## l'intensite des neons (l'ambiance sombre reste, mais lisible).
const BRIGHTNESS_SCREEN_FACTOR: float = 0.6
const BRIGHTNESS_LIGHT_FACTOR: float = 0.8

## Ambiance (meme esthetique que MenuBackground) : un neon defaillant grille
## souvent, les autres rarement. Purement visuel.
@export var flicker_enabled: bool = true
@export var broken_tube_name: StringName = &"Tube_Corridor3"
const BROKEN_CHANCE: float = 0.06
const NORMAL_CHANCE: float = 0.002

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var monster_spawn: Marker3D = $MonsterSpawn
@onready var exit_marker: Marker3D = $ExitMarker
@onready var power_spawn_points: Node3D = $PowerSpawnPoints
@onready var patrol_points: Node3D = $PatrolPoints

var _exit_reachable_cache: int = -1 # -1 inconnu, 0 non, 1 oui
var _tubes: Array[Node] = []
var _power_points: Array[Vector3] = []
var _secret_points: Array[Vector3] = []
var _items_generated: bool = false
var _monster_spawn_ready: bool = false
var _monster_spawn_point: Vector3 = Vector3.ZERO
var _doors: Array[Node3D] = []
var _door_rids: Array[RID] = []

# Analyse du niveau (calculee une seule fois).
var _grid_ready: bool = false
var _grid_origin: Vector2 = Vector2.ZERO
var _grid_width: int = 0
var _grid_height: int = 0
var _item_cells: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	add_to_group("hospital")
	_validate()
	var tubes_node: Node = get_node_or_null("Tubes")
	if tubes_node != null:
		_tubes = tubes_node.get_children()
	set_process(flicker_enabled and not _tubes.is_empty())
	_connect_brightness()
	# Tirage des objets des l'entree dans l'arbre : un rechargement de scene
	# (relance de partie) donne donc une nouvelle disposition.
	_ensure_items()
	_spawn_doors()


func _process(_delta: float) -> void:
	for tube: Node in _tubes:
		var chance: float = BROKEN_CHANCE if tube.name == broken_tube_name else NORMAL_CHANCE
		(tube as Node3D).visible = randf() > chance


# =======================================================================
# API PUBLIQUE
# =======================================================================

## Position sure de depart du joueur (sol libre, loin du monstre).
func get_player_spawn_position() -> Vector3:
	return player_spawn.global_position


## Position initiale du monstre, loin du joueur.
func get_monster_spawn_position() -> Vector3:
	return monster_spawn.global_position


## Hors contrat : position de depart ALEATOIRE du monstre (differente a chaque
## partie). Elle est tiree sur son circuit de patrouille, dont chaque segment
## est en ligne droite sans mur : le monstre n'apparait donc jamais coince dans
## une piece, et sa patrouille reprend tout de suite. Loin du joueur et de la
## sortie, et jamais dans l'emprise d'une porte. Si rien de valide n'est
## trouve, renvoie le MonsterSpawn fixe. Resultat memorise (stable par partie).
func get_random_monster_spawn_position() -> Vector3:
	if _monster_spawn_ready:
		return _monster_spawn_point
	_monster_spawn_ready = true
	_monster_spawn_point = monster_spawn.global_position
	var points: Array[Vector3] = get_patrol_points()
	if points.size() < 2:
		return _monster_spawn_point

	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed + 202
	else:
		rng.randomize()

	var player_pos: Vector3 = get_player_spawn_position()
	var exit_pos: Vector3 = get_exit_position()
	var fallback: Vector3 = Vector3.INF
	var fallback_distance: float = -1.0
	for attempt in MONSTER_SPAWN_ATTEMPTS:
		var index: int = rng.randi_range(0, points.size() - 1)
		var from_point: Vector3 = points[index]
		var to_point: Vector3 = points[(index + 1) % points.size()]
		if _flat_distance(from_point, to_point) < 0.5:
			continue
		var candidate: Vector3 = from_point.lerp(to_point, rng.randf())
		candidate.y = monster_spawn.global_position.y
		if _flat_distance(candidate, exit_pos) < MONSTER_MIN_DISTANCE_FROM_EXIT \
				or _is_near_door(candidate):
			continue
		var distance: float = _flat_distance(candidate, player_pos)
		if distance >= MONSTER_MIN_DISTANCE_FROM_PLAYER:
			_monster_spawn_point = candidate
			return _monster_spawn_point
		if distance > fallback_distance:
			fallback_distance = distance
			fallback = candidate
	# Aucun point assez loin : on prend le plus eloigne du joueur.
	if fallback != Vector3.INF:
		_monster_spawn_point = fallback
	return _monster_spawn_point


## Vrai si le point est dans la zone d'une porte (battant + marge).
func _is_near_door(point: Vector3) -> bool:
	for door: Node3D in _doors:
		if not is_instance_valid(door) or not (door is Door):
			continue
		var door_node: Door = door as Door
		if _flat_distance(point, door_node.get_center_position()) < door_node.get_width() * 0.5 + MONSTER_DOOR_MARGIN:
			return true
	return false


## Exactement 4 positions ALEATOIRES (differentes a chaque partie).
## L'index correspond a POWER_IDS :
## 0 shockwave, 1 spectral_vision, 2 speed_boost, 3 spectral_trap.
func get_power_spawn_points() -> Array[Vector3]:
	_ensure_items()
	return _power_points.duplicate()


## Positions ALEATOIRES des secrets a retrouver (secret_count positions,
## distinctes des pouvoirs). Tous les secrets sont requis pour gagner.
func get_secret_spawn_points() -> Array[Vector3]:
	_ensure_items()
	return _secret_points.duplicate()


## Points de patrouille ordonnes (boucle). Chaque segment est en ligne
## droite sans mur, et le premier point est joignable depuis le spawn.
func get_patrol_points() -> Array[Vector3]:
	return _collect_positions(patrol_points)


func get_exit_position() -> Vector3:
	return exit_marker.global_position


## true si la sortie est accessible depuis le spawn du joueur (obstacles
## et murs pris en compte via les collisions). Resultat mis en cache.
## A appeler apres quelques frames physiques (les CSG creent leurs
## collisions en differe).
func is_exit_reachable() -> bool:
	if _exit_reachable_cache == -1:
		_exit_reachable_cache = 1 if _compute_exit_reachable() else 0
	return _exit_reachable_cache == 1


## Hors contrat (portes) : centre des passages equipes d'une porte.
func get_door_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for door: Node3D in _doors:
		if is_instance_valid(door) and door is Door:
			positions.append((door as Door).get_center_position())
	return positions


func get_doors() -> Array[Node3D]:
	return _doors


## Hors contrat (minimap) : emprise au sol de la map, en global (x, z).
func get_map_bounds() -> Rect2:
	return _get_bounds()


## Hors contrat (minimap) : emprises au sol (x, z) des murs et des meubles
## qui bloquent le joueur. Calculees a la demande depuis la scene.
func get_solid_rects() -> Array[Rect2]:
	return _collect_solid_rects()


## Hors contrat (luminosite) : applique le reglage de luminosite du joueur
## (1.0 = rendu d'origine) a l'environnement et aux neons du niveau.
func apply_brightness(value: float) -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment
		# Valeurs d'origine memorisees sur la ressource (partagee entre les
		# rechargements de scene) pour ne jamais cumuler les reglages.
		if not env.has_meta("base_ambient"):
			env.set_meta("base_ambient", env.ambient_light_energy)
			env.set_meta("base_brightness", env.adjustment_brightness)
		env.ambient_light_energy = float(env.get_meta("base_ambient")) * value * value
		env.adjustment_enabled = true
		env.adjustment_brightness = float(env.get_meta("base_brightness")) * (1.0 + (value - 1.0) * BRIGHTNESS_SCREEN_FACTOR)
	for tube: Node in _tubes:
		for light: Node in tube.find_children("*", "OmniLight3D", true, false):
			var omni := light as OmniLight3D
			if not omni.has_meta("base_energy"):
				omni.set_meta("base_energy", omni.light_energy)
			omni.light_energy = float(omni.get_meta("base_energy")) * (1.0 + (value - 1.0) * BRIGHTNESS_LIGHT_FACTOR)


# =======================================================================
# PORTES
# =======================================================================

## Repere les passages (ouvertures de 1.1 a 2.8 m dans un mur fin), en tire
## door_count au hasard (espaces, loin du depart et de la sortie) et y pose
## une Door. Independant de la disposition : suit une refonte de la map.
func _spawn_doors() -> void:
	for old: Node3D in _doors:
		if is_instance_valid(old):
			old.queue_free()
	_doors.clear()
	_door_rids.clear()
	if door_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed + 101
	else:
		rng.randomize()

	var candidates: Array[Dictionary] = _find_doorways()
	# Melange (Fisher-Yates avec notre RNG, reproductible avec random_seed).
	for i in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Dictionary = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var spawn: Vector3 = get_player_spawn_position()
	var exit_pos: Vector3 = get_exit_position()
	var chosen: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if chosen.size() >= door_count:
			break
		var center: Vector3 = candidate["center"]
		if _flat_distance(center, spawn) < DOOR_MIN_FROM_PLAYER \
				or _flat_distance(center, exit_pos) < DOOR_MIN_FROM_EXIT:
			continue
		var too_close: bool = false
		for other: Dictionary in chosen:
			if _flat_distance(center, other["center"]) < DOOR_MIN_SPACING:
				too_close = true
				break
		if not too_close:
			chosen.append(candidate)

	var root := Node3D.new()
	root.name = "Doors"
	add_child(root)
	for candidate: Dictionary in chosen:
		var door := Door.new()
		var hinge_at_min: bool = rng.randf() < 0.5
		var transposed: bool = candidate["transposed"]
		var u_hinge: float = candidate["u_min"] if hinge_at_min else candidate["u_max"]
		var v_center: float = candidate["v_center"]
		var y: float = player_spawn.global_position.y
		var hinge: Vector3
		var yaw: float
		if not transposed: # passage le long de X
			hinge = Vector3(u_hinge, y, v_center)
			yaw = 0.0 if hinge_at_min else PI
		else: # passage le long de Z
			hinge = Vector3(v_center, y, u_hinge)
			yaw = -PI * 0.5 if hinge_at_min else PI * 0.5
		door.configure(hinge, yaw, candidate["width"], candidate["thickness"])
		door.name = "Door_%d" % (root.get_child_count() + 1)
		root.add_child(door)
		_doors.append(door)
		var panel: Node = door.get_node_or_null("Panel")
		if panel is CollisionObject3D:
			_door_rids.append((panel as CollisionObject3D).get_rid())


func _find_doorways() -> Array[Dictionary]:
	var bounds: Rect2 = _get_bounds()
	var rects: Array[Rect2] = _collect_solid_rects()
	var w: int = ceili(bounds.size.x / DOOR_STEP)
	var h: int = ceili(bounds.size.y / DOOR_STEP)
	var solid := PackedByteArray()
	solid.resize(w * h)
	# Une case est pleine si son CENTRE est dans un rectangle (largeur des
	# passages fidele a 25 cm pres ; les valeurs exactes sont reprises ensuite
	# sur les rectangles eux-memes).
	for rect: Rect2 in rects:
		var x0: int = maxi(0, ceili((rect.position.x - bounds.position.x) / DOOR_STEP - 0.5))
		var x1: int = mini(w - 1, floori((rect.end.x - bounds.position.x) / DOOR_STEP - 0.5))
		var z0: int = maxi(0, ceili((rect.position.y - bounds.position.y) / DOOR_STEP - 0.5))
		var z1: int = mini(h - 1, floori((rect.end.y - bounds.position.y) / DOOR_STEP - 0.5))
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				solid[z * w + x] = 1

	var found: Array[Dictionary] = []
	for transposed: bool in [false, true]:
		_scan_doorways(solid, w, h, transposed, bounds, rects, found)
	return found


## Balayage dans un sens (passage le long de X, ou le long de Z si transposed).
func _scan_doorways(solid: PackedByteArray, w: int, h: int, transposed: bool,
		bounds: Rect2, rects: Array[Rect2], out: Array[Dictionary]) -> void:
	var u_size: int = h if transposed else w
	var v_size: int = w if transposed else h
	var origin_u: float = bounds.position.y if transposed else bounds.position.x
	var origin_v: float = bounds.position.x if transposed else bounds.position.y
	for v in v_size:
		var u: int = 0
		while u < u_size:
			if _is_solid(solid, w, h, u, v, transposed):
				u += 1
				continue
			var start: int = u
			while u < u_size and not _is_solid(solid, w, h, u, v, transposed):
				u += 1
			var end: int = u # exclusif
			var length: float = (end - start) * DOOR_STEP
			if start == 0 or end >= u_size or length < DOOR_MIN_WIDTH - DOOR_STEP \
					or length > DOOR_MAX_WIDTH + DOOR_STEP:
				continue
			# On ne traite une ouverture qu'a sa premiere rangee.
			if v > 0 and _is_gap_row(solid, w, h, start, end, v - 1, transposed):
				continue
			if not _is_gap_row(solid, w, h, start, end, v, transposed):
				continue
			var v_last: int = v
			while _is_gap_row(solid, w, h, start, end, v_last + 1, transposed):
				v_last += 1
			var thickness_cells: int = v_last - v + 1
			if thickness_cells > 3:
				continue
			if not _is_wall_continuing(solid, w, h, start, end, v, v_last, transposed):
				continue
			if not _is_passage_clear(solid, w, h, start, end, v, v_last, transposed):
				continue
			var u_center: float = origin_u + (start + end) * 0.5 * DOOR_STEP
			var v_center: float = origin_v + (v + v_last + 1) * 0.5 * DOOR_STEP
			var record: Dictionary = _refine_doorway(rects, transposed, u_center, v_center)
			if record.is_empty() or not _is_swing_clear(rects, record):
				continue
			out.append(record)


func _is_solid(solid: PackedByteArray, w: int, h: int, u: int, v: int, transposed: bool) -> bool:
	var x: int = v if transposed else u
	var z: int = u if transposed else v
	if x < 0 or z < 0 or x >= w or z >= h:
		return true # hors map = mur
	return solid[z * w + x] == 1


## Rangee v : les cases start..end-1 sont libres, encadrees par du mur.
func _is_gap_row(solid: PackedByteArray, w: int, h: int, start: int, end: int, v: int, transposed: bool) -> bool:
	if not _is_solid(solid, w, h, start - 1, v, transposed) or not _is_solid(solid, w, h, end, v, transposed):
		return false
	for u in range(start, end):
		if _is_solid(solid, w, h, u, v, transposed):
			return false
	return true


## Le mur se prolonge d'au moins 1 m de chaque cote de l'ouverture.
func _is_wall_continuing(solid: PackedByteArray, w: int, h: int, start: int, end: int,
		v_first: int, v_last: int, transposed: bool) -> bool:
	var v_mid: int = (v_first + v_last) / 2
	for k in range(1, DOOR_WALL_CELLS + 1):
		if not _is_solid(solid, w, h, start - k, v_mid, transposed) \
				or not _is_solid(solid, w, h, end - 1 + k, v_mid, transposed):
			return false
	return true


## Libre devant et derriere l'ouverture (on peut la franchir).
func _is_passage_clear(solid: PackedByteArray, w: int, h: int, start: int, end: int,
		v_first: int, v_last: int, transposed: bool) -> bool:
	for k in range(1, DOOR_CLEAR_CELLS + 1):
		for u in range(start, end):
			if _is_solid(solid, w, h, u, v_first - k, transposed) \
					or _is_solid(solid, w, h, u, v_last + k, transposed):
				return false
	return true


## Le battant (largeur x largeur de chaque cote) ne traverse aucun meuble :
## il peut s'ouvrir dans les deux sens sans entrer dans un lit ou un mur.
func _is_swing_clear(rects: Array[Rect2], record: Dictionary) -> bool:
	var half_t: float = float(record["thickness"]) * 0.5 + 0.04
	var width: float = record["width"]
	var u0: float = float(record["u_min"]) + 0.05
	var v_center: float = record["v_center"]
	for side: float in [-1.0, 1.0]:
		var v0: float = v_center + half_t if side > 0.0 else v_center - half_t - width
		var area: Rect2
		if record["transposed"]:
			area = Rect2(v0, u0, width, width - 0.1)
		else:
			area = Rect2(u0, v0, width - 0.1, width)
		for rect: Rect2 in rects:
			if rect.intersects(area):
				return false
	return true


## Reprend les bords exacts de l'ouverture sur les rectangles du mur.
func _refine_doorway(rects: Array[Rect2], transposed: bool, u_center: float, v_center: float) -> Dictionary:
	var u_min: float = -INF
	var u_max: float = INF
	var thickness: float = 0.4
	for rect: Rect2 in rects:
		var r_u0: float = rect.position.y if transposed else rect.position.x
		var r_u1: float = rect.end.y if transposed else rect.end.x
		var r_v0: float = rect.position.x if transposed else rect.position.y
		var r_v1: float = rect.end.x if transposed else rect.end.y
		if r_v0 > v_center + 0.1 or r_v1 < v_center - 0.1:
			continue
		if r_u1 <= u_center + 0.01 and r_u1 > u_min:
			u_min = r_u1
			thickness = clampf(r_v1 - r_v0, 0.2, 0.8)
		elif r_u0 >= u_center - 0.01 and r_u0 < u_max:
			u_max = r_u0
	var width: float = u_max - u_min
	if not is_finite(width) or width < DOOR_MIN_WIDTH or width > DOOR_MAX_WIDTH:
		return {}
	var center_u: float = (u_min + u_max) * 0.5
	var center: Vector3 = Vector3(v_center, 0.0, center_u) if transposed else Vector3(center_u, 0.0, v_center)
	return {
		"center": center,
		"u_min": u_min,
		"u_max": u_max,
		"v_center": v_center,
		"transposed": transposed,
		"width": width,
		"thickness": thickness,
	}


## Utilitaire (hors contrat) : power_id associe a un index de spawn.
func get_power_id_for_spawn(index: int) -> String:
	if index < 0 or index >= POWER_IDS.size():
		return ""
	return POWER_IDS[index]


## Utilitaire (hors contrat) : retire au sort une nouvelle disposition des
## pouvoirs et des secrets (a appeler AVANT que Main place les objets).
func reroll_items() -> void:
	_items_generated = false
	_ensure_items()


# =======================================================================
# PRIVE - TIRAGE ALEATOIRE
# =======================================================================

func _ensure_items() -> void:
	if _items_generated:
		return
	_items_generated = true
	_power_points.clear()
	_secret_points.clear()

	_build_grid()
	if _item_cells.is_empty():
		push_warning("Hospital: aucune case libre trouvee, positions fixes utilisees.")
		_power_points = _collect_positions(power_spawn_points)
		return

	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed
	else:
		rng.randomize()

	var total: int = POWER_SPAWN_COUNT + maxi(secret_count, 0)
	var chosen: Array[Vector3] = []
	for i in total:
		chosen.append(_pick_point(rng, chosen))

	for i in chosen.size():
		if i < POWER_SPAWN_COUNT:
			_power_points.append(chosen[i])
		else:
			_secret_points.append(chosen[i])


## Meilleur candidat parmi plusieurs tirages : valide (loin du joueur et de
## la sortie) et le plus eloigne des objets deja places.
func _pick_point(rng: RandomNumberGenerator, chosen: Array[Vector3]) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_score: float = -1.0
	for attempt in CANDIDATES_PER_ITEM:
		var candidate: Vector3 = _random_candidate(rng)
		if not _is_candidate_valid(candidate):
			continue
		var score: float = _nearest_distance(candidate, chosen)
		if score > best_score:
			best_score = score
			best = candidate
	if best != Vector3.INF:
		return best

	# Rien de valide : on elargit la recherche sans exigence d'espacement.
	for attempt in FALLBACK_ATTEMPTS:
		var candidate: Vector3 = _random_candidate(rng)
		if _is_candidate_valid(candidate):
			return candidate
	push_warning("Hospital: aucun emplacement valide trouve, case libre quelconque utilisee.")
	return _random_candidate(rng)


## Point uniforme sur une case libre et atteignable (tirage par surface).
func _random_candidate(rng: RandomNumberGenerator) -> Vector3:
	var index: int = _item_cells[rng.randi_range(0, _item_cells.size() - 1)]
	var cell := Vector2i(index % _grid_width, index / _grid_width)
	var half: float = CELL_SIZE * 0.5
	return Vector3(
		_grid_origin.x + cell.x * CELL_SIZE + rng.randf_range(-half, half),
		global_position.y + ITEM_HEIGHT,
		_grid_origin.y + cell.y * CELL_SIZE + rng.randf_range(-half, half)
	)


func _is_candidate_valid(candidate: Vector3) -> bool:
	if _flat_distance(candidate, get_player_spawn_position()) < MIN_DISTANCE_FROM_PLAYER:
		return false
	if _flat_distance(candidate, get_exit_position()) < MIN_DISTANCE_FROM_EXIT:
		return false
	return true


func _nearest_distance(point: Vector3, others: Array[Vector3]) -> float:
	if others.is_empty():
		return 1000.0
	var best: float = INF
	for other in others:
		best = minf(best, _flat_distance(point, other))
	return best


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# =======================================================================
# PRIVE - ANALYSE DU NIVEAU (grille d'occupation)
# =======================================================================

## Emprise au sol : celle du sol (Geometry/Floor) si elle existe.
func _get_bounds() -> Rect2:
	var floor_box := get_node_or_null("Geometry/Floor") as CSGBox3D
	if floor_box != null:
		var rect: Rect2 = _footprint(floor_box.global_transform, floor_box.size * 0.5, Vector3.ZERO)
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			return rect
	return walkable_bounds


## Rectangle XZ occupe par une boite (centre local, demi-tailles, transform).
func _footprint(xform: Transform3D, half: Vector3, center: Vector3) -> Rect2:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner: Vector3 = xform * (center + Vector3(half.x * sx, 0.0, half.z * sz))
			min_p = min_p.min(Vector2(corner.x, corner.z))
			max_p = max_p.max(Vector2(corner.x, corner.z))
	return Rect2(min_p, max_p - min_p)


## Intervalle de hauteur (min, max) occupe par une boite, en global.
func _height_range(xform: Transform3D, half: Vector3, center: Vector3) -> Vector2:
	var low: float = INF
	var high: float = -INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner: Vector3 = xform * (center + Vector3(half.x * sx, half.y * sy, half.z * sz))
				low = minf(low, corner.y)
				high = maxf(high, corner.y)
	return Vector2(low, high)


## Murs, meubles et cachettes qui bloquent le joueur (en emprise au sol).
## - CSGBox3D avec collision (murs, meubles) ;
## - CollisionShape3D d'un corps physique (cachettes, lits) ;
## - les zones Area3D (declencheurs) sont ignorees ;
## - tout ce qui est au-dessus de la tete (linteaux, plafond) ou au sol
##   (dalle) ne bloque pas.
func _collect_solid_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	_gather_solids(self, rects)
	return rects


func _gather_solids(node: Node, out: Array[Rect2]) -> void:
	for child: Node in node.get_children():
		if child is Area3D or child.is_in_group("doors"):
			continue
		if child is CSGBox3D:
			var box := child as CSGBox3D
			if box.use_collision:
				_add_solid(out, box.global_transform, box.size * 0.5, Vector3.ZERO)
		elif child is CollisionShape3D:
			var collision := child as CollisionShape3D
			if collision.shape != null and not collision.disabled \
					and collision.get_parent() is PhysicsBody3D:
				var aabb: AABB = collision.shape.get_debug_mesh().get_aabb()
				_add_solid(out, collision.global_transform, aabb.size * 0.5, aabb.get_center())
		_gather_solids(child, out)


func _add_solid(out: Array[Rect2], xform: Transform3D, half: Vector3, center: Vector3) -> void:
	var heights: Vector2 = _height_range(xform, half, center)
	if heights.y <= BODY_MIN_Y or heights.x >= BODY_MAX_Y:
		return
	out.append(_footprint(xform, half, center))


## Case = (x, z) -> indice. 1 = bloque.
func _rasterize(rects: Array[Rect2], grow: float) -> PackedByteArray:
	var blocked := PackedByteArray()
	blocked.resize(_grid_width * _grid_height)
	for rect in rects:
		var area: Rect2 = rect.grow(grow)
		var x0: int = maxi(ceili((area.position.x - _grid_origin.x) / CELL_SIZE), 0)
		var x1: int = mini(floori((area.end.x - _grid_origin.x) / CELL_SIZE), _grid_width - 1)
		var z0: int = maxi(ceili((area.position.y - _grid_origin.y) / CELL_SIZE), 0)
		var z1: int = mini(floori((area.end.y - _grid_origin.y) / CELL_SIZE), _grid_height - 1)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				blocked[z * _grid_width + x] = 1
	return blocked


func _cell_index_of(world: Vector3) -> int:
	var x: int = roundi((world.x - _grid_origin.x) / CELL_SIZE)
	var z: int = roundi((world.z - _grid_origin.y) / CELL_SIZE)
	if x < 0 or z < 0 or x >= _grid_width or z >= _grid_height:
		return -1
	return z * _grid_width + x


## Construit une fois : sol atteignable depuis le joueur, puis cases assez
## degagees pour y poser un objet (_item_cells).
func _build_grid() -> void:
	if _grid_ready:
		return
	_grid_ready = true
	_item_cells = PackedInt32Array()

	var bounds: Rect2 = _get_bounds()
	_grid_origin = bounds.position
	_grid_width = ceili(bounds.size.x / CELL_SIZE) + 1
	_grid_height = ceili(bounds.size.y / CELL_SIZE) + 1

	var solids: Array[Rect2] = _collect_solid_rects()
	var walk_blocked: PackedByteArray = _rasterize(solids, WALK_CLEARANCE)
	var item_blocked: PackedByteArray = _rasterize(solids, ITEM_CLEARANCE)

	# Bords de la map : toujours bloques.
	for x in _grid_width:
		walk_blocked[x] = 1
		walk_blocked[(_grid_height - 1) * _grid_width + x] = 1
	for z in _grid_height:
		walk_blocked[z * _grid_width] = 1
		walk_blocked[z * _grid_width + _grid_width - 1] = 1

	var start: int = _cell_index_of(get_player_spawn_position())
	if start < 0 or walk_blocked[start] == 1:
		push_warning("Hospital: depart du joueur invalide pour l'analyse du niveau.")
		return

	# Parcours en largeur depuis le depart : seules les cases atteignables a
	# pied comptent (une piece fermee ne recevra jamais d'objet).
	var seen := PackedByteArray()
	seen.resize(_grid_width * _grid_height)
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head: int = 0
	while head < queue.size():
		var index: int = queue[head]
		head += 1
		if item_blocked[index] == 0:
			_item_cells.append(index)
		var cx: int = index % _grid_width
		var cz: int = index / _grid_width
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + step.x
			var nz: int = cz + step.y
			if nx < 0 or nz < 0 or nx >= _grid_width or nz >= _grid_height:
				continue
			var next: int = nz * _grid_width + nx
			if seen[next] == 1 or walk_blocked[next] == 1:
				continue
			seen[next] = 1
			queue.append(next)


# =======================================================================
# PRIVE - DIVERS
# =======================================================================

func _collect_positions(container: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for child: Node in container.get_children():
		var point := child as Marker3D
		if point != null:
			result.append(point.global_position)
	return result


## Suit le reglage de luminosite (EffectsManager) : applique la valeur
## actuelle puis chaque changement.
func _connect_brightness() -> void:
	var effects: Node = get_node_or_null("/root/EffectsManager")
	if effects == null or not effects.has_signal("brightness_changed"):
		return
	if not effects.is_connected("brightness_changed", apply_brightness):
		effects.connect("brightness_changed", apply_brightness)
	apply_brightness(effects.get_brightness())


func _validate() -> void:
	if get_patrol_points().is_empty():
		push_warning("Hospital: aucun point de patrouille.")


func _compute_exit_reachable() -> bool:
	if not is_inside_tree():
		push_warning("Hospital: is_exit_reachable() appelee hors de l'arbre.")
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = AGENT_RADIUS
	shape.height = AGENT_HEIGHT
	var bounds: Rect2 = _get_bounds()
	var start: Vector3 = get_player_spawn_position()
	var goal: Vector3 = get_exit_position()
	var start_cell: Vector2i = _to_cell(start, bounds)
	if not _is_cell_free(space, shape, start_cell, bounds):
		return false

	var visited: Dictionary = {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if _cell_to_world(cell, goal.y, bounds).distance_to(goal) <= EXIT_TOLERANCE:
			return true
		for d: Vector2i in dirs:
			var next: Vector2i = cell + d
			if visited.has(next) or not _in_bounds(next, bounds):
				continue
			visited[next] = true
			if _is_cell_free(space, shape, next, bounds):
				queue.append(next)
	return false


func _to_cell(world: Vector3, bounds: Rect2) -> Vector2i:
	return Vector2i(
		roundi((world.x - bounds.position.x) / GRID_STEP),
		roundi((world.z - bounds.position.y) / GRID_STEP)
	)


func _cell_to_world(cell: Vector2i, y: float, bounds: Rect2) -> Vector3:
	return Vector3(
		bounds.position.x + cell.x * GRID_STEP,
		y,
		bounds.position.y + cell.y * GRID_STEP
	)


func _in_bounds(cell: Vector2i, bounds: Rect2) -> bool:
	var max_x: int = roundi(bounds.size.x / GRID_STEP)
	var max_z: int = roundi(bounds.size.y / GRID_STEP)
	return cell.x >= 0 and cell.y >= 0 and cell.x <= max_x and cell.y <= max_z


## Cellule libre = capsule sans collision (levee de 5 cm) ET sol dessous.
func _is_cell_free(
	space: PhysicsDirectSpaceState3D, shape: CapsuleShape3D, cell: Vector2i, bounds: Rect2
) -> bool:
	var base: Vector3 = _cell_to_world(cell, global_position.y, bounds)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1
	params.exclude = _door_rids # une porte fermee s'ouvre : ce n'est pas un mur
	params.transform = Transform3D(Basis.IDENTITY, base + Vector3.UP * (AGENT_HEIGHT * 0.5 + 0.05))
	if not space.intersect_shape(params, 1).is_empty():
		return false
	var ray := PhysicsRayQueryParameters3D.create(
		base + Vector3.UP * 0.5, base + Vector3.DOWN * 0.5, 1
	)
	ray.exclude = _door_rids
	return not space.intersect_ray(ray).is_empty()
