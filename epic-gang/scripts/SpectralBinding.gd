class_name SpectralBinding
extends Node3D
## Anneaux spectraux qui enserrent le monstre pris dans le piège, le temps de
## son ralentissement. Se retirent en fondu puis se libèrent.

const COLOR := Color(0.6, 0.35, 1.0)
const RING_HEIGHTS: Array[float] = [0.35, 0.95, 1.55]
const RING_RADIUS := 0.75
const SPIN_SPEED := 1.6
const FADE_TIME := 0.5

var duration := 5.0
var _rings: Array[MeshInstance3D] = []
var _material: StandardMaterial3D
var _age := 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_color = Color(COLOR, 0.9)
	for i in RING_HEIGHTS.size():
		var torus := TorusMesh.new()
		torus.inner_radius = RING_RADIUS - 0.04
		torus.outer_radius = RING_RADIUS
		torus.material = _material
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.position.y = RING_HEIGHTS[i]
		ring.rotation.z = 0.25 * (1.0 if i % 2 == 0 else -1.0)
		add_child(ring)
		_rings.append(ring)
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 1.2
	light.omni_range = 3.0
	light.position.y = 1.0
	add_child(light)


func _process(delta: float) -> void:
	_age += delta
	# Les anneaux se resserrent au début, puis tournent en sens alternés.
	var tighten := clampf(_age / 0.4, 0.0, 1.0)
	for i in _rings.size():
		var ring := _rings[i]
		ring.scale = Vector3.ONE * lerpf(1.8, 1.0, tighten)
		ring.rotate_y(SPIN_SPEED * delta * (1.0 if i % 2 == 0 else -1.0))
	var remaining := duration - _age
	_material.albedo_color.a = 0.9 * clampf(remaining / FADE_TIME, 0.0, 1.0)
	if remaining <= 0.0:
		queue_free()
