extends Node3D
## Visuel du monstre : "Smily horror monster" (Sketchfab, CC-BY, voir README).
## Son unique animation (accroupi, rictus qui s'ouvre) tourne en boucle ; par-
## dessus, SmilyCrawl le fait avancer à quatre pattes selon sa vitesse réelle.
## En poursuite : plus rapide, penché, tête relevée. À la capture : ruée gueule
## ouverte. N'a aucun effet sur l'IA (Monster.gd).

const MODEL_SCENE: PackedScene = preload("res://assets/models/monster.glb")
const HEIGHT := 1.75
const STEP_RATE := 2.6
const SPEED_REFERENCE := 2.5
const MAX_SWING := 1.3
const BLEND_SPEED := 6.0
const IDLE_ANIM_SPEED := 1.0
const CHASE_ANIM_SPEED := 1.8
const BOB_HEIGHT := 0.06
const LUNGE_SPEED := 5.0
## Secousses de la tête : intervalle entre deux secousses (s), durée (s).
const TWITCH_INTERVAL := Vector2(1.5, 4.0)
const CHASE_TWITCH_INTERVAL := Vector2(0.4, 1.4)
const TWITCH_DURATION := 0.18

var _body: CharacterBody3D
var _visual: Node3D
var _crawl: SmilyCrawl
var _anim: AnimationPlayer
var _caught := false
var _twitch_timer := 0.0
var _twitch_left := 0.0
var _twitch_side := 1.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_visual = MODEL_SCENE.instantiate()
	_visual.name = "Smily"
	add_child(_visual)
	var skeleton: Skeleton3D = _visual.find_children("*", "Skeleton3D", true, false)[0]
	_crawl = SmilyCrawl.new()
	skeleton.add_child(_crawl)
	_anim = _visual.find_children("*", "AnimationPlayer", true, false)[0]
	var clip: String = _anim.get_animation_list()[0]
	_anim.get_animation(clip).loop_mode = Animation.LOOP_PINGPONG
	_anim.play(clip)
	_anim.seek(0.0, true)
	_fit(skeleton)
	if _body != null and _body.has_signal("monster_caught_player"):
		_body.monster_caught_player.connect(func() -> void: _caught = true)
	_twitch_timer = randf_range(TWITCH_INTERVAL.x, TWITCH_INTERVAL.y)


## Le modèle d'origine regarde vers +Z et n'est pas à l'échelle : on le tourne
## vers l'avant du monstre (-Z), on le met à HEIGHT et on pose ses pieds au sol.
func _fit(skeleton: Skeleton3D) -> void:
	_visual.rotation.y = PI
	var bounds := _pose_bounds(skeleton)
	_visual.scale = Vector3.ONE * (HEIGHT / maxf(bounds.size.y, 0.001))
	bounds = _pose_bounds(skeleton)
	_visual.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)


## Boîte englobante des os dans la pose animée (accroupie), dans le repère de
## ce nœud. La boîte des maillages n'est pas fiable sur un modèle animé.
func _pose_bounds(skeleton: Skeleton3D) -> AABB:
	var to_local := global_transform.affine_inverse() * skeleton.global_transform
	var box := AABB(to_local * skeleton.get_bone_global_pose(0).origin, Vector3.ZERO)
	for i in skeleton.get_bone_count():
		box = box.expand(to_local * skeleton.get_bone_global_pose(i).origin)
	return box


func _process(delta: float) -> void:
	if _body == null:
		return
	var blend := minf(BLEND_SPEED * delta, 1.0)
	var chasing: bool = _body.has_method("is_chasing_player") and _body.is_chasing_player()
	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	_crawl.swing = lerpf(_crawl.swing, clampf(speed / SPEED_REFERENCE, 0.0, MAX_SWING), blend)
	_crawl.phase += speed * STEP_RATE * delta
	_crawl.lean = lerpf(_crawl.lean, 1.0 if chasing else 0.0, blend)
	_crawl.jaw = lerpf(_crawl.jaw, 1.0 if (chasing or _caught) else 0.0, blend)
	_crawl.lunge = move_toward(_crawl.lunge, 1.0 if _caught else 0.0, LUNGE_SPEED * delta)
	_anim.speed_scale = lerpf(IDLE_ANIM_SPEED, CHASE_ANIM_SPEED, _crawl.lean)
	# Le corps rebondit à chaque appui.
	position.y = absf(cos(_crawl.phase)) * BOB_HEIGHT * _crawl.swing
	_update_twitch(delta, chasing)


func _update_twitch(delta: float, chasing: bool) -> void:
	if _twitch_left > 0.0:
		_twitch_left -= delta
		_crawl.twitch = _twitch_side * sin(PI * (1.0 - _twitch_left / TWITCH_DURATION))
		return
	_crawl.twitch = 0.0
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		var interval := CHASE_TWITCH_INTERVAL if chasing else TWITCH_INTERVAL
		_twitch_timer = randf_range(interval.x, interval.y)
		_twitch_left = TWITCH_DURATION
		_twitch_side = -1.0 if randf() < 0.5 else 1.0
