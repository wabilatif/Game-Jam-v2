extends Control
## LOST MEMORY - Mini-map progressive (petite : haut-gauche ; grande : touche M).
## Le plan est inconnu au depart : il se devoile autour du joueur, avec une
## ligne de vue (un mur cache ce qu'il y a derriere), et reste affiche une
## fois decouvert. Vue du dessus, nord (-Z) en haut.
##
## Touche M : la carte s'affiche en grand au centre de l'ecran (comme dans les
## vrais jeux) ; en jeu elle reste petite, en haut a gauche. Le jeu continue
## pendant que la grande carte est ouverte.
##
## Sacrifice "memory" : le joueur perd sa mini-map (elle disparait pour de bon).
##
## Lit uniquement le niveau (groupe "hospital" : get_map_bounds /
## get_solid_rects / get_exit_position) et le joueur (groupe "player").
## Ne modifie jamais le gameplay.

const CELL_SIZE: float = 0.5
## Distance de vue (metres) pour devoiler le plan.
const REVEAL_RADIUS: float = 8.0
const UPDATE_INTERVAL: float = 0.1
const PADDING: float = 6.0
const LOST_SACRIFICE: String = "memory"

## Grande carte (touche M), en pixels de l'interface. Decalee vers la gauche
## pour laisser la liste des sacrifices visible en haut a droite.
const EXPANDED_SIZE: Vector2 = Vector2(560, 400)
const EXPANDED_CENTER_SHIFT: Vector2 = Vector2(-104, 14)
const EXPANDED_SCALE: float = 1.7
const TOGGLE_KEY: Key = KEY_M

const COLOR_BACKGROUND := Color(0.035, 0.035, 0.03, 0.78)
const COLOR_BORDER := Color(0.42, 0.4, 0.36, 0.9)
const COLOR_FLOOR := Color(0.27, 0.26, 0.23, 0.95)
const COLOR_WALL := Color(0.80, 0.77, 0.69, 1.0)
const COLOR_PLAYER := Color(0.97, 0.88, 0.55, 1.0)
const COLOR_EXIT := Color(0.85, 0.16, 0.12, 1.0)

var _hospital: Node
var _player: Node
var _origin: Vector2 = Vector2.ZERO
var _width: int = 0
var _height: int = 0
var _solid: PackedByteArray = PackedByteArray()
var _known: PackedByteArray = PackedByteArray()
var _known_count: int = 0
var _floor_count: int = 0
var _image: Image
var _texture: ImageTexture
var _dirty: bool = false
var _timer: float = 0.0
var _last_cell: Vector2i = Vector2i(-9999, -9999)
var _exit_position: Vector2 = Vector2(INF, INF)
var _expanded: bool = false
var _small_offsets: Array[float] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	# Position "petite carte" definie dans HUD.tscn : on la memorise.
	_small_offsets = [offset_left, offset_top, offset_right, offset_bottom]


## Oublie le plan decouvert (nouvelle partie).
func reset() -> void:
	set_expanded(false)
	_hospital = null
	_width = 0
	_height = 0
	_known_count = 0
	_last_cell = Vector2i(-9999, -9999)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != TOGGLE_KEY:
		return
	# Seulement en jeu : carte disponible et HUD affiche (pas de menu ouvert).
	if not visible or not is_visible_in_tree():
		return
	set_expanded(not _expanded)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _ensure_sources():
		visible = false
		set_expanded(false)
		return
	# Sacrifice "memory" : plus de mini-map (ni de grande carte).
	if _player.has_method("has_sacrifice") and _player.has_sacrifice(LOST_SACRIFICE):
		visible = false
		set_expanded(false)
		return
	visible = true
	# Un menu (pause, sacrifice, fin) masque le HUD : la grande carte se ferme.
	if _expanded and not is_visible_in_tree():
		set_expanded(false)
	_timer += delta
	if _timer >= UPDATE_INTERVAL:
		_timer = 0.0
		update_now()
	if _dirty:
		_texture.update(_image)
		_dirty = false
	queue_redraw()


# =======================================================================
# API (surtout pour les tests)
# =======================================================================

## Ouvre / ferme la grande carte (touche M).
func set_expanded(value: bool) -> void:
	if value == _expanded:
		return
	_expanded = value
	_apply_layout()
	queue_redraw()


func is_expanded() -> bool:
	return _expanded


## Devoile ce que le joueur voit depuis sa position actuelle.
func update_now() -> void:
	if _width == 0 or not is_instance_valid(_player):
		return
	var cell := _to_cell(_player.global_position)
	if cell == _last_cell:
		return
	_last_cell = cell
	_reveal_from(cell)


