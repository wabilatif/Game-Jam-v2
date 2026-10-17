extends Area3D

signal power_discovered(power_id: String)

@export var power_id: String = ""
@export var spin_speed := 1.5

@onready var _mesh: Node3D = $MeshInstance3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_mesh.rotate_y(spin_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		power_discovered.emit(power_id)
