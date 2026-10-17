class_name Door
extends Node3D
## LOST MEMORY - Porte a gonds posee dans un passage du niveau.
##
## - Le joueur l'ouvre / la ferme avec [E] (comme les cachettes).
## - Bruit selon la facon d'ouvrir : EN COURANT = claquement violent (grande
##   portee), EN MARCHANT = grincement lent (petite portee). Le bruit est
##   envoye a NoiseManager, que le monstre interroge selon sa position.
## - Le monstre ouvre les portes tout seul (il n'a pas besoin de code pour
##   ca) : une porte fermee ne le bloque jamais, mais le joueur l'entend.
##
## Cree par Hospital.gd (voir _spawn_doors) : configure() puis add_child().
## Les portes sont dans le groupe "doors" et ignorees par la mini-map / le
## placement des objets (elles ne comptent pas comme murs).

signal opened(by_player: bool, loud: bool)
signal closed(by_player: bool)

enum State { CLOSED, OPENING, OPEN, CLOSING }

const DOOR_HEIGHT: float = 2.4
const WALL_HEIGHT: float = 3.0
const PANEL_THICKNESS: float = 0.07
const PANEL_MARGIN: float = 0.03
const OPEN_ANGLE: float = 1.75 # ~100 degres
const WALK_OPEN_TIME: float = 1.25
const RUN_OPEN_TIME: float = 0.28
const CLOSE_TIME: float = 0.9
const MONSTER_OPEN_TIME: float = 0.3
const INTERACT_DISTANCE: float = 2.4
const FACING_DOT: float = 0.35
const CLEAR_BAND: float = 0.75

const CREAK_PATH: String = "res://audio/sfx/door_creak.wav"
const SLAM_PATH: String = "res://audio/sfx/door_slam.wav"

const PROMPT_OPEN: String = "[E] Ouvrir la porte"
const PROMPT_CLOSE: String = "[E] Fermer la porte"

static var _creak_stream: AudioStream
static var _slam_stream: AudioStream

var _hinge: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _width: float = 1.6
var _wall_thickness: float = 0.4
var _state: State = State.CLOSED
var _open_sign: float = 1.0
var _tween: Tween

var _panel: AnimatableBody3D
var _zone: Area3D
var _prompt: Label3D
var _audio: AudioStreamPlayer3D
var _player_nearby: Node3D
var _monsters_inside: Array[Node3D] = []


## hinge : position globale du gond ; yaw : rotation Y de la porte fermee
## (son axe local +X part du gond le long du passage) ; width : largeur du
## passage ; wall_thickness : epaisseur du mur traverse.
func configure(hinge: Vector3, yaw: float, width: float, wall_thickness: float) -> void:
	_hinge = hinge
	_yaw = yaw
	_width = width
	_wall_thickness = wall_thickness


func _ready() -> void:
	add_to_group("doors")
	global_position = _hinge
	global_rotation = Vector3(0.0, _yaw, 0.0)
	_build()


func _physics_process(_delta: float) -> void:
	# Le monstre est dans la zone alors que la porte est fermee (ex. le joueur
	# l'a refermee a ce moment) : il l'ouvre, il ne doit jamais rester bloque.
	if _state == State.CLOSED and not _monsters_inside.is_empty():
		_prune_monsters()
		if not _monsters_inside.is_empty():
			_open(_monsters_inside[0].global_position, true, false)


func _process(_delta: float) -> void:
	if _player_nearby == null:
		if _prompt.visible:
			_prompt.visible = false
		return
	var show_prompt: bool = _is_interaction_target(_player_nearby) \
			and (_state == State.CLOSED or _state == State.OPEN)
	if show_prompt:
		_prompt.text = PROMPT_CLOSE if _state == State.OPEN else PROMPT_OPEN
	_prompt.visible = show_prompt


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action("interact") or not event.is_action_pressed("interact"):
		return
	if _player_nearby == null or not _is_interaction_target(_player_nearby):
		return
	if interact(_player_nearby):
		get_viewport().set_input_as_handled()


# =======================================================================
# API
# =======================================================================

## Le joueur actionne la porte. Renvoie true si quelque chose s'est passe.
func interact(player: Node3D) -> bool:
	match _state:
		State.CLOSED:
			var running: bool = player.has_method("is_sprinting") and bool(player.is_sprinting())
			_open(player.global_position, running, true)
			return true
		State.OPEN:
			return _close(player)
	return false


func get_state() -> State:
	return _state


func is_open() -> bool:
	return _state == State.OPEN or _state == State.OPENING


