extends Node
## LOST MEMORY - Personne 5A : Autoload UIManager.
## Seul point d'entree de l'interface pour la Personne 7 (Main / GameManager).
## L'UI affiche et transmet les choix, elle ne modifie JAMAIS le gameplay.
##
## ORDRE DES AUTOLOADS (Project Settings > Autoload) : GameManager, PowerManager,
## puis UIManager (sinon UIManager rate le signal game_started du 1er lancement).
##
## Les menus de la Personne 5B (PauseMenu, GameOverScreen) sont charges s'ils
## existent. Contrat attendu :
##   PauseMenu      : signaux resume_pressed, restart_pressed, main_menu_pressed
##   GameOverScreen : signaux restart_pressed, main_menu_pressed
##                    + func show_result(won: bool, reason: String)

signal sacrifice_accepted(power_id: String, sacrifice_id: String)
signal sacrifice_rejected
signal pause_requested
signal restart_requested
signal main_menu_requested

const HUD_SCENE: PackedScene = preload("res://scenes/ui/HUD.tscn")
const SACRIFICE_MENU_SCENE: PackedScene = preload("res://scenes/ui/SacrificeMenu.tscn")
const PAUSE_MENU_PATH: String = "res://scenes/ui/PauseMenu.tscn"
const GAME_OVER_PATH: String = "res://scenes/ui/GameOverScreen.tscn"

var _layer: CanvasLayer
var _hud: Control
var _sacrifice_menu: Control
var _pause_menu: Control
var _game_over_screen: Control

var _sacrifice_open: bool = false
var _pause_open: bool = false
var _game_over: bool = false


func _ready() -> void:
	# Les menus doivent fonctionner pendant la pause de l'arbre.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)

	_hud = HUD_SCENE.instantiate() as Control
	_layer.add_child(_hud)
	_hud.visible = false

	_sacrifice_menu = SACRIFICE_MENU_SCENE.instantiate() as Control
	_layer.add_child(_sacrifice_menu)
	_sacrifice_menu.visible = false
	_connect_once(Signal(_sacrifice_menu, "accepted"), _on_menu_accepted)
	_connect_once(Signal(_sacrifice_menu, "rejected"), _on_menu_rejected)

	_pause_menu = _load_optional_menu(PAUSE_MENU_PATH)
	if _pause_menu != null:
		_connect_menu_signal(_pause_menu, "resume_pressed", _on_resume_pressed)
		_connect_menu_signal(_pause_menu, "restart_pressed", _on_restart_pressed)
		_connect_menu_signal(_pause_menu, "main_menu_pressed", _on_main_menu_pressed)

	_game_over_screen = _load_optional_menu(GAME_OVER_PATH)
	if _game_over_screen != null:
		_connect_menu_signal(_game_over_screen, "restart_pressed", _on_restart_pressed)
		_connect_menu_signal(_game_over_screen, "main_menu_pressed", _on_main_menu_pressed)

	_connect_external_signals()
	# Nouvelle tentative : un Autoload place plus bas dans la liste n'existe
	# pas encore pendant ce _ready.
	_connect_external_signals.call_deferred()


func _process(_delta: float) -> void:
	# Le HUD n'apparait que dans une scene de jeu (un joueur existe).
	_hud.visible = _is_gameplay_active() and not _game_over


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not _is_gameplay_active() or _game_over or _sacrifice_open:
		return
	pause_requested.emit()
	get_viewport().set_input_as_handled()


# =======================================================================
# API PUBLIQUE (contrat V3)
# =======================================================================

func show_sacrifice_menu(power_id: String, sacrifices: Array[String]) -> void:
	_sacrifice_menu.call("open", power_id, sacrifices)
	_sacrifice_menu.visible = true
	_sacrifice_open = true
	_refresh_mouse_mode()


func hide_sacrifice_menu() -> void:
	_sacrifice_menu.visible = false
	_sacrifice_open = false
	_refresh_mouse_mode()


func show_message(message: String, duration: float) -> void:
	_hud.call("show_message", message, duration)


func update_power_list(powers: Array[String]) -> void:
	_hud.call("set_powers", powers)


func update_sacrifice_list(sacrifices: Array[String]) -> void:
	_hud.call("set_sacrifices", sacrifices)


func show_game_over(reason: String) -> void:
	_show_result(false, reason)


func show_victory() -> void:
	_show_result(true, "escaped")


