extends Area3D

signal monster_triggered(monster: Node3D)

@export var lifetime := 15.0

const BURST_DURATION := 0.6

var _triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body.is_in_group("monster"):
		return
	_triggered = true
	monster_triggered.emit(body)
	_spawn_burst()
	var binding := SpectralBinding.new()
	binding.duration = PowerManager.TRAP_SLOW_DURATION
	body.add_child(binding)
	queue_free()


## Éclat de lumière violette au moment où le piège se referme.
func _spawn_burst() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.35, 1.0)
	light.light_energy = 7.0
	light.omni_range = 7.0
	get_parent().add_child(light)
	light.global_position = global_position + Vector3.UP * 0.8
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, BURST_DURATION)
	tween.tween_callback(light.queue_free)
