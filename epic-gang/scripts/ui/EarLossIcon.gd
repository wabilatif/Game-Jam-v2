class_name EarLossIcon
extends Control
## Oreille barrée : rappelle en permanence que l'ouïe a été sacrifiée.

const INK := Color("cfc8b8")
const SLASH := Color("b8352d")
const ICON_SIZE := Vector2(46, 54)


func _init() -> void:
	custom_minimum_size = ICON_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := ICON_SIZE / 2.0
	var k := ICON_SIZE.x / 34.0
	# Pavillon de l'oreille, puis le creux intérieur.
	draw_arc(c + Vector2(1, -3) * k, 12.0 * k, PI * 0.95, PI * 2.6, 24, INK, 3.0, true)
	draw_line(c + Vector2(-4, 8) * k, c + Vector2(-1, 16) * k, INK, 3.0, true)
	draw_arc(c + Vector2(2, -3) * k, 5.5 * k, PI * 1.1, PI * 2.4, 16, INK, 2.5, true)
	# Barre rouge.
	draw_line(Vector2(4, ICON_SIZE.y - 5), Vector2(ICON_SIZE.x - 4, 5), SLASH, 4.5, true)
