class_name SmilyCrawl
extends SkeletonModifier3D
## Marche à quatre pattes ajoutée par-dessus l'animation d'origine du modèle
## (qui ne fait que respirer et grimacer sur place). Les bras et les jambes
## alternent en diagonale, le torse se tord, la tête a des secousses nerveuses
## et la mâchoire s'ouvre. Les axes sont déduits du squelette lui-même
## (jambe gauche -> droite, bassin -> tête) : rien ne dépend de l'export.
## SmilyModel règle les paramètres à chaque image.

const ARM_SWING := 0.55
const LEG_SWING := 0.45
const FOREARM_BEND := 0.3
const SPINE_TWIST := 0.14
const CHASE_LEAN := 0.3
const HEAD_LOOK_UP := 0.25
const JAW_OPEN := 0.55
## Ruée de capture : il se cabre vers le joueur, bras tendus.
const LUNGE_REAR := 0.6
const LUNGE_ARMS := 0.9
const TWITCH_ANGLE := 0.4

## 0 = immobile, 1 = vitesse de référence.
var swing := 0.0
## Phase du cycle de pas (radians).
var phase := 0.0
## 0 = patrouille, 1 = poursuite.
var lean := 0.0
## 0 = au repos, 1 = ruée de capture.
var lunge := 0.0
## Ouverture supplémentaire de la mâchoire, de 0 à 1.
var jaw := 0.0
## Secousse de la tête, de -1 à 1.
var twitch := 0.0
## Sens qui tend les bras vers l'avant pendant la ruée (réglé une fois).
var arm_reach_sign := -1.0

var _bones: Dictionary[String, int] = {}
var _lateral := Vector3.RIGHT
var _forward := Vector3.FORWARD
var _up := Vector3.UP
var _axes_ready := false


func _ready() -> void:
	var skeleton := get_skeleton()
	for key in ["Arm.L", "Arm.R", "Forearm.L", "Forearm.R", "leg.L", "leg.R", "chest", "head", "jaw", "spinebase"]:
		_bones[key] = _find_bone(skeleton, key)


## Axes déduits de la pose animée (ce modèle n'a pas de pose de repos utile).
## Les os "Hip" partent tous deux du centre du bassin : on mesure la largeur
## sur les os "leg", qui partent de chaque articulation de hanche.
func _compute_axes(skeleton: Skeleton3D) -> void:
	var hip_l := skeleton.get_bone_global_pose(_bones["leg.L"]).origin
	var hip_r := skeleton.get_bone_global_pose(_bones["leg.R"]).origin
	var base := skeleton.get_bone_global_pose(_bones["spinebase"]).origin
	var head := skeleton.get_bone_global_pose(_bones["head"]).origin
	# Tant que l'animation n'a pas posé les os, ils sont tous au même point.
	if hip_l.is_equal_approx(hip_r) or head.is_equal_approx(base):
		return
	_lateral = (hip_l - hip_r).normalized()
	_up = _lateral.cross(head - base).cross(_lateral).normalized()
	_forward = _lateral.cross(_up).normalized()
	if _forward.dot(head - base) < 0.0:
		_forward = -_forward
	_axes_ready = true


## Os dont le nom commence par `prefix` ("Arm.L" trouve "Arm.L_09").
func _find_bone(skeleton: Skeleton3D, prefix: String) -> int:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).begins_with(prefix):
			return i
	push_warning("SmilyCrawl : os '%s' introuvable." % prefix)
	return -1


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _bones.values().has(-1):
		return
	if not _axes_ready:
		_compute_axes(skeleton)
		if not _axes_ready:
			return
	var step := sin(phase)
	# Torse : penché en poursuite, tordu à chaque pas, cabré pendant la ruée.
	_rotate(skeleton, "chest", _lateral, lean * CHASE_LEAN * (1.0 - lunge) - lunge * LUNGE_REAR)
	_rotate(skeleton, "chest", _up, step * SPINE_TWIST * swing)
	# Diagonales : bras gauche avec jambe droite, et inversement.
	var arm_raise := lunge * LUNGE_ARMS * arm_reach_sign
	_rotate(skeleton, "Arm.L", _lateral, step * ARM_SWING * swing + arm_raise)
	_rotate(skeleton, "Arm.R", _lateral, -step * ARM_SWING * swing + arm_raise)
	_rotate(skeleton, "Forearm.L", _lateral, maxf(step, 0.0) * FOREARM_BEND * swing)
	_rotate(skeleton, "Forearm.R", _lateral, maxf(-step, 0.0) * FOREARM_BEND * swing)
	_rotate(skeleton, "leg.L", _lateral, -step * LEG_SWING * swing)
	_rotate(skeleton, "leg.R", _lateral, step * LEG_SWING * swing)
	# Tête : relevée vers sa proie en poursuite, secousses nerveuses.
	_rotate(skeleton, "head", _lateral, -lean * HEAD_LOOK_UP)
	_rotate(skeleton, "head", _forward, twitch * TWITCH_ANGLE)
	_rotate(skeleton, "jaw", _lateral, jaw * JAW_OPEN)


## Tourne un os autour d'un axe exprimé dans l'espace du squelette, par-dessus
## la pose animée.
func _rotate(skeleton: Skeleton3D, key: String, axis: Vector3, angle: float) -> void:
	if is_zero_approx(angle):
		return
	var bone: int = _bones[key]
	var global := skeleton.get_bone_global_pose(bone)
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var rotated := Basis(axis, angle) * global.basis
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * rotated).get_rotation_quaternion())