## Centre du passage (global), la ou le bruit est emis.
func get_center_position() -> Vector3:
	return to_global(Vector3(_width * 0.5, 0.0, 0.0))


func get_width() -> float:
	return _width


# =======================================================================
# OUVERTURE / FERMETURE
# =======================================================================

func _open(opener_position: Vector3, loud: bool, by_player: bool) -> void:
	if _state != State.CLOSED:
		return
	# S'ouvre en s'eloignant de celui qui la pousse.
	_open_sign = 1.0 if to_local(opener_position).z > 0.0 else -1.0
	var duration: float = RUN_OPEN_TIME if loud else WALK_OPEN_TIME
	if not by_player:
		duration = MONSTER_OPEN_TIME
	_swing(_open_sign * OPEN_ANGLE, duration, State.OPENING, State.OPEN)
	_play(_slam_stream_get() if loud else _creak_stream_get(), 2.0 if loud else -6.0)
	_emit_noise(loud, by_player)
	opened.emit(by_player, loud)


func _close(player: Node3D) -> bool:
	if _state != State.OPEN:
		return false
	# On ne ferme pas une porte sur quelqu'un, ni devant le monstre.
	_prune_monsters()
	if not _monsters_inside.is_empty() or _is_in_doorway(player.global_position):
		return false
	_swing(0.0, CLOSE_TIME, State.CLOSING, State.CLOSED)
	_play(_creak_stream_get(), -12.0, 0.85)
	var noise: Node = get_node_or_null("/root/NoiseManager")
	if noise != null:
		noise.emit_noise(get_center_position(), noise.RADIUS_DOOR_CLOSE, &"door_close", true)
	closed.emit(true)
	return true


func _swing(target_angle: float, duration: float, moving: State, done: State) -> void:
	if _tween != null:
		_tween.kill()
	_state = moving
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if duration < 0.5 else Tween.EASE_IN_OUT)
	_tween.tween_property(_panel, "rotation:y", target_angle, duration)
	_tween.finished.connect(func() -> void: _state = done)


func _emit_noise(loud: bool, by_player: bool) -> void:
	var noise: Node = get_node_or_null("/root/NoiseManager")
	if noise == null:
		return
	if by_player:
		noise.emit_noise(
				get_center_position(),
				noise.RADIUS_DOOR_RUN if loud else noise.RADIUS_DOOR_WALK,
				&"door_slam" if loud else &"door_creak", true)
	else:
		# Le monstre ouvre la porte : le joueur l'entend, mais ce n'est pas
		# un bruit du joueur (le monstre ne se "repond" pas a lui-meme).
		noise.emit_noise(get_center_position(), noise.RADIUS_DOOR_RUN, &"door_monster", false)


# =======================================================================
# CONSTRUCTION
# =======================================================================

