class_name TutorialProgress
extends RefCounted
## Mémorise si l'intro et le tutoriel ont déjà été vus (user://settings.cfg).
## Le fichier est partagé avec la langue et la luminosité : on relit avant
## d'écrire pour ne rien écraser.

const SETTINGS_PATH := "user://settings.cfg"
const INTRO_SCENE := "res://scenes/Intro.tscn"
const GAME_SCENE := "res://scenes/Main.tscn"


static func is_done() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return false
	return bool(config.get_value("progress", "tutorial_done", false))


static func mark_done() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("progress", "tutorial_done", true)
	config.save(SETTINGS_PATH)


## Première partie : intro puis tutoriel. Ensuite : directement le jeu.
static func first_scene() -> String:
	return GAME_SCENE if is_done() else INTRO_SCENE
