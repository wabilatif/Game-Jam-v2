extends Area3D
## LOST MEMORY - Secret a retrouver dans l'hopital.
## Retrouver TOUS les secrets est ce qui permet d'ouvrir la sortie.
## L'objet ne decide de rien : il signale seulement qu'il a ete ramasse,
## Main s'occupe du compteur (GameManager) et des messages.

signal secret_found(secret: Area3D)

## Identifiant du secret (0, 1, 2...), attribue par Main.
@export var secret_id: int = 0
## Fragment de memoire affiche au ramassage, attribue par Main.
@export_multiline var note: String = ""
@export var spin_speed: float = 1.2
@export var bob_height: float = 0.06
@export var bob_speed: float = 2.0

@onready var _visual: Node3D = $Visual

var _collected: bool = false
var _time: float = 0.0
var _base_y: float = 1.0


func _ready() -> void:
	add_to_group("secrets")
	_base_y = _visual.position.y
	_time = randf() * TAU # les secrets ne ondulent pas tous en phase
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_visual.rotate_y(spin_speed * delta)
	_visual.position.y = _base_y + sin(_time * bob_speed) * bob_height


func is_collected() -> bool:
	return _collected


func collect() -> void:
	if _collected:
		return
	_collected = true
	set_deferred("monitoring", false)
	visible = false
	secret_found.emit(self)
	queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		collect()
