extends Button
## LOST MEMORY - Bouton plein ecran (menu principal et menu pause).
## Meme action que F11 / Alt+Entree. Si le jeu est lance dans l'ecran integre
## de l'editeur Godot, le plein ecran est impossible : le bouton l'indique.

var _ui: Node


func _ready() -> void:
	_ui = get_node_or_null("/root/UIManager")
	if _ui == null:
		visible = false
		return
	pressed.connect(_on_pressed)
	mouse_entered.connect(grab_focus)
	get_window().size_changed.connect(_refresh)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func _on_pressed() -> void:
	_ui.toggle_fullscreen()
	_refresh()


func _refresh() -> void:
	if _ui == null:
		return
	if not _ui.is_fullscreen_available():
		text = tr("Plein écran : indisponible (jeu intégré à l'éditeur)")
	elif _ui.is_fullscreen():
		text = tr("Plein écran : activé")
	else:
		text = tr("Plein écran : désactivé")
