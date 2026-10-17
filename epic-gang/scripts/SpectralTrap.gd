extends Area3D

signal monster_triggered(monster: Node3D)

@export var lifetime := 15.0

var _triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body.is_in_group("monster"):
		return
	_triggered = true
	monster_triggered.emit(body)
	queue_free()