func _build() -> void:
	var panel_width: float = _width - PANEL_MARGIN
	var panel_size := Vector3(panel_width, DOOR_HEIGHT, PANEL_THICKNESS)

	_panel = AnimatableBody3D.new()
	_panel.name = "Panel"
	_panel.collision_layer = 1
	_panel.collision_mask = 0
	add_child(_panel)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = panel_size
	shape.shape = box
	shape.position = Vector3(panel_width * 0.5 + PANEL_MARGIN * 0.5, DOOR_HEIGHT * 0.5, 0.0)
	_panel.add_child(shape)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.27, 0.23)
	wood.roughness = 0.82
	wood.metallic = 0.15
	var mesh := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = panel_size
	panel_mesh.material = wood
	mesh.mesh = panel_mesh
	mesh.position = shape.position
	_panel.add_child(mesh)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.64, 0.6)
	metal.metallic = 0.85
	metal.roughness = 0.3
	for side: float in [-1.0, 1.0]:
		var handle := MeshInstance3D.new()
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(0.14, 0.04, 0.05)
		handle_mesh.material = metal
		handle.mesh = handle_mesh
		handle.position = Vector3(panel_width - 0.1, 1.05, side * (PANEL_THICKNESS * 0.5 + 0.025))
		_panel.add_child(handle)

	# Linteau fixe au-dessus de la porte (le mur du niveau a un passage
	# haut de 3 m) : pas de collision, la tete du joueur passe en dessous.
	var lintel_height: float = WALL_HEIGHT - DOOR_HEIGHT
	if lintel_height > 0.01:
		var lintel := MeshInstance3D.new()
		var lintel_mesh := BoxMesh.new()
		lintel_mesh.size = Vector3(_width, lintel_height, _wall_thickness)
		var concrete := StandardMaterial3D.new()
		concrete.albedo_color = Color(0.2, 0.21, 0.19)
		concrete.roughness = 0.95
		lintel_mesh.material = concrete
		lintel.mesh = lintel_mesh
		lintel.position = Vector3(_width * 0.5, DOOR_HEIGHT + lintel_height * 0.5, 0.0)
		add_child(lintel)

	# Zone de detection (joueur : invite ; monstre : ouverture automatique).
	_zone = Area3D.new()
	_zone.name = "Zone"
	_zone.collision_layer = 0
	_zone.collision_mask = 3 # joueur (1) + monstre (2)
	var zone_shape := CollisionShape3D.new()
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(_width + 0.6, 2.2, INTERACT_DISTANCE * 1.4)
	zone_shape.shape = zone_box
	zone_shape.position = Vector3(_width * 0.5, 1.1, 0.0)
	_zone.add_child(zone_shape)
	add_child(_zone)
	_zone.body_entered.connect(_on_body_entered)
	_zone.body_exited.connect(_on_body_exited)

	_prompt = Label3D.new()
	_prompt.name = "PromptLabel"
	_prompt.text = PROMPT_OPEN
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 28
	_prompt.outline_size = 8
	_prompt.modulate = Color(0.96, 0.94, 0.85)
	_prompt.outline_modulate = Color(0.05, 0.05, 0.05, 0.9)
	_prompt.position = Vector3(_width * 0.5, 1.85, 0.0)
	_prompt.visible = false
	add_child(_prompt)

	_audio = AudioStreamPlayer3D.new()
	_audio.name = "Audio"
	_audio.position = Vector3(_width * 0.5, 1.2, 0.0)
	_audio.max_distance = 45.0
	_audio.unit_size = 9.0
	add_child(_audio)


# =======================================================================
# DETECTION
# =======================================================================

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_nearby = body
	elif _is_monster(body):
		if not _monsters_inside.has(body):
			_monsters_inside.append(body)
		if _state == State.CLOSED:
			_open(body.global_position, true, false)


func _on_body_exited(body: Node3D) -> void:
	if body == _player_nearby:
		_player_nearby = null
	_monsters_inside.erase(body)


func _is_monster(body: Node3D) -> bool:
	return body.is_in_group("monster") or body.has_method("get_monster_position")


func _prune_monsters() -> void:
	var alive: Array[Node3D] = []
	for monster in _monsters_inside:
		if is_instance_valid(monster):
			alive.append(monster)
	_monsters_inside = alive


## Le joueur peut-il actionner CETTE porte maintenant ? (proche, visible, la
## plus proche s'il y en a plusieurs, pas cache.)
func _is_interaction_target(player: Node3D) -> bool:
	if player.has_method("is_hidden") and bool(player.is_hidden()):
		return false
	if player.get("_nearby_hiding_spot") != null:
		return false # une cachette a la priorite
	var center: Vector3 = get_center_position()
	var to_door: Vector3 = center - player.global_position
	to_door.y = 0.0
	var distance: float = to_door.length()
	if distance > INTERACT_DISTANCE + _width * 0.5:
		return false
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	if distance > 0.9 and forward.normalized().dot(to_door.normalized()) < FACING_DOT:
		return false
	for other: Node in get_tree().get_nodes_in_group("doors"):
		if other != self and other is Door:
			var other_door := other as Door
			var other_flat: Vector3 = other_door.get_center_position() - player.global_position
			other_flat.y = 0.0
			if other_flat.length() < distance:
				return false
	return true


func _is_in_doorway(world_position: Vector3) -> bool:
	var local: Vector3 = to_local(world_position)
	return absf(local.z) < CLEAR_BAND and local.x > -0.3 and local.x < _width + 0.3


# =======================================================================
# SONS
# =======================================================================

func _play(stream: AudioStream, volume_db: float, pitch: float = 1.0) -> void:
	if stream == null or _audio == null:
		return
	_audio.stream = stream
	_audio.volume_db = volume_db
	_audio.pitch_scale = pitch * randf_range(0.95, 1.05)
	_audio.play()


static func _creak_stream_get() -> AudioStream:
	if _creak_stream == null and ResourceLoader.exists(CREAK_PATH):
		_creak_stream = load(CREAK_PATH)
	return _creak_stream


static func _slam_stream_get() -> AudioStream:
	if _slam_stream == null and ResourceLoader.exists(SLAM_PATH):
		_slam_stream = load(SLAM_PATH)
	return _slam_stream
