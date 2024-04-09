extends Node
class_name TerrainGeneration

@export var noise: FastNoiseLite
@export var elevation_curve: Curve
@export_range(0.0, 1.0) var water_level: float = 0.28

@onready var rng: RandomNumberGenerator = RandomNumberGenerator.new()
@onready var water: MeshInstance3D = %Water
@onready var nav_region: NavigationRegion3D = %NavigationRegion

var mesh: MeshInstance3D
var size_depth: int = 300
var size_width: int = 300
var mesh_resolution: int = 2
var max_height: int = 70

var falloff_image: Image = null
var use_falloff: bool = false

var spawnable_objects: Array[SpawnableObject]

func _ready() -> void:
	if use_falloff:
		var falloff_texture = preload("res://procedural_generation/textures/TerrainFalloff.png")
		falloff_image = falloff_texture.get_image()

	for child in get_children():
		if child is SpawnableObject:
			spawnable_objects.append(child)

	noise.seed = randi()
	rng.seed = noise.seed

	generate()

func generate() -> void:
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(size_width, size_depth)
	plane_mesh.subdivide_depth = size_depth * mesh_resolution
	plane_mesh.subdivide_width = size_width * mesh_resolution
	plane_mesh.material = preload("res://procedural_generation/materials/TerrainMaterial.tres")

	var surface = SurfaceTool.new()
	var data = MeshDataTool.new()
	surface.create_from(plane_mesh, 0)

	var array_plane = surface.commit()
	data.create_from_surface(array_plane, 0)

	for i in range(data.get_vertex_count()):
		var vertex = data.get_vertex(i)
		var y = get_noise_y(vertex.x, vertex.z)
		vertex.y = y
		data.set_vertex(i, vertex)

	array_plane.clear_surfaces()

	data.commit_to_surface(array_plane)
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_plane, 0)
	surface.generate_normals()

	mesh = MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.create_trimesh_collision()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.add_to_group("NavSource")
	add_child(mesh)

	water.position.y = water_level * max_height

	for obj in spawnable_objects:
		spawn_objects(obj)

	nav_region.bake_navigation_mesh()
	await nav_region.bake_finished

	# TODO: spawn in AI

func get_noise_y(x: float, z: float) -> float:
	var value = noise.get_noise_2d(x, z)
	# get_noise_2d returns value in -1...1 range, remap to 0..1 range
	var remapped_value = (value + 1) / 2
	var adjusted_value = elevation_curve.sample(remapped_value)

	var falloff = 1.0
	if use_falloff:
		var x_percent = (x + (size_width / 2.0)) / size_width
		var z_percent = (z + (size_depth / 2.0)) / size_depth
		var x_pixel = int(x_percent * falloff_image.get_width())
		var y_pixel = int(z_percent * falloff_image.get_height())
		# since falloff texture is black/white, rgb channels are all same value
		# we can just pick one channel, e.g. red
		falloff = falloff_image.get_pixel(x_pixel, y_pixel).r

	return adjusted_value * max_height * falloff

func get_random_position() -> Vector3:
	var x = rng.randf_range(-size_width / 2.0, size_width / 2.0)
	var z = rng.randf_range(-size_depth / 2.0, size_depth / 2.0)
	var y = get_noise_y(x, z)
	return Vector3(x, y, z)

func spawn_objects(spawnable: SpawnableObject):
	for i in range(spawnable.spawn_count):
		var obj = spawnable.scenes_to_spawn[rng.randi() % spawnable.scenes_to_spawn.size()].instantiate()
		obj.add_to_group("NavSource")
		add_child(obj)

		var random_position = get_random_position()
		# prevent objects from spawning in water
		while random_position.y < water_level * max_height:
			random_position = get_random_position()

		obj.position = random_position
		obj.scale = Vector3.ONE * rng.randf_range(spawnable.min_scale, spawnable.max_scale)
		obj.rotation_degrees.y = rng.randf_range(0, 360)
