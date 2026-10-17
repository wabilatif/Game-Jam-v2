extends Node3D
## AudioTest — scène de test de la Personne 6.
## Place ce fichier dans res://tests/ avec AudioTest.tscn, puis lance la scène avec F6.
## Prérequis : AudioManager et EffectsManager déclarés en Autoload.
## Cette scène ne sert qu'à toi : ne l'intègre pas au jeu final.

const REQUIRED_SFX := ["monster_detected", "monster_attack", "power_found", "sacrifice", "shockwave", "door_open"]
const OPTIONAL_SFX := ["footstep", "monster_loop"]
const EXTENSIONS := ["ogg", "mp3", "wav"]

@export var ambient_id := "scary_ambience"

var _hearing_on := false
var _vision_on := false
var _monster_levels := [0.0, 0.3, 0.7, 1.0]
var _monster_step := 0
var _label: Label


func _ready() -> void:
	_build_scene()
	_build_help()
	_report_files()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1: AudioManager.play_sfx("monster_detected")
		KEY_2: AudioManager.play_sfx("monster_attack")
		KEY_3: AudioManager.play_sfx("power_found")
		KEY_4: AudioManager.play_sfx("sacrifice")
		KEY_5: AudioManager.play_sfx("shockwave")
		KEY_6: AudioManager.play_sfx("door_open")
		KEY_7: AudioManager.play_sfx("footstep")
		KEY_A: AudioManager.play_ambient_sound(ambient_id)
		KEY_X: AudioManager.stop_ambient_sound()
		KEY_H:
			_hearing_on = not _hearing_on
			AudioManager.set_hearing_effect(_hearing_on)
		KEY_V:
			_vision_on = not _vision_on
			EffectsManager.set_vision_effect(_vision_on)
		KEY_F1: AudioManager.play_sacrifice_effect("hearing")
		KEY_F2: AudioManager.play_sacrifice_effect("leg")
		KEY_F3: AudioManager.play_sacrifice_effect("vision")
		KEY_F4: AudioManager.play_sacrifice_effect("stamina")
		KEY_F5: AudioManager.play_power_effect("shockwave", Vector3.ZERO)
		KEY_F6: AudioManager.play_power_effect("spectral_vision", Vector3.ZERO)
		KEY_F7: AudioManager.play_power_effect("speed_boost", Vector3.ZERO)
		KEY_F8: AudioManager.play_power_effect("spectral_trap", Vector3.ZERO)
		KEY_M:
			_monster_step = (_monster_step + 1) % _monster_levels.size()
			AudioManager.set_monster_audio_intensity(_monster_levels[_monster_step])
			_label.text = _help_text() + "\nIntensité monstre : %.1f" % _monster_levels[_monster_step]
		KEY_R:
			_hearing_on = false
			_vision_on = false
			AudioManager.reset_audio()
			EffectsManager.reset_effects()


func _help_text() -> String:
	return """TEST AUDIO / EFFETS (Personne 6)
1 monster_detected   2 monster_attack   3 power_found
4 sacrifice   5 shockwave   6 door_open   7 footstep
A ambiance   X stop ambiance   M intensité monstre (cycle)
H ouïe on/off   V vue on/off   R reset
F1-F4 effets sacrifice (hearing, leg, vision, stamina)
F5-F8 effets pouvoir (shockwave, spectral_vision, speed_boost, spectral_trap)"""


func _build_help() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.text = _help_text()
	layer.add_child(_label)


func _build_scene() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2, 5)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(12, 0.2, 12)
	add_child(floor_box)
	floor_box.position = Vector3(0, -0.1, 0)


func _report_files() -> void:
	print("=== Vérification des sons ===")
	var missing := 0
	for id in REQUIRED_SFX:
		if not _exists("res://audio/sfx/", id):
			push_warning("MANQUANT (obligatoire) : audio/sfx/%s" % id)
			missing += 1
	for id in OPTIONAL_SFX:
		if not _exists("res://audio/sfx/", id):
			print("Absent (optionnel) : audio/sfx/%s" % id)
	if not _exists("res://audio/ambient/", ambient_id):
		push_warning("MANQUANT : audio/ambient/%s" % ambient_id)
		missing += 1
	print("Sons obligatoires manquants : %d" % missing)


func _exists(dir: String, id: String) -> bool:
	for ext in EXTENSIONS:
		if ResourceLoader.exists("%s%s.%s" % [dir, id, ext]):
			return true
	return false