## Part (0..1) du plan (cases hors obstacles) deja decouverte.
func get_known_ratio() -> float:
	if _floor_count == 0:
		return 0.0
	return float(_known_count) / float(_floor_count)


## Vrai si la case contenant cette position globale est deja decouverte.
func is_known(world_position: Vector3) -> bool:
	if _width == 0:
		return false
	var cell := _to_cell(world_position)
	return _in_grid(cell) and _known[_index(cell)] == 1


# =======================================================================
# PRIVE : initialisation
# =======================================================================

func _apply_layout() -> void:
	if _small_offsets.is_empty():
		return
	if _expanded:
		# Ancree au centre de l'ecran : suit le redimensionnement / plein ecran.
		set_anchors_preset(Control.PRESET_CENTER, false)
		var half := EXPANDED_SIZE * 0.5
		offset_left = -half.x + EXPANDED_CENTER_SHIFT.x
		offset_top = -half.y + EXPANDED_CENTER_SHIFT.y
		offset_right = half.x + EXPANDED_CENTER_SHIFT.x
		offset_bottom = half.y + EXPANDED_CENTER_SHIFT.y
	else:
		set_anchors_preset(Control.PRESET_TOP_LEFT, false)
		offset_left = _small_offsets[0]
		offset_top = _small_offsets[1]
		offset_right = _small_offsets[2]
		offset_bottom = _small_offsets[3]


func _ensure_sources() -> bool:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var hospital: Node = get_tree().get_first_node_in_group("hospital")
	if _player == null or hospital == null:
		return false
	if hospital != _hospital:
		_hospital = hospital
		_build_map()
	return _width > 0


