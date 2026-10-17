extends Node3D
## Tutoriel jouable (première partie uniquement) : une aile de l'hôpital où
## chaque étape apprend une commande. Il utilise les vrais Player, Monster,
## PowerPickup et le vrai formulaire : ce qu'on apprend ici marche pareil en
## jeu. À la fin (ou si on le passe), tout est remis à zéro avant la partie.

const GAME_SCENE := "res://scenes/Main.tscn"
const FADE_DURATION := 1.0
const FINAL_CARD_DURATION := 2.5
const LOOK_ANGLE := 1.6
const SPRINT_TIME := 1.2
const MARKER_RADIUS := 1.3

const FAILURE_MESSAGES: Dictionary = {
	"locked": "Ce pouvoir ne t'appartient pas encore.",
	"cooldown": "Pas encore... (%d s)",
	"out_of_range": "Trop loin : approche-toi du monstre.",
	"no_target": "Il n'y a rien ici.",
}

## Étapes : titre, consigne, touches à afficher. Une touche est soit un texte
## ("Souris"), soit une touche physique : on affiche alors la lettre du clavier
## du joueur (Z sur AZERTY, W sur QWERTY).
const STEPS: Array[Dictionary] = [
	{"title": "Regarder", "text": "Bouge la souris pour regarder autour de toi.", "keys": ["Souris"]},
	{"title": "Se déplacer", "text": "Avance jusqu'à la marque lumineuse au sol.", "keys": [KEY_W, KEY_A, KEY_S, KEY_D]},
	{"title": "Courir", "text": "Maintiens Maj en avançant pour courir. Ton souffle s'épuise vite : surveille la jauge en bas.", "keys": ["Maj"]},
	{"title": "La lampe", "text": "Éteins ta lampe, puis rallume-la. Dans l'hôpital, ce sera ta seule lumière.", "keys": [KEY_F]},
	{"title": "Se cacher", "text": "Approche-toi de l'armoire et appuie sur E pour t'y cacher. À l'intérieur, le monstre ne te voit pas.", "keys": [KEY_E]},
	{"title": "Sortir", "text": "Appuie de nouveau sur E pour sortir de l'armoire.", "keys": [KEY_E]},
	{"title": "Un pouvoir", "text": "Touche le cube lumineux et signe le formulaire. Ici, le sacrifice ne comptera pas.", "keys": []},
	{"title": "S'en servir", "text": "Le monstre est là, immobile. Approche-toi à moins de 8 m et appuie sur 1 pour l'étourdir.", "keys": [KEY_1]},
	{"title": "La sortie", "text": "Rejoins la porte verte. Dans le vrai jeu, elle ne s'ouvre qu'avec les quatre pouvoirs.", "keys": []},
]
enum Step { LOOK, MOVE, SPRINT, LIGHT, HIDE, UNHIDE, POWER, USE, EXIT, DONE }

@onready var _player: CharacterBody3D = $Player
@onready var _monster: CharacterBody3D = $Monster
@onready var _pickup: Area3D = $PowerPickup
@onready var _exit_door: Area3D = $ExitDoor
@onready var _move_marker: Node3D = $Markers/MoveMarker
@onready var _sprint_marker: Node3D = $Markers/SprintMarker
@onready var _panel: Control = %ObjectivePanel
@onready var _counter: Label = %StepCounter
@onready var _title: Label = %StepTitle
@onready var _text: Label = %StepText
@onready var _keys: HBoxContainer = %StepKeys
@onready var _final_card: Control = %FinalCard
@onready var _skip: Control = %HoldToSkip
@onready var _fade: ColorRect = %Fade

var _step := Step.LOOK
var _look_amount := 0.0
var _last_yaw := 0.0
var _last_pitch := 0.0
var _sprint_time := 0.0
var _light_was_off := false
var _finishing := false


func _ready() -> void:
	_player.add_to_group("player")
	_monster.set_target(_player)
	_monster.set_menu_paused(true)
	_last_yaw = _player.rotation.y
	_last_pitch = _player.get_node("Head").rotation.x
	_final_card.hide()
	_connect_signals()
	_show_step()
	create_tween().tween_property(_fade, "modulate:a", 0.0, FADE_DURATION)


func _connect_signals() -> void:
	var ui := get_node("/root/UIManager")
	_skip.skipped.connect(_finish)
	_player.flashlight_toggled.connect(_on_flashlight_toggled)
	_player.hidden_state_changed.connect(_on_hidden_changed)
	_pickup.power_discovered.connect(PowerManager.discover_power)
	_exit_door.player_reached_exit.connect(_on_exit_reached)
	PowerManager.sacrifice_choice_requested.connect(_on_choice_requested)
	PowerManager.sacrifice_completed.connect(_on_sacrifice_completed)
	PowerManager.power_activated.connect(_on_power_activated)
	PowerManager.power_activation_failed.connect(_on_power_failed)
	ui.sacrifice_accepted.connect(PowerManager.accept_sacrifice)
	ui.sacrifice_rejected.connect(_on_sacrifice_rejected)


