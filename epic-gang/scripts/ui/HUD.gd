extends Control
## LOST MEMORY - Personne 5A : HUD en jeu (pouvoirs, recharge, sacrifices,
## jauge de sprint, messages, chronometre). Ne modifie jamais le gameplay.
## Pilote par UIManager (set_powers, set_sacrifices, show_message, reset).

const POWER_ORDER: Array[String] = [
	"shockwave", "spectral_vision", "speed_boost", "spectral_trap"
]
const POWER_NAMES: Dictionary = {
	"shockwave": "ONDE DE CHOC",
	"spectral_vision": "VISION SPECTRALE",
	"speed_boost": "ACCÉLÉRATION",
	"spectral_trap": "PIÈGE SPECTRAL",
}
## Notes du patient sur ce qu'il a perdu, écrites à la main.
const SACRIFICE_NAMES: Dictionary = {
	"hearing": "je n'entends plus rien",
	"leg": "ma jambe ne répond plus",
	"vision": "tout est flou",
	"stamina": "je n'arrive plus à courir",
	"arm": "mon bras ne répond plus",
	"heart": "mon cœur s'essouffle",
	"reflexes": "je n'arrive plus à bouger la tête",
	"light": "la lampe s'éteint doucement",
	"memory": "je ne retrouve plus mon chemin",
}
const POWER_NAME_WIDTH := 18
const COLOR_READY: Color = Color("cfc8b8")
const COLOR_COOLDOWN: Color = Color("6b665c")
const COLOR_EXHAUSTED: Color = Color("8e1b17")
## Secondes par caractère pour l'effet machine à écrire des messages.
const TYPE_SPEED := 0.025
## Effet de course : vitesse d'apparition, et respiration (inspirations/s)
## qui accélère quand le souffle baisse.
const SPRINT_FX_SMOOTHING := 4.0
const BREATH_RATE := Vector2(1.3, 2.6)

@onready var _sacrifice_panel: Control = %SacrificePanel
@onready var _sacrifice_text: Label = %SacrificeText
@onready var _power_panel: Control = %PowerPanel
@onready var _power_list: VBoxContainer = %PowerList
@onready var _message_label: Label = %MessageLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _secret_label: Label = %SecretLabel
@onready var _mini_map: Control = %MiniMap
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _sprint_fx: ColorRect = %SprintFX
@onready var _sprint_material: ShaderMaterial = _sprint_fx.material

var _powers: Array[String] = []
var _sacrifices: Array[String] = []
var _power_labels: Dictionary = {}
var _message_token: int = 0
var _message_tween: Tween
var _player: Node
var _sprint_intensity := 0.0
var _exhaustion := 0.0
var _breath_phase := 0.0


func _ready() -> void:
	reset()


## Changement de langue en cours de partie : on re-ecrit la liste des sacrifices.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		set_sacrifices(_sacrifices)


func _process(delta: float) -> void:
	_update_stamina()
	_update_sprint_fx(delta)
	_update_power_rows()
	_update_timer()
	_update_secrets()


# =======================================================================
# API (appelee par UIManager)
# =======================================================================

func set_powers(powers: Array[String]) -> void:
	_powers = powers.duplicate()
	for child in _power_list.get_children():
		_power_list.remove_child(child)
		child.queue_free()
	_power_labels.clear()

	# Ordre fixe = ordre des touches 1 a 4.
	for id in POWER_ORDER:
		if not _powers.has(id):
			continue
		var label := Label.new()
		label.theme_type_variation = "FieldValueLabel"
		_power_list.add_child(label)
		_power_labels[id] = label
	_power_panel.visible = not _power_labels.is_empty()
	_update_power_rows()


func set_sacrifices(sacrifices: Array[String]) -> void:
	_sacrifices = sacrifices.duplicate()
	var lines: Array[String] = []
	for id in _sacrifices:
		lines.append(tr(String(SACRIFICE_NAMES.get(id, id))))
	_sacrifice_text.text = "\n".join(lines)
	_sacrifice_panel.visible = not _sacrifices.is_empty()


func show_message(message: String, duration: float) -> void:
	_message_token += 1
	var token: int = _message_token
	if _message_tween != null:
		_message_tween.kill()
	_message_label.text = message
	_message_label.modulate.a = 1.0
	_message_label.visible_ratio = 0.0
	_message_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_message_tween.tween_property(_message_label, "visible_ratio", 1.0, message.length() * TYPE_SPEED)
	if duration <= 0.0:
		return # message persistant jusqu'au suivant
	await get_tree().create_timer(duration).timeout
	if token != _message_token:
		return
	_message_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.5)


