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
	# Le HUD n'apparait que dans une scene de jeu (un joueur existe),
	# et s'efface derriere les menus plein ecran.
	_hud.visible = _is_gameplay_active() and not (_game_over or _pause_open or _sacrifice_open)


func _unhandled_input(event: InputEvent) -> void:
	if _handle_fullscreen_key(event):
		return
	if _handle_brightness_key(event):
		return
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

## F11 (ou Alt+Entree) : bascule plein ecran / fenetre, partout (menus compris).
## L'interface suit : stretch "canvas_items" + HUD et menus ancres a l'ecran.
func _handle_fullscreen_key(event: InputEvent) -> bool:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return false
	var is_f11: bool = key_event.keycode == KEY_F11
	var is_alt_enter: bool = key_event.alt_pressed \
			and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER)
	if not is_f11 and not is_alt_enter:
		return false
	toggle_fullscreen()
	get_viewport().set_input_as_handled()
	return true


## Bascule plein ecran / fenetre. Renvoie false si c'est impossible : le jeu
## lance DANS l'editeur Godot (onglet Game integre) ne peut pas passer en
## plein ecran, il faut le lancer dans sa propre fenetre.
func toggle_fullscreen() -> bool:
	if is_fullscreen_available() == false:
		if _is_gameplay_active():
			show_message(tr("Plein écran impossible : jeu intégré à l'éditeur Godot (onglet Game)."), 5.0)
		return false
	var window: Window = get_window()
	window.mode = Window.MODE_WINDOWED if is_fullscreen() else Window.MODE_FULLSCREEN
	return true


func is_fullscreen() -> bool:
	var mode: Window.Mode = get_window().mode
	return mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN


func is_fullscreen_available() -> bool:
	return not Engine.is_embedded_in_editor()


## Raccourcis de luminosite en jeu : touche "+" / "-" (pave numerique compris).
## Le reglage (et sa sauvegarde) vit dans EffectsManager.
func _handle_brightness_key(event: InputEvent) -> bool:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed:
		return false
	var direction: int = 0
	match key_event.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			direction = 1
		KEY_MINUS, KEY_KP_SUBTRACT:
			direction = -1
		_:
			return false
	var effects: Node = get_node_or_null("/root/EffectsManager")
	if effects == null or not _is_gameplay_active() or _game_over:
		return false
	effects.change_brightness(direction)
	if not _pause_open and not _sacrifice_open:
		show_message(tr("Luminosité : %d %%") % roundi(effects.get_brightness() * 100.0), 1.2)
	get_viewport().set_input_as_handled()
	return true


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
