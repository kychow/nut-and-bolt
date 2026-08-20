extends Node3D

@export_group("Camera")
@export var camera_height := 1.6
@export var camera_distance := 6.0

var _player: Player

func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_floor()
	_spawn_player()
	_setup_camera()

func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.6, 0.72, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.55)
	environment.ambient_light_energy = 0.6
	env_node.environment = environment
	add_child(env_node)

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.position = Vector3(6, 10, 6)
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	add_child(sun)

func _setup_floor() -> void:
	var grass := StaticBody3D.new()
	grass.name = "Grass"

	var grass_mesh := MeshInstance3D.new()
	var base := BoxMesh.new()
	base.size = Vector3(40, 0.5, 320)
	grass_mesh.mesh = base
	grass_mesh.material_override = _material(Color(0.25, 0.5, 0.25))
	grass_mesh.position = Vector3(0, -0.25, -150)
	grass.add_child(grass_mesh)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 0.5, 320)
	collision.shape = shape
	collision.position = Vector3(0, -0.25, -150)
	grass.add_child(collision)

	add_child(grass)

	var track := MeshInstance3D.new()
	var track_box := BoxMesh.new()
	track_box.size = Vector3(12, 0.1, 320)
	track.mesh = track_box
	track.name = "Track"
	track.material_override = _material(Color(0.62, 0.3, 0.18))
	track.position = Vector3(0, 0.05, -150)
	add_child(track)

	for lane_x in [-3.0, 0.0, 3.0]:
		add_child(_strip(0.15, 0.05, 320, Color.WHITE, lane_x, 0.11, -150, "LaneLine"))
	for edge_x in [-6.0, 6.0]:
		add_child(_strip(0.15, 0.05, 320, Color.WHITE, edge_x, 0.11, -150, "EdgeLine"))

	var start := MeshInstance3D.new()
	var start_box := BoxMesh.new()
	start_box.size = Vector3(13, 0.05, 0.5)
	start.mesh = start_box
	start.name = "StartLine"
	var start_material := StandardMaterial3D.new()
	start_material.albedo_texture = _grid_texture()
	start_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	start.material_override = start_material
	start.position = Vector3(0, 0.11, 0)
	add_child(start)

func _strip(width: float, height: float, length: float, color: Color, x: float, y: float, z: float, label: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, length)
	mesh.mesh = box
	mesh.name = label
	mesh.material_override = _material(color)
	mesh.position = Vector3(x, y, z)
	return mesh

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

func _grid_texture() -> Texture2D:
	var pixels := 64
	var tiles := 16
	var cell := pixels / tiles
	var image := Image.create(pixels, pixels, false, Image.FORMAT_RGB8)
	for y in pixels:
		for x in pixels:
			var light := (x / cell + y / cell) % 2 == 0
			image.set_pixel(x, y, Color(0.85, 0.85, 0.85) if light else Color(0.3, 0.3, 0.3))
	return ImageTexture.create_from_image(image)

func _spawn_player() -> void:
	_player = load("res://player.tscn").instantiate()
	add_child(_player)

func _setup_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "FollowCamera"
	camera.position = Vector3(0, camera_height, camera_distance)
	camera.current = true
	_player.add_child(camera)
	camera.look_at(_player.to_global(Vector3(0, 1.0, 0)))