class_name HidingSpot
extends Node3D
## LOST MEMORY - Armoire / Cachette pour échapper au monstre.
## Permet au joueur d'entrer pour se dissimuler.
## Lorsque le joueur est caché, le monstre ne peut plus le voir ni l'attaquer,
## et s'éloigne activement de lui.

signal player_entered_hiding(spot: HidingSpot)
signal player_exited_hiding(spot: HidingSpot)

@export var prompt_hide: String = "[E] Se cacher"
@export var prompt_exit: String = "[E] Sortir"

@onready var interaction_area: Area3D = $InteractionArea
@onready var hiding_point: Marker3D = $HidingPoint
@onready var exit_point: Marker3D = $ExitPoint
@onready var prompt_label: Label3D = $PromptLabel

var _occupant: CharacterBody3D = null
var _player_nearby: CharacterBody3D = null


func _ready() -> void:
	add_to_group("hiding_spots")
	if prompt_label != null:
		prompt_label.text = prompt_hide
		prompt_label.visible = false
	if interaction_area != null:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)


func is_occupied() -> bool:
	return _occupant != null


func get_occupant() -> CharacterBody3D:
	return _occupant


func get_hiding_position() -> Vector3:
	if hiding_point != null:
		return hiding_point.global_position
	return global_position


func get_hiding_rotation() -> Vector3:
	if hiding_point != null:
		return hiding_point.global_rotation
	return global_rotation


func get_exit_position() -> Vector3:
	if exit_point != null:
		return exit_point.global_position
	return global_position + global_transform.basis.z * 1.0


func hide_player(player: CharacterBody3D) -> bool:
	if is_occupied() or player == null:
		return false
	_occupant = player
	_update_prompt()
	player_entered_hiding.emit(self)
	return true


func release_player(player: CharacterBody3D) -> void:
	if _occupant == player:
		_occupant = null
		_update_prompt()
		player_exited_hiding.emit(self)


func _update_prompt() -> void:
	if prompt_label == null:
		return
	if _occupant != null:
		prompt_label.text = prompt_exit
		prompt_label.visible = true
	elif _player_nearby != null and is_instance_valid(_player_nearby):
		prompt_label.text = prompt_hide
		prompt_label.visible = true
	else:
		prompt_label.visible = false


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body is CharacterBody3D:
		_player_nearby = body as CharacterBody3D
		if body.has_method("set_nearby_hiding_spot"):
			body.set_nearby_hiding_spot(self)
		_update_prompt()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_nearby:
		if body.has_method("clear_nearby_hiding_spot"):
			body.clear_nearby_hiding_spot(self)
		_player_nearby = null
		_update_prompt()

