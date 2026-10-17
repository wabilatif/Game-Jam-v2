extends Node
## LOST MEMORY - Autoload Localization : langue du jeu (francais / anglais).
##
## Le jeu est ecrit en francais ; l'anglais vient de TranslationsEN.gd (le
## texte francais sert de cle). Les nodes de l'interface se traduisent tout
## seuls au changement de langue ; dans le code, utiliser tr("texte francais").
## La langue choisie est memorisee dans user://settings.cfg.
##
##   Localization.set_language("en")   /  Localization.toggle_language()
##   Localization.get_language()       ->  "fr" | "en"

signal language_changed(code: String)

const TranslationsEN := preload("res://scripts/TranslationsEN.gd")

const LANGUAGES: Array[String] = ["fr", "en"]
const LANGUAGE_NAMES: Dictionary = {"fr": "Français", "en": "English"}
const DEFAULT_LANGUAGE: String = "fr"
const SETTINGS_PATH: String = "user://settings.cfg"

var _language: String = DEFAULT_LANGUAGE


func _ready() -> void:
	var english := Translation.new()
	english.locale = "en"
	for source: String in TranslationsEN.TABLE:
		english.add_message(source, String(TranslationsEN.TABLE[source]))
	TranslationServer.add_translation(english)
	_language = _load_language()
	TranslationServer.set_locale(_language)


func get_language() -> String:
	return _language


func get_language_name(code: String = "") -> String:
	return String(LANGUAGE_NAMES.get(code if code != "" else _language, _language))


func set_language(code: String) -> void:
	if not LANGUAGES.has(code) or code == _language:
		return
	_language = code
	TranslationServer.set_locale(code)
	_save_language()
	language_changed.emit(code)


func toggle_language() -> void:
	var next: int = (LANGUAGES.find(_language) + 1) % LANGUAGES.size()
	set_language(LANGUAGES[next])


func _load_language() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return DEFAULT_LANGUAGE
	var saved: String = String(config.get_value("game", "language", DEFAULT_LANGUAGE))
	return saved if LANGUAGES.has(saved) else DEFAULT_LANGUAGE


func _save_language() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH) # conserve les autres reglages (luminosite...)
	config.set_value("game", "language", _language)
	config.save(SETTINGS_PATH)