func set_pause_menu_visible(visible: bool) -> void:
	if _pause_menu == null:
		push_warning("UIManager: PauseMenu.tscn introuvable (Personne 5B).")
		return
	_pause_menu.visible = visible
	_pause_open = visible
	_refresh_mouse_mode()


# =======================================================================
# BONUS (hors contrat)
# =======================================================================

## Remet toute l'interface a zero (listes, messages, menus). Appele
## automatiquement sur game_started / game_restarted ; Main peut aussi l'appeler.
func reset_ui() -> void:
	_game_over = false
	_sacrifice_open = false
	_pause_open = false
	_sacrifice_menu.visible = false
	if _pause_menu != null:
		_pause_menu.visible = false
	if _game_over_screen != null:
		_game_over_screen.visible = false
	_hud.call("reset")
	_refresh_mouse_mode()


# =======================================================================
# PRIVE
# =======================================================================

func _is_gameplay_active() -> bool:
	return get_tree().get_first_node_in_group("player") != null


func _show_result(won: bool, reason: String) -> void:
	_game_over = true
	_sacrifice_open = false
	_pause_open = false
	_sacrifice_menu.visible = false
	if _pause_menu != null:
		_pause_menu.visible = false
	if _game_over_screen != null and _game_over_screen.has_method("show_result"):
		_game_over_screen.call("show_result", won, reason)
		_game_over_screen.visible = true
	else:
		push_warning("UIManager: GameOverScreen.tscn introuvable (Personne 5B).")
	_refresh_mouse_mode()


## Souris visible des qu'un menu est ouvert, capturee sinon (en jeu).
func _refresh_mouse_mode() -> void:
	if _sacrifice_open or _pause_open or _game_over:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _is_gameplay_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _load_optional_menu(path: String) -> Control:
	if not ResourceLoader.exists(path):
		push_warning("UIManager: %s absent pour l'instant (Personne 5B)." % path)
		return null
	var scene: PackedScene = load(path)
	var menu := scene.instantiate() as Control
	_layer.add_child(menu)
	menu.visible = false
	return menu


func _connect_menu_signal(menu: Object, signal_name: String, callable: Callable) -> void:
	if menu.has_signal(signal_name):
		_connect_once(Signal(menu, signal_name), callable)
	else:
		push_warning("UIManager: signal '%s' manquant sur %s" % [signal_name, menu])


func _connect_once(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


func _connect_external_signals() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager != null:
		if game_manager.has_signal("game_started"):
			_connect_once(Signal(game_manager, "game_started"), _on_game_started)
		if game_manager.has_signal("game_restarted"):
			_connect_once(Signal(game_manager, "game_restarted"), _on_game_started)
	var power_manager: Node = get_node_or_null("/root/PowerManager")
	if power_manager != null and power_manager.has_signal("sacrifice_completed"):
		_connect_once(Signal(power_manager, "sacrifice_completed"), _on_sacrifice_completed)


func _refresh_lists_from_sources() -> void:
	var power_manager: Node = get_node_or_null("/root/PowerManager")
	if power_manager != null and power_manager.has_method("get_unlocked_powers"):
		var powers: Array[String] = []
		for p in power_manager.get_unlocked_powers():
			powers.append(str(p))
		update_power_list(powers)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get_applied_sacrifices"):
		var sacrifices: Array[String] = []
		for s in player.get_applied_sacrifices():
			sacrifices.append(str(s))
		update_sacrifice_list(sacrifices)


# --- Callbacks ----------------------------------------------------------

func _on_game_started() -> void:
	reset_ui()


func _on_sacrifice_completed(_power_id: String, _sacrifice_id: String) -> void:
	# Idempotent : Main fait aussi cette mise a jour selon le tableau des signaux.
	_refresh_lists_from_sources()
	hide_sacrifice_menu()


func _on_menu_accepted(power_id: String, sacrifice_id: String) -> void:
	# Le menu reste ouvert : PowerManager peut refuser. Il se ferme sur
	# sacrifice_completed (ou via hide_sacrifice_menu() appele par Main).
	sacrifice_accepted.emit(power_id, sacrifice_id)


func _on_menu_rejected() -> void:
	sacrifice_rejected.emit()
	hide_sacrifice_menu()


func _on_resume_pressed() -> void:
	pause_requested.emit() # GameManager.toggle_pause() reprend la partie


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_main_menu_pressed() -> void:
	reset_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_menu_requested.emit()
