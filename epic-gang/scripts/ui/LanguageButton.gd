extends Button
## LOST MEMORY - Bouton de langue (menu principal et menu pause).
## Affiche la langue actuelle ("Langue : Français" / "Language: English") ;
## un clic bascule francais <-> anglais. Tout le jeu suit (Localization).

var _localization: Node


func _ready() -> void:
	_localization = get_node_or_null("/root/Localization")
	if _localization == null:
		visible = false
		return
	pressed.connect(_localization.toggle_language)
	mouse_entered.connect(grab_focus)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func _refresh() -> void:
	if _localization == null:
		return
	text = tr("Langue : %s") % _localization.get_language_name()
