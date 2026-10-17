extends Control
## LOST MEMORY - Personne 5A : HUD en jeu (pouvoirs, recharge, sacrifices,
## jauge de sprint, messages, chronometre). Ne modifie jamais le gameplay.
## Pilote par UIManager (set_powers, set_sacrifices, show_message, reset).

const POWER_ORDER: Array[String] = [
	"shockwave", "spectral_vision", "speed_boost", "spectral_trap"
]
const POWER_NAMES: Dictionary = {
	"shockwave": "Onde de choc",
	"spectral_vision": "Vision spectrale",
	"speed_boost": "Accélération",
	"spectral_trap": "Piège spectral",
}
const SACRIFICE_NAMES: Dictionary = {
	"hearing": "Ouïe perdue",
	"leg": "Jambe blessée",
	"vision": "Vue troublée",
	"stamina": "Souffle court",
}
const COLOR_READY: Color = Color(0.75, 1.0, 0.75)
const COLOR_COOLDOWN: Color = Color(0.6, 0.6, 0.6)

@onready var _sacrifice_panel: Control = %SacrificePanel
@onready var _sacrifice_text: Label = %SacrificeText
@onready var _power_panel: Control = %PowerPanel
@onready var _power_list: VBoxContainer = %PowerList
@onready var _message_label: Label = %MessageLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _stamina_bar: ProgressBar = %StaminaBar

var _powers: Array[String] = []
var _sacrifices: Array[String] = []
var _power_labels: Dictionary = {}
var _message_token: int = 0
var _message_tween: Tween
var _player: Node


func _ready() -> void:
	reset()


func _process(_delta: float) -> void:
	_update_stamina()
	_update_power_rows()
	_update_timer()


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
		label.add_theme_font_size_override("font_size", 18)
		_power_list.add_child(label)
		_power_labels[id] = label
	_power_panel.visible = not _power_labels.is_empty()
	_update_power_rows()


func set_sacrifices(sacrifices: Array[String]) -> void:
	_sacrifices = sacrifices.duplicate()
	var lines: Array[String] = []
	for id in _sacrifices:
		lines.append("- " + String(SACRIFICE_NAMES.get(id, id)))
	_sacrifice_text.text = "\n".join(lines)
	_sacrifice_panel.visible = not _sacrifices.is_empty()


func show_message(message: String, duration: float) -> void:
	_message_token += 1
	var token: int = _message_token
	if _message_tween != null:
		_message_tween.kill()
	_message_label.text = message
	_message_label.modulate.a = 1.0
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
	_stamina_bar.modulate = Color(1.0, 0.35, 0.35) if exhausted else Color.WHITE


func _update_power_rows() -> void:
	for id: String in _power_labels:
		var label: Label = _power_labels[id]
		var key: int = POWER_ORDER.find(id) + 1
		var power_name: String = POWER_NAMES.get(id, id)
		var remaining: float = _get_cooldown_remaining(id)
		if remaining > 0.0:
			label.text = "[%d] %s  %.1f s" % [key, power_name, remaining]
			label.modulate = COLOR_COOLDOWN
		elif remaining < 0.0:
			label.text = "[%d] %s  recharge..." % [key, power_name]
			label.modulate = COLOR_COOLDOWN
		else:
			label.text = "[%d] %s  PRÊT" % [key, power_name]
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
