class_name RunningTrackBuilder


static func add_environment(parent: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"

	var environment := Environment.new()

	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(
		0.60,
		0.72,
		0.85
	)

	environment.ambient_light_source = (
		Environment.AMBIENT_SOURCE_COLOR
	)

	environment.ambient_light_color = Color(
		0.55,
		0.55,
		0.55
	)

	environment.ambient_light_energy = 0.6

	world_environment.environment = environment

	parent.add_child(world_environment)


static func add_sun(parent: Node3D) -> void:
	var sun := DirectionalLight3D.new()

	sun.name = "Sun"

	sun.rotation_degrees = Vector3(
		-55.0,
		35.0,
		0.0
	)

	sun.shadow_enabled = true

	sun.light_energy = 1.2

	parent.add_child(sun)


static func add_grass(parent: Node3D, track_length: float) -> void:
	var grass := StaticBody3D.new()
	grass.name = "Grass"

	# Visual mesh.
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GrassMesh"

	var mesh := BoxMesh.new()

	mesh.size = Vector3(
		40.0,
		0.5,
		track_length
	)

	mesh_instance.mesh = mesh

	mesh_instance.material_override = _material(
		Color(0.25, 0.50, 0.25)
	)

	mesh_instance.position = Vector3(
		0.0,
		-0.25,
		-track_length / 2.0
	)

	grass.add_child(mesh_instance)

	# Collision.
	var collision := CollisionShape3D.new()
	collision.name = "GrassCollision"

	var shape := BoxShape3D.new()

	shape.size = Vector3(
		40.0,
		0.5,
		track_length
	)

	collision.shape = shape

	collision.position = Vector3(
		0.0,
		-0.25,
		-track_length / 2.0
	)

	grass.add_child(collision)

	parent.add_child(grass)


static func add_track(parent: Node3D, track_width: float, track_length: float) -> void:
	var track := MeshInstance3D.new()

	track.name = "Track"

	var mesh := BoxMesh.new()

	mesh.size = Vector3(
		track_width,
		0.1,
		track_length
	)

	track.mesh = mesh

	track.material_override = _material(
		Color(0.62, 0.30, 0.18)
	)

	track.position = Vector3(
		0.0,
		0.0,
		-track_length / 2.0
	)

	parent.add_child(track)


static func add_lane_lines(parent: Node3D, track_width: float, track_length: float) -> void:
	for lane_x in range(-3, 4):
		var line := _strip(
			0.15,
			0.01,
			track_length,
			Color.WHITE,
			lane_x * 1.5,
			0.11,
			-track_length / 2.0,
			"LaneLine"
		)

		parent.add_child(line)

	# Outer edges.
	for edge_x in [-6.0, 6.0]:
		var line := _strip(
			0.15,
			0.05,
			track_length,
			Color.WHITE,
			edge_x,
			0.11,
			-track_length / 2.0,
			"EdgeLine"
		)

		parent.add_child(line)


static func add_start_line(parent: Node3D, track_width: float) -> void:
	var start_line := MeshInstance3D.new()

	start_line.name = "StartLine"

	var mesh := BoxMesh.new()

	mesh.size = Vector3(
		track_width + 1.0,
		0.05,
		1
	)

	start_line.mesh = mesh

	var material := StandardMaterial3D.new()

	material.albedo_texture = _grid_texture()

	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST
	)

	start_line.material_override = material

	start_line.position = Vector3(
		0.0,
		0.1,
		-0.4
	)

	parent.add_child(start_line)


static func add_finish_line(parent: Node3D, track_width: float) -> void:
	var finish := MeshInstance3D.new()

	finish.name = "FinishLine"

	var mesh := BoxMesh.new()

	mesh.size = Vector3(
		track_width + 1.0,
		0.05,
		0.5
	)

	finish.mesh = mesh

	var material := StandardMaterial3D.new()

	material.albedo_color = Color.WHITE

	finish.material_override = material

	finish.position = Vector3(
		0.0,
		0.11,
		-50.0
	)

	parent.add_child(finish)


static func _strip(width: float, height: float, length: float, color: Color, x: float, y: float, z: float, label: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, length)
	mesh_instance.mesh = box
	mesh_instance.name = label
	mesh_instance.material_override = _material(color)
	mesh_instance.position = Vector3(x, y, z)
	return mesh_instance


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()

	material.albedo_color = color

	return material


static func _grid_texture() -> Texture2D:
	var pixels := 64
	var tiles := 16
	var cell := pixels / tiles

	var image := Image.create(
		pixels,
		pixels,
		false,
		Image.FORMAT_RGB8
	)

	for y in pixels:
		for x in pixels:
			var light := (
				(x / cell + y / cell) % 2 == 0
			)

			image.set_pixel(
				x,
				y,
				Color(0.85, 0.85, 0.85)
				if light
				else Color(0.30, 0.30, 0.30)
			)

	return ImageTexture.create_from_image(image)
