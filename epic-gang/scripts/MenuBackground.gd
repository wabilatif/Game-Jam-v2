extends Node3D
## Couloir du menu principal : néons qui grésillent, coupures de courant,
## et une silhouette qui se rapproche à chaque retour de la lumière.

const BROKEN_TUBE := 2
const BLACKOUT_INTERVAL := Vector2(6.0, 10.0)
## Étapes d'une coupure : [durée, lumière allumée, silhouette visible].
const BLACKOUT_STEPS: Array[Array] = [
	[0.12, false, false],
	[0.07, true, false],
	[0.55, false, true],
	[1.6, true, true],
	[0.1, false, true],
	[0.05, true, true],
	[0.25, false, false],
]
const FIGURE_DEPTHS: Array[float] = [-22.0, -17.0, -12.5]
const SWAY_DEGREES := 0.35

@onready var _camera: Camera3D = $Camera3D
@onready var _figure: Node3D = $Figure
@onready var _tubes: Array[Node] = $Tubes.get_children()

var _camera_base_rotation: Vector3
var _blackout_timer := 0.0
var _step := -1
var _step_timer := 0.0
var _figure_index := 0


func _ready() -> void:
	_camera_base_rotation = _camera.rotation
	_figure.visible = false
	_blackout_timer = randf_range(BLACKOUT_INTERVAL.x, BLACKOUT_INTERVAL.y)


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_camera.rotation = _camera_base_rotation + Vector3(sin(t * 0.7), sin(t * 0.45) * 1.3, 0.0) * deg_to_rad(SWAY_DEGREES)
	if _step >= 0:
		_update_blackout(delta)
		return
	_blackout_timer -= delta
	if _blackout_timer <= 0.0:
		_figure.position.z = FIGURE_DEPTHS[_figure_index]
		_figure_index = (_figure_index + 1) % FIGURE_DEPTHS.size()
		_enter_step(0)
		return
	for i in _tubes.size():
		var chance := 0.06 if i == BROKEN_TUBE else 0.002
		_tubes[i].visible = randf() > chance


func _update_blackout(delta: float) -> void:
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	if _step + 1 < BLACKOUT_STEPS.size():
		_enter_step(_step + 1)
		return
	_step = -1
	_set_lights(true)
	_figure.visible = false
	_blackout_timer = randf_range(BLACKOUT_INTERVAL.x, BLACKOUT_INTERVAL.y)


func _enter_step(index: int) -> void:
	_step = index
	var step: Array = BLACKOUT_STEPS[index]
	_step_timer = step[0]
	_set_lights(step[1])
	_figure.visible = step[2]


func _set_lights(on: bool) -> void:
	for tube: Node3D in _tubes:
		tube.visible = on