func _build_map() -> void:
	var bounds: Rect2 = _hospital.get_map_bounds()
	_origin = bounds.position
	_width = maxi(1, ceili(bounds.size.x / CELL_SIZE))
	_height = maxi(1, ceili(bounds.size.y / CELL_SIZE))
	_solid = PackedByteArray()
	_solid.resize(_width * _height)
	_known = PackedByteArray()
	_known.resize(_width * _height)
	_known_count = 0
	_last_cell = Vector2i(-9999, -9999)

	var rects: Array[Rect2] = _hospital.get_solid_rects()
	for rect: Rect2 in rects:
		_rasterize(rect)
	_floor_count = 0
	for value in _solid:
		if value == 0:
			_floor_count += 1

	_image = Image.create_empty(_width, _height, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	_dirty = false

	_exit_position = Vector2(INF, INF)
	if _hospital.has_method("get_exit_position"):
		var exit_3d: Vector3 = _hospital.get_exit_position()
		_exit_position = Vector2(exit_3d.x, exit_3d.z)


func _rasterize(rect: Rect2) -> void:
	# Toute case touchee par le rectangle est pleine : la mini-map ne laisse
	# jamais passer la vue a travers un mur fin.
	const EPS: float = 0.02
	var x0: int = maxi(0, floori((rect.position.x + EPS - _origin.x) / CELL_SIZE))
	var x1: int = mini(_width - 1, floori((rect.end.x - EPS - _origin.x) / CELL_SIZE))
	var y0: int = maxi(0, floori((rect.position.y + EPS - _origin.y) / CELL_SIZE))
	var y1: int = mini(_height - 1, floori((rect.end.y - EPS - _origin.y) / CELL_SIZE))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_solid[y * _width + x] = 1


# =======================================================================
# PRIVE : devoilement (lancers de rayons sur la grille)
# =======================================================================

func _reveal_from(start: Vector2i) -> void:
	if not _in_grid(start):
		return
	_mark_known(start)
	var radius_cells: int = ceili(REVEAL_RADIUS / CELL_SIZE)
	var ray_count: int = int(TAU * radius_cells * 2.0)
	for i in ray_count:
		var angle: float = TAU * float(i) / float(ray_count)
		var target := start + Vector2i(
				roundi(cos(angle) * radius_cells), roundi(sin(angle) * radius_cells))
		_cast_ray(start, target)


func _cast_ray(from: Vector2i, to: Vector2i) -> void:
	# Bresenham : on s'arrete sur le premier mur rencontre (qui, lui, est vu).
	var dx: int = absi(to.x - from.x)
	var dy: int = absi(to.y - from.y)
	var sx: int = 1 if from.x < to.x else -1
	var sy: int = 1 if from.y < to.y else -1
	var err: int = dx - dy
	var x: int = from.x
	var y: int = from.y
	while x != to.x or y != to.y:
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		var cell := Vector2i(x, y)
		if not _in_grid(cell):
			return
		_mark_known(cell)
		if _solid[_index(cell)] == 1:
			return


func _mark_known(cell: Vector2i) -> void:
	var index: int = _index(cell)
	if _known[index] == 1:
		return
	_known[index] = 1
	if _solid[index] == 0:
		_known_count += 1
	_image.set_pixel(cell.x, cell.y, COLOR_WALL if _solid[index] == 1 else COLOR_FLOOR)
	_dirty = true


func _to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(
			floori((world_position.x - _origin.x) / CELL_SIZE),
			floori((world_position.z - _origin.y) / CELL_SIZE))


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _height


func _index(cell: Vector2i) -> int:
	return cell.y * _width + cell.x


# =======================================================================
# PRIVE : dessin
# =======================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if _width == 0 or _texture == null:
		return
	var top_pad: float = 34.0 if _expanded else PADDING
	var bottom_pad: float = 30.0 if _expanded else PADDING
	var inner := Rect2(Vector2(PADDING, top_pad), size - Vector2(PADDING * 2.0, top_pad + bottom_pad))
	var pixel_scale: float = minf(inner.size.x / _width, inner.size.y / _height)
	var map_size := Vector2(_width, _height) * pixel_scale
	var map_origin: Vector2 = inner.position + (inner.size - map_size) * 0.5
	draw_texture_rect(_texture, Rect2(map_origin, map_size), false)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 2.0 if _expanded else 1.0)
	var marker_scale: float = EXPANDED_SCALE if _expanded else 1.0

	# Sortie : visible seulement une fois sa zone decouverte.
	if _exit_position.is_finite() and _is_exit_known():
		var exit_px: Vector2 = _world_to_pixel(_exit_position, map_origin, pixel_scale)
		var r: float = 5.0 * marker_scale
		draw_colored_polygon(PackedVector2Array([
				exit_px + Vector2(0, -r), exit_px + Vector2(r, 0),
				exit_px + Vector2(0, r), exit_px + Vector2(-r, 0)]), COLOR_EXIT)

	# Joueur : fleche orientee comme le regard.
	if is_instance_valid(_player):
		var pos := Vector2(_player.global_position.x, _player.global_position.z)
		var player_px: Vector2 = _world_to_pixel(pos, map_origin, pixel_scale)
		var forward3: Vector3 = -_player.global_transform.basis.z
		var forward := Vector2(forward3.x, forward3.z).normalized()
		var side := Vector2(-forward.y, forward.x)
		draw_colored_polygon(PackedVector2Array([
				player_px + forward * 6.0 * marker_scale,
				player_px - forward * 4.0 * marker_scale + side * 4.0 * marker_scale,
				player_px - forward * 2.0 * marker_scale,
				player_px - forward * 4.0 * marker_scale - side * 4.0 * marker_scale]), COLOR_PLAYER)
	if _expanded:
		_draw_legend()


func _draw_legend() -> void:
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var font_size: int = 14
	draw_string(font, Vector2(14, 24), tr("PLAN DE L'HÔPITAL"), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 2, COLOR_WALL)
	draw_string(font, Vector2(14, size.y - 12), tr("[M] fermer"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_BORDER)
	# Legende : joueur / sortie
	var legend_x: float = size.x - 150.0
	draw_colored_polygon(PackedVector2Array([
			Vector2(legend_x, size.y - 22), Vector2(legend_x - 4, size.y - 12),
			Vector2(legend_x, size.y - 15), Vector2(legend_x + 4, size.y - 12)]), COLOR_PLAYER)
	draw_string(font, Vector2(legend_x + 10, size.y - 12), tr("vous"), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_WALL)
	draw_colored_polygon(PackedVector2Array([
			Vector2(legend_x + 62, size.y - 22), Vector2(legend_x + 67, size.y - 16),
			Vector2(legend_x + 62, size.y - 10), Vector2(legend_x + 57, size.y - 16)]), COLOR_EXIT)
	draw_string(font, Vector2(legend_x + 74, size.y - 12), tr("sortie"), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_WALL)


func _world_to_pixel(world_xz: Vector2, map_origin: Vector2, pixel_scale: float) -> Vector2:
	return map_origin + (world_xz - _origin) / CELL_SIZE * pixel_scale


func _is_exit_known() -> bool:
	var cell := _to_cell(Vector3(_exit_position.x, 0.0, _exit_position.y))
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var neighbour := cell + Vector2i(dx, dy)
			if _in_grid(neighbour) and _known[_index(neighbour)] == 1:
				return true
	return false
