extends Node3D
## LOST MEMORY - Personne 2 : niveau (Hospital).
## Le niveau fournit des positions GLOBALES et des collisions. Il ne cree
## ni le joueur ni le monstre et ne decide pas de la victoire : Main
## recupere les positions et place les instances.
##
## La scene doit etre dans l'arbre avant d'appeler les fonctions
## (global_position n'est valide que dans l'arbre).
##
## Index de spawn des pouvoirs (ordre des Marker3D de PowerSpawnPoints) :
##   0 shockwave | 1 spectral_vision | 2 speed_boost | 3 spectral_trap

const POWER_SPAWN_COUNT: int = 4
const POWER_IDS: Array[String] = [
	"shockwave", "spectral_vision", "speed_boost", "spectral_trap"
]

## Verification d'accessibilite de la sortie (grille + requetes physiques).
const GRID_STEP: float = 0.5
const AGENT_RADIUS: float = 0.35
const AGENT_HEIGHT: float = 1.8
const EXIT_TOLERANCE: float = 1.0
## Emprise de la map (x, z, largeur, profondeur) en coordonnees globales.
@export var walkable_bounds: Rect2 = Rect2(-10.0, -12.0, 80.0, 24.0)

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


func _ready() -> void:
	add_to_group("hospital")
	_validate()
	var tubes_node: Node = get_node_or_null("Tubes")
	if tubes_node != null:
		_tubes = tubes_node.get_children()
	set_process(flicker_enabled and not _tubes.is_empty())


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


## Exactement 4 positions. L'index correspond a POWER_IDS :
## 0 shockwave, 1 spectral_vision, 2 speed_boost, 3 spectral_trap.
func get_power_spawn_points() -> Array[Vector3]:
	return _collect_positions(power_spawn_points)


## Points de patrouille ordonnes (boucle). Chaque segment est en ligne
## droite sans mur, et le premier point est joignable depuis le spawn.
func get_patrol_points() -> Array[Vector3]:
	return _collect_positions(patrol_points)


func get_exit_position() -> Vector3:
	return exit_marker.global_position


## true si la sortie est accessible depuis le spawn du joueur (obstacles
## et murs pris en compte via les collisions). Resultat mis en cache.
func is_exit_reachable() -> bool:
	if _exit_reachable_cache == -1:
		_exit_reachable_cache = 1 if _compute_exit_reachable() else 0
	return _exit_reachable_cache == 1


## Utilitaire (hors contrat) : power_id associe a un index de spawn.
func get_power_id_for_spawn(index: int) -> String:
	if index < 0 or index >= POWER_IDS.size():
		return ""
	return POWER_IDS[index]


# =======================================================================
# PRIVE
# =======================================================================

func _collect_positions(container: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for child: Node in container.get_children():
		var point := child as Marker3D
		if point != null:
			result.append(point.global_position)
	return result


func _validate() -> void:
	if get_power_spawn_points().size() != POWER_SPAWN_COUNT:
		push_warning("Hospital: %d points de pouvoir attendus." % POWER_SPAWN_COUNT)
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
	var start: Vector3 = get_player_spawn_position()
	var goal: Vector3 = get_exit_position()
	var start_cell: Vector2i = _to_cell(start)
	if not _is_cell_free(space, shape, start_cell):
		return false

	var visited: Dictionary = {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if _cell_to_world(cell, goal.y).distance_to(goal) <= EXIT_TOLERANCE:
			return true
		for d: Vector2i in dirs:
			var next: Vector2i = cell + d
			if visited.has(next) or not _in_bounds(next):
				continue
			visited[next] = true
			if _is_cell_free(space, shape, next):
				queue.append(next)
	return false


func _to_cell(world: Vector3) -> Vector2i:
	return Vector2i(
		roundi((world.x - walkable_bounds.position.x) / GRID_STEP),
		roundi((world.z - walkable_bounds.position.y) / GRID_STEP)
	)


func _cell_to_world(cell: Vector2i, y: float) -> Vector3:
	return Vector3(
		walkable_bounds.position.x + cell.x * GRID_STEP,
		y,
		walkable_bounds.position.y + cell.y * GRID_STEP
	)


func _in_bounds(cell: Vector2i) -> bool:
	var max_x: int = roundi(walkable_bounds.size.x / GRID_STEP)
	var max_z: int = roundi(walkable_bounds.size.y / GRID_STEP)
	return cell.x >= 0 and cell.y >= 0 and cell.x <= max_x and cell.y <= max_z


## Cellule libre = capsule sans collision (levee de 5 cm) ET sol dessous.
func _is_cell_free(space: PhysicsDirectSpaceState3D, shape: CapsuleShape3D, cell: Vector2i) -> bool:
	var base: Vector3 = _cell_to_world(cell, global_position.y)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1
	params.transform = Transform3D(Basis.IDENTITY, base + Vector3.UP * (AGENT_HEIGHT * 0.5 + 0.05))
	if not space.intersect_shape(params, 1).is_empty():
		return false
	var ray := PhysicsRayQueryParameters3D.create(
		base + Vector3.UP * 0.5, base + Vector3.DOWN * 0.5, 1
	)
	return not space.intersect_ray(ray).is_empty()
