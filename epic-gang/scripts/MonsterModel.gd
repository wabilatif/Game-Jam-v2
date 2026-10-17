extends Node3D

const STEP_RATE: float = 2.2
const LEG_SWING: float = 0.7
const ARM_SWING: float = 0.45
const MAX_SWING: float = 1.2
const SPEED_REFERENCE: float = 2.5
const CHASE_ARM_ANGLE: float = 1.1
const BASE_LEAN: float = -0.3
const CHASE_LEAN: float = -0.55
const IDLE_SWAY: float = 0.03
const HEAD_SWAY: float = 0.08
const BLEND_SPEED: float = 8.0

@onready var _leg_left: Node3D = $LegL
@onready var _leg_right: Node3D = $LegR
@onready var _upper: Node3D = $Upper
@onready var _arm_left: Node3D = $Upper/ArmL
@onready var _arm_right: Node3D = $Upper/ArmR
@onready var _head: Node3D = $Upper/Head

var _body: CharacterBody3D = null
var _phase: float = 0.0
var _time: float = 0.0
var _swing: float = 0.0
var _lean: float = BASE_LEAN
var _arm_angle: float = 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D


func _process(delta: float) -> void:
	if _body == null:
		return
	_time += delta
	var flat_speed: float = Vector2(_body.velocity.x, _body.velocity.z).length()
	var blend: float = clampf(BLEND_SPEED * delta, 0.0, 1.0)
	_swing = lerpf(_swing, clampf(flat_speed / SPEED_REFERENCE, 0.0, MAX_SWING), blend)
	_phase += flat_speed * STEP_RATE * delta
	_update_stance(blend)
	_animate_limbs()
	_animate_idle()


func _update_stance(blend: float) -> void:
	var target_lean: float = BASE_LEAN
	var target_arm: float = 0.0
	if _is_chasing():
		target_lean = CHASE_LEAN
		target_arm = CHASE_ARM_ANGLE
	_lean = lerpf(_lean, target_lean, blend)
	_arm_angle = lerpf(_arm_angle, target_arm, blend)


func _is_chasing() -> bool:
	if not _body.has_method("is_chasing_player"):
		return false
	return _body.is_chasing_player()


func _animate_limbs() -> void:
	var step: float = sin(_phase)
	_leg_left.rotation.x = step * LEG_SWING * _swing
	_leg_right.rotation.x = -step * LEG_SWING * _swing
	_arm_left.rotation.x = _arm_angle - step * ARM_SWING * _swing
	_arm_right.rotation.x = _arm_angle + step * ARM_SWING * _swing


func _animate_idle() -> void:
	_upper.rotation.x = _lean
	_upper.rotation.z = sin(_time * 1.3) * IDLE_SWAY
	_head.rotation.z = sin(_time * 0.9) * HEAD_SWAY
	_head.rotation.x = sin(_time * 0.7) * HEAD_SWAY
