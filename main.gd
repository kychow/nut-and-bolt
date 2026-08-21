extends Node3D


@export_group("Camera")
@export var camera_height := 1.8
@export var camera_distance := 5.5

@export_group("Track")
@export var track_length := 320.0
@export var track_width := 12.0

@export_group("Audio")
@export var bgm_volume_db := -8.0
@export_file("*.mp3", "*.ogg", "*.wav") var bgm_stream_path := "res://audio/Raw audio files/Super_Mario_Level_Loop_FULL_SONG_MusicGPT.mp3"


var _player: Player

var _has_finished := false
var _win_screen_shown := false

var _elapsed_time := 0.0
var _hud_canvas_layer = null
var _timer_label = null

var _bgm_player: AudioStreamPlayer


func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_floor()
	_spawn_player()
	_setup_camera()

	_create_hud()
	_setup_bgm()


# ============================================================
# ENVIRONMENT
# ============================================================

func _setup_environment() -> void:
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

	add_child(world_environment)


# ============================================================
# LIGHTING
# ============================================================

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()

	sun.name = "Sun"

	sun.rotation_degrees = Vector3(
		-55.0,
		35.0,
		0.0
	)

	sun.shadow_enabled = true

	sun.light_energy = 1.2

	add_child(sun)


# ============================================================
# FLOOR / TRACK
# ============================================================

func _setup_floor() -> void:
	_create_grass()
	_create_track()
	_create_lane_lines()
	_create_start_line()
	_create_finish_line()


func _create_grass() -> void:
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

	add_child(grass)


func _create_track() -> void:
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

	add_child(track)


func _create_lane_lines() -> void:
	# Three lanes:
	#
	#     | lane -3 | lane -2 | lane - 1 | lane 0 | lane 1 | lane 2 | lane 3 
	#       -3      0      3
	#
	# These lines separate the lanes.

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

		add_child(line)

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

		add_child(line)


func _create_start_line() -> void:
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

	add_child(start_line)


func _create_finish_line() -> void:
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

	add_child(finish)


func _strip(width: float, height: float, length: float, color: Color, x: float, y: float, z: float, label: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, length)
	mesh_instance.mesh = box
	mesh_instance.name = label
	mesh_instance.material_override = _material(color)
	mesh_instance.position = Vector3(x, y, z)
	return mesh_instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()

	material.albedo_color = color

	return material


func _grid_texture() -> Texture2D:
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


func _setup_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = "Master"
	_bgm_player.volume_db = bgm_volume_db
	_bgm_player.autoplay = false
	add_child(_bgm_player)

	if bgm_stream_path.is_empty():
		push_warning("Main: BGM stream path is empty.")
		return

	var stream := load(bgm_stream_path) as AudioStream
	if stream == null:
		push_warning("Main: Could not load BGM stream: %s" % bgm_stream_path)
		return

	# Enable looping for MP3/OGG/WAV at runtime (import may have loop=false)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

	_bgm_player.stream = stream
	_bgm_player.play()

# ============================================================
# PLAYER
# ============================================================

func _spawn_player() -> void:
	_player = Player.new()

	_player.name = "Player"

	add_child(_player)

	# The GLB itself is loaded by player.gd.
	#
	# Put the player at the starting line.
	_player.position = Vector3(
		0.0,
		0.0,
		0.0
	)


# ============================================================
# CAMERA
# ============================================================

func _setup_camera() -> void:
	if _player == null:
		push_error(
			"Camera setup failed: Player is null."
		)
		return

	var camera := Camera3D.new()

	camera.name = "FollowCamera"

	_player.add_child(camera)

	camera.position = Vector3(
		5.0,
		camera_height,
		camera_distance
	)

	# Look slightly down the track instead of directly
	# at the player's origin.
	camera.look_at(
		_player.to_global(
			Vector3(
				0.0,
				1.0,
				-3.0
			)
		),
		Vector3.UP
	)

	camera.current = true

	camera.fov = 20.0

func _create_hud() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "HUD"
	add_child(canvas_layer)

	var label := Label.new()
	label.name = "TimerLabel"
	#label.position = Vector2(0, -50)
	label.size = Vector2(200, 50)
	label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	label.text = "Time: %02.1fs" % _elapsed_time

	canvas_layer.add_child(label)

	_hud_canvas_layer = canvas_layer
	_timer_label = label


func _create_win_screen() -> void:
	_win_screen_shown = true

	# Dark overlay background.
	var overlay := ColorRect.new()
	overlay.name = "WinOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	_hud_canvas_layer.add_child(overlay)

	# Center container for all win text.
	var center := CenterContainer.new()
	center.name = "WinCenter"
	center.anchors_preset = Control.PRESET_FULL_RECT
	_hud_canvas_layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.name = "WinVBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	# Title.
	var title := Label.new()
	title.name = "WinTitle"
	title.text = "YOU WIN!"
	title.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	vbox.add_child(title)

	# Final time.
	var time_label := Label.new()
	time_label.name = "WinTime"
	time_label.text = "Time: %02.1fs" % _elapsed_time
	time_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(time_label)

	# Restart instruction.
	var instruction := Label.new()
	instruction.name = "WinInstruction"
	instruction.text = "Press R to restart"
	instruction.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 28)
	vbox.add_child(instruction)


func _process(delta: float) -> void:
	if _has_finished:
		if not _win_screen_shown:
			_create_win_screen()
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return

	_elapsed_time += delta
	_timer_label.text = "Time: %02.1fs" % _elapsed_time

	if _player.position.z <= -50.0:
		_has_finished = true
