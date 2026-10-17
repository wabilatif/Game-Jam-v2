class_name KeyNames
extends RefCounted
## Nom affiché d'une touche. Les touches du jeu sont physiques : on montre la
## lettre réelle du clavier du joueur (Z sur AZERTY, W sur QWERTY).


static func label(key: Variant) -> String:
	if key is int:
		# Sans écran (mode console), la disposition du clavier est inconnue.
		if DisplayServer.get_name() == "headless":
			return OS.get_keycode_string(key)
		# Lettres : celle du clavier du joueur. Chiffres et autres touches : le
		# nom physique (sur AZERTY, la touche 1 porte aussi "&").
		var on_layout: Key = DisplayServer.keyboard_get_label_from_physical(key)
		if on_layout >= KEY_A and on_layout <= KEY_Z:
			return OS.get_keycode_string(on_layout)
		return OS.get_keycode_string(key)
	return TranslationServer.translate(str(key))


## Une touche dessinée comme une étiquette de dossier : [ Maj ].
static func cap(key: Variant) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "KeyCap"
	var text := Label.new()
	text.theme_type_variation = "KeyCapLabel"
	text.text = label(key)
	panel.add_child(text)
	return panel