## Les Autoloads survivent au changement de scène : on se débranche.
func _exit_tree() -> void:
	var ui := get_node_or_null("/root/UIManager")
	for pair: Array in [
		[PowerManager.sacrifice_choice_requested, _on_choice_requested],
		[PowerManager.sacrifice_completed, _on_sacrifice_completed],
		[PowerManager.power_activated, _on_power_activated],
		[PowerManager.power_activation_failed, _on_power_failed],
	]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
	if ui != null:
		if ui.sacrifice_accepted.is_connected(PowerManager.accept_sacrifice):
			ui.sacrifice_accepted.disconnect(PowerManager.accept_sacrifice)
		if ui.sacrifice_rejected.is_connected(_on_sacrifice_rejected):
			ui.sacrifice_rejected.disconnect(_on_sacrifice_rejected)


func _physics_process(delta: float) -> void:
	match _step:
		Step.LOOK:
			var yaw: float = _player.rotation.y
			var pitch: float = _player.get_node("Head").rotation.x
			_look_amount += absf(angle_difference(_last_yaw, yaw)) + absf(pitch - _last_pitch)
			_last_yaw = yaw
			_last_pitch = pitch
			if _look_amount >= LOOK_ANGLE:
				_advance()
		Step.MOVE:
			if _is_near(_move_marker):
				_advance()
		Step.SPRINT:
			if _player.is_sprinting():
				_sprint_time += delta
			if _sprint_time >= SPRINT_TIME:
				_advance()


func _is_near(marker: Node3D) -> bool:
	var offset: Vector3 = _player.global_position - marker.global_position
	return Vector2(offset.x, offset.z).length() <= MARKER_RADIUS


func _advance() -> void:
	_step = (_step + 1) as Step
	if _step == Step.DONE:
		_show_final_card()
		return
	_show_step()


func _show_step() -> void:
	var step: Dictionary = STEPS[_step]
	_counter.text = tr("TUTORIEL  ·  ÉTAPE %d / %d") % [_step + 1, STEPS.size()]
	_title.text = step["title"]
	_text.text = step["text"]
	for child in _keys.get_children():
		child.queue_free()
	for key: Variant in step["keys"]:
		_keys.add_child(KeyNames.cap(key))
	_move_marker.visible = _step == Step.MOVE
	_sprint_marker.visible = _step == Step.SPRINT
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.35)


func _show_final_card() -> void:
	_panel.hide()
	_final_card.show()
	_final_card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_final_card, "modulate:a", 1.0, 0.6)
	tween.tween_interval(FINAL_CARD_DURATION)
	tween.tween_callback(_finish)


## Fin ou tutoriel passé : on oublie tout ce qui a été fait ici, puis la
## vraie partie commence.
func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	TutorialProgress.mark_done()
	_player.set_controls_enabled(false)
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_DURATION)
	tween.tween_callback(_start_game)


func _start_game() -> void:
	PowerManager.reset_powers()
	for manager_call: Array in [["EffectsManager", "reset_effects"], ["AudioManager", "reset_audio"], ["UIManager", "reset_ui"]]:
		var manager := get_node_or_null("/root/" + manager_call[0])
		if manager != null and manager.has_method(manager_call[1]):
			manager.call(manager_call[1])
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_flashlight_toggled(is_on: bool) -> void:
	if _step != Step.LIGHT:
		return
	if not is_on:
		_light_was_off = true
	elif _light_was_off:
		_advance()


func _on_hidden_changed(is_hidden: bool) -> void:
	if (_step == Step.HIDE and is_hidden) or (_step == Step.UNHIDE and not is_hidden):
		_advance()


## Le formulaire passe au premier plan : l'interface du tutoriel s'efface.
func _set_tutorial_ui_visible(visible_now: bool) -> void:
	_panel.visible = visible_now and _step != Step.DONE
	_skip.visible = visible_now


func _on_choice_requested(power_id: String, sacrifices: Array[String]) -> void:
	_player.set_controls_enabled(false)
	_set_tutorial_ui_visible(false)
	get_node("/root/UIManager").show_sacrifice_menu(power_id, sacrifices)


func _on_sacrifice_completed(_power_id: String, _sacrifice_id: String) -> void:
	_player.set_controls_enabled(true)
	_set_tutorial_ui_visible(true)
	if is_instance_valid(_pickup):
		_pickup.queue_free()
	if _step == Step.POWER:
		_advance()


func _on_sacrifice_rejected() -> void:
	PowerManager.reject_sacrifice()
	_player.set_controls_enabled(true)
	_set_tutorial_ui_visible(true)
	get_node("/root/UIManager").show_message(tr("Recule, puis touche de nouveau le cube pour signer."), 4.0)


func _on_power_activated(power_id: String) -> void:
	var position: Vector3 = _player.global_position + Vector3.UP * 1.2
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_power_effect(power_id, position)
	if power_id == "shockwave":
		var effects := get_node_or_null("/root/EffectsManager")
		if effects != null:
			effects.flash_screen(Color(0.85, 0.9, 1.0, 0.45), 0.5)
		if _step == Step.USE:
			get_node("/root/UIManager").show_message(tr("Étourdi pendant 3 s. Dans le vrai jeu, profites-en pour fuir."), 3.5)
			_advance()


func _on_power_failed(power_id: String, reason: String) -> void:
	var message: String = tr(FAILURE_MESSAGES.get(reason, reason))
	if reason == "cooldown":
		message = message % ceili(PowerManager.get_cooldown_remaining(power_id))
	get_node("/root/UIManager").show_message(message, 2.5)


func _on_exit_reached() -> void:
	if _step == Step.EXIT:
		_advance()