func reset() -> void:
	_message_token += 1
	if _message_tween != null:
		_message_tween.kill()
	_message_label.text = ""
	var no_powers: Array[String] = []
	var no_sacrifices: Array[String] = []
	set_powers(no_powers)
	set_sacrifices(no_sacrifices)
	_stamina_bar.visible = false
	_timer_label.text = ""
	_secret_label.text = ""
	_mini_map.reset()
	_sprint_intensity = 0.0
	_exhaustion = 0.0
	_sprint_fx.visible = false


# =======================================================================
# PRIVE
# =======================================================================

func _update_stamina() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null or not _player.has_method("get_stamina_ratio"):
		_stamina_bar.visible = false
		return
	var ratio: float = _player.get_stamina_ratio()
	_stamina_bar.value = ratio * 100.0
	# La jauge n'apparait que lorsqu'elle n'est pas pleine.
	_stamina_bar.visible = ratio < 0.995
	var exhausted: bool = _player.has_method("is_exhausted") and _player.is_exhausted()
	_stamina_bar.modulate = COLOR_EXHAUSTED if exhausted else Color.WHITE


func _update_sprint_fx(delta: float) -> void:
	var sprinting := false
	var exhausted := false
	var ratio := 1.0
	if is_instance_valid(_player):
		sprinting = _player.has_method("is_sprinting") and _player.is_sprinting()
		exhausted = _player.has_method("is_exhausted") and _player.is_exhausted()
		if _player.has_method("get_stamina_ratio"):
			ratio = _player.get_stamina_ratio()
	var weight := minf(SPRINT_FX_SMOOTHING * delta, 1.0)
	_sprint_intensity = lerpf(_sprint_intensity, 1.0 if sprinting else 0.0, weight)
	_exhaustion = lerpf(_exhaustion, 1.0 if exhausted else 0.0, weight)
	_sprint_fx.visible = _sprint_intensity > 0.01 or _exhaustion > 0.01
	if not _sprint_fx.visible:
		return
	_breath_phase += delta * TAU * lerpf(BREATH_RATE.x, BREATH_RATE.y, 1.0 - ratio)
	_sprint_material.set_shader_parameter("intensity", _sprint_intensity)
	_sprint_material.set_shader_parameter("exhaustion", _exhaustion)
	_sprint_material.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_breath_phase))


func _update_power_rows() -> void:
	for id: String in _power_labels:
		var label: Label = _power_labels[id]
		var key: int = POWER_ORDER.find(id) + 1
		var power_name: String = (tr(String(POWER_NAMES.get(id, id))) + " ").rpad(POWER_NAME_WIDTH, ".")
		var remaining: float = _get_cooldown_remaining(id)
		if remaining > 0.0:
			label.text = "[%d] %s %4.1f s" % [key, power_name, remaining]
			label.modulate = COLOR_COOLDOWN
		elif remaining < 0.0:
			label.text = "[%d] %s ..." % [key, power_name]
			label.modulate = COLOR_COOLDOWN
		else:
			label.text = "[%d] %s %s" % [key, power_name, tr("prêt")]
			label.modulate = COLOR_READY


## > 0 : secondes restantes ; 0 : pret ; -1 : en recharge, duree inconnue
## (PowerManager n'expose que is_power_on_cooldown).
func _get_cooldown_remaining(power_id: String) -> float:
	var power_manager: Node = get_node_or_null("/root/PowerManager")
	if power_manager == null:
		return 0.0
	if power_manager.has_method("get_cooldown_remaining"):
		return float(power_manager.get_cooldown_remaining(power_id))
	if power_manager.has_method("is_power_on_cooldown") \
			and power_manager.is_power_on_cooldown(power_id):
		return -1.0
	return 0.0


func _update_timer() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager == null or not game_manager.has_method("get_game_time"):
		_timer_label.text = ""
		return
	var total: int = int(game_manager.get_game_time())
	_timer_label.text = "%02d:%02d" % [floori(total / 60.0), total % 60]


## Compteur de secrets : "SECRETS 2/5".
func _update_secrets() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager == null or not game_manager.has_method("get_secret_total"):
		_secret_label.text = ""
		return
	var total: int = game_manager.get_secret_total()
	if total <= 0:
		_secret_label.text = ""
		return
	_secret_label.text = "SECRETS %d/%d" % [game_manager.get_secrets_found(), total]
