extends Node
## AudioManager — Personne 6 (Lost Memory)
## A enregistrer en Autoload : Projet > Paramètres du projet > Autoload > nom "AudioManager".
## (EffectsManager.gd doit aussi être en Autoload, sous le nom "EffectsManager".)
##
## Convention de fichiers (nom de fichier = identifiant du contrat) :
##   res://audio/sfx/monster_detected.ogg (ou .mp3 / .wav)
##   res://audio/sfx/monster_attack.ogg
##   res://audio/sfx/power_found.ogg
##   res://audio/sfx/sacrifice.ogg
##   res://audio/sfx/shockwave.ogg
##   res://audio/sfx/door_open.ogg
##   res://audio/sfx/footstep.ogg           (optionnel : bruits de pas)
##   res://audio/ambient/<ambient_id>.ogg   (ex : scary_ambience.ogg)
##   res://audio/sfx/monster_loop.ogg       (optionnel : son continu du monstre)
##
## Si un fichier est absent, un warning est affiché mais le jeu ne plante pas.

const SFX_DIR := "res://audio/sfx/"
const AMBIENT_DIR := "res://audio/ambient/"
const EXTENSIONS := ["ogg", "mp3", "wav"]
const SFX_POOL_SIZE := 8
const MONSTER_LOOP_ID := "monster_loop"

var _sfx_players: Array[AudioStreamPlayer] = []
var _ambient_player: AudioStreamPlayer
var _monster_player: AudioStreamPlayer
var _stream_cache: Dictionary = {}
var _lowpass_index := -1


func _ready() -> void:
	_setup_players()
	_setup_hearing_filter()


# ---------------------------------------------------------------------------
# API PUBLIQUE (contrat)
# ---------------------------------------------------------------------------

## Joue un effet sonore court (ex : "monster_detected").
func play_sfx(sound_id: String) -> void:
	var stream := _load_stream(SFX_DIR, sound_id)
	if stream == null:
		return
	var player := _get_free_sfx_player()
	player.stream = stream
	player.play()


## Joue une ambiance en boucle. Remplace l'ambiance en cours.
func play_ambient_sound(sound_id: String) -> void:
	var stream := _load_stream(AMBIENT_DIR, sound_id)
	if stream == null:
		return
	stream = stream.duplicate() as AudioStream
	stream.set("loop", true)
	_ambient_player.stream = stream
	_ambient_player.play()


func stop_ambient_sound() -> void:
	_ambient_player.stop()


## Perte d'ouïe : filtre passe-bas sur le bus Master.
func set_hearing_effect(deafened: bool) -> void:
	if _lowpass_index >= 0:
		AudioServer.set_bus_effect_enabled(0, _lowpass_index, deafened)


## Perte de vue : délègue à EffectsManager (gardé ici pour respecter le contrat).
func set_vision_effect(impaired: bool) -> void:
	EffectsManager.set_vision_effect(impaired)


## Effet de transition d'un sacrifice (son + flash).
## sacrifice_id : "hearing", "leg", "vision", "stamina", "arm", "heart", "reflexes", "light", "memory"
func play_sacrifice_effect(sacrifice_id: String) -> void:
	play_sfx("sacrifice")
	match sacrifice_id:
		"hearing":
			EffectsManager.flash_screen(Color(1, 1, 1, 0.6), 0.4)
		"vision":
			EffectsManager.flash_screen(Color(0, 0, 0, 1.0), 0.8)
		"leg", "stamina", "arm", "heart":
			pass # le battement rouge du HUD (SacrificeMoment) s'en charge
		"light":
			EffectsManager.flash_screen(Color(0, 0, 0, 0.9), 0.5)
		_:
			EffectsManager.flash_screen(Color(1, 1, 1, 0.4), 0.3)


## Effet d'un pouvoir à une position 3D.
## power_id : "shockwave", "spectral_vision", "speed_boost", "spectral_trap"
func play_power_effect(power_id: String, position: Vector3) -> void:
	if power_id == "shockwave":
		play_sfx("shockwave")
	EffectsManager.spawn_power_light(position, _power_color(power_id))


## intensity entre 0.0 (silence) et 1.0 (plein volume). Appelé par le monstre.
func set_monster_audio_intensity(intensity: float) -> void:
	intensity = clampf(intensity, 0.0, 1.0)
	if intensity <= 0.01:
		_monster_player.stop()
		return
	if not _monster_player.playing:
		var stream := _load_stream(SFX_DIR, MONSTER_LOOP_ID)
		if stream == null:
			return
		stream = stream.duplicate() as AudioStream
		stream.set("loop", true)
		_monster_player.stream = stream
		_monster_player.play()
	_monster_player.volume_db = linear_to_db(intensity)


## A appeler par Main à la relance de partie (le joueur ne le fait pas).
func reset_audio() -> void:
	set_hearing_effect(false)
	stop_ambient_sound()
	_monster_player.stop()
	for p in _sfx_players:
		p.stop()


# ---------------------------------------------------------------------------
# PRIVE
# ---------------------------------------------------------------------------

func _setup_players() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	_ambient_player = AudioStreamPlayer.new()
	add_child(_ambient_player)
	_monster_player = AudioStreamPlayer.new()
	add_child(_monster_player)


func _setup_hearing_filter() -> void:
	var fx := AudioEffectLowPassFilter.new()
	fx.cutoff_hz = 800.0
	AudioServer.add_bus_effect(0, fx)
	_lowpass_index = AudioServer.get_bus_effect_count(0) - 1
	AudioServer.set_bus_effect_enabled(0, _lowpass_index, false)


func _load_stream(dir: String, id: String) -> AudioStream:
	var key := dir + id
	if _stream_cache.has(key):
		return _stream_cache[key]
	for ext in EXTENSIONS:
		var path := "%s%s.%s" % [dir, id, ext]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			_stream_cache[key] = stream
			return stream
	push_warning("AudioManager : son introuvable '%s' dans %s" % [id, dir])
	return null


func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0] # tous occupés : on réutilise le premier


func _power_color(power_id: String) -> Color:
	match power_id:
		"shockwave":
			return Color(1.0, 0.9, 0.5)
		"spectral_vision":
			return Color(0.4, 0.8, 1.0)
		"speed_boost":
			return Color(0.5, 1.0, 0.5)
		"spectral_trap":
			return Color(0.7, 0.4, 1.0)
		_:
			return Color.WHITE
