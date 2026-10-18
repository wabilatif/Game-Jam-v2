class_name TutorialProgress
extends RefCounted
## Mémorise si l'intro et le tutoriel ont déjà été vus (user://settings.cfg).
## Le fichier est partagé avec la langue et la luminosité : on relit avant
## d'écrire pour ne rien écraser.

const SETTINGS_PATH := "user://settings.cfg"
const INTRO_SCENE := "res://scenes/Intro.tscn"
const GAME_SCENE := "res://scenes/Main.tscn"
const TUTORIAL_SCENE := "res://scenes/Tutorial.tscn"
const MENU_SCENE := "res://scenes/MainMenu.tscn"

## Vrai quand le tutoriel est relancé volontairement depuis le menu : à la fin
## (ou si on le passe), on revient au menu au lieu de lancer la partie.
static var replay: bool = false


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


## Relancer le tutoriel depuis le menu (sans refaire l'intro).
static func replay_scene() -> String:
	replay = true
	return TUTORIAL_SCENE


## Scène qui suit le tutoriel : le menu après un replay, sinon la partie.
## Consomme le drapeau : un lancement ultérieur repart sur le flux normal.
static func scene_after_tutorial() -> String:
	var was_replay := replay
	replay = false
	return MENU_SCENE if was_replay else GAME_SCENE


## Première partie : intro puis tutoriel. Ensuite : directement le jeu.
static func first_scene() -> String:
	return GAME_SCENE if is_done() else INTRO_SCENE
