extends SceneTree

const HOSPITAL_PATH: String = "res://scenes/Hospital.tscn"
const OUTPUT_DIR: String = "res://assets/navigation"
const OUTPUT_PATH: String = "res://assets/navigation/hospital_navmesh.tres"


func _initialize() -> void:
	await process_frame
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var hospital: Node3D = (load(HOSPITAL_PATH) as PackedScene).instantiate() as Node3D
	holder.add_child(hospital)
	await process_frame
	await process_frame
	var navmesh: NavigationMesh = _create_navmesh()
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, hospital)
	if not source.has_data():
		push_error("bake_navmesh: aucune geometrie trouvee dans l'hopital.")
		quit(1)
		return
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var error: int = ResourceSaver.save(navmesh, OUTPUT_PATH)
	print("bake_navmesh: %d polygones, sauvegarde code %d" % [navmesh.get_polygon_count(), error])
	quit(error)


func _create_navmesh() -> NavigationMesh:
	var navmesh: NavigationMesh = NavigationMesh.new()
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 2.0
	navmesh.agent_max_climb = 0.25
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	return navmesh
