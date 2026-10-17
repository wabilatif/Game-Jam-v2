extends RichTextLabel
## Note manuscrite qui s'écrit progressivement à chaque apparition.

@export var delay := 0.0
@export var duration := 1.2

var _tween: Tween


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func write() -> void:
	if _tween != null:
		_tween.kill()
	visible_ratio = 0.0
	_tween = create_tween()
	_tween.tween_interval(delay)
	_tween.tween_property(self, "visible_ratio", 1.0, duration)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		write()
