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
var _has_started := false

var _elapsed_time := 0.0
var _hud_canvas_layer = null
var _timer_label = null
var _win_label = null
var _restart_label = null

var _bgm_player: AudioStreamPlayer
var _instructions_layer: CanvasLayer = null


func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_floor()
	_spawn_player()
	_setup_camera()

	_create_hud()
	_setup_bgm()
	_create_instructions()

func is_game_started() -> bool:
	return _has_started


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

	var vbox := VBoxContainer.new()
	vbox.name = "HUDVBox"
	vbox.anchor_left = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_top = 0.0
	vbox.anchor_bottom = 0.0
	vbox.offset_top = 24.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	canvas_layer.add_child(vbox)

	var timer_label := Label.new()
	timer_label.name = "TimerLabel"
	timer_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 36)
	timer_label.text = "Time: %02.1fs" % _elapsed_time
	vbox.add_child(timer_label)

	var win_label := Label.new()
	win_label.name = "WinLabel"
	win_label.text = "YOU WIN!"
	win_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 48)
	win_label.visible = false
	vbox.add_child(win_label)

	var restart_label := Label.new()
	restart_label.name = "RestartLabel"
	restart_label.text = "Press R to restart"
	restart_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 24)
	restart_label.visible = false
	vbox.add_child(restart_label)

	_hud_canvas_layer = canvas_layer
	_timer_label = timer_label
	_win_label = win_label
	_restart_label = restart_label

func _create_instructions() -> void:
	# Show every run; simplest visual consistent with title_screen palette
	_instructions_layer = CanvasLayer.new()
	_instructions_layer.name = "InstructionsLayer"
	_instructions_layer.layer = 10
	add_child(_instructions_layer)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_instructions_layer.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_instructions_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	# StyleBoxFlat for rounded panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.18, 0.82)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "HOW TO RUN"
	title.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.12, 0.18))
	vbox.add_child(title)

	var keys := HBoxContainer.new()
	keys.name = "Keys"
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_theme_constant_override("separation", 12)
	vbox.add_child(keys)

	for key_name in ["A", "D"]:
		var badge := Label.new()
		badge.name = "Key" + key_name
		badge.text = key_name
		badge.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 28)
		badge.add_theme_color_override("font_color", Color(0.12, 0.12, 0.18))
		badge.custom_minimum_size = Vector2(56, 56)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color.WHITE
		bsb.set_corner_radius_all(10)
		badge.add_theme_stylebox_override("normal", bsb)
		keys.add_child(badge)

	var arrow := Label.new()
	arrow.name = "Arrow"
	arrow.text = "↔ Alternate rapidly"
	arrow.add_theme_font_size_override("font_size", 20)
	arrow.add_theme_color_override("font_color", Color.WHITE)
	keys.add_child(arrow)

	var body := Label.new()
	body.name = "Body"
	body.text = "Tap A then D, then A… Keep alternating to build speed.\nMashing one key won't move you. Race to the white finish line!"
	body.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", Color.WHITE)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(body)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Press SPACE (or A / D) to start"
	hint.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	vbox.add_child(hint)

	# Subtle flash on hint (like title_screen flash)
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(hint, "modulate:a", 0.3, 0.8)
	tween.tween_property(hint, "modulate:a", 1.0, 0.8)

func _dismiss_instructions() -> void:
	if _has_started:
		return
	_has_started = true
	if _instructions_layer == null:
		return
	var layer := _instructions_layer
	_instructions_layer = null
	# CanvasLayer has no modulate; tween its Center child
	var target: Control = layer.get_node_or_null("Center") as Control
	if target == null:
		target = layer.get_node_or_null("Dim") as Control
	if target != null:
		var tween := create_tween()
		tween.tween_property(target, "modulate:a", 0.0, 0.25)
		tween.tween_callback(layer.queue_free)
	else:
		layer.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if _has_started or _has_finished:
		return
	# Dismiss on SPACE, A, D, or mouse click (recommended)
	var should_dismiss := false
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_SPACE or event.keycode == KEY_A or event.keycode == KEY_D:
			should_dismiss = true
	elif event is InputEventMouseButton and event.pressed:
		should_dismiss = true
	elif event is InputEventJoypadButton and event.pressed:
		should_dismiss = true
	if should_dismiss:
		_dismiss_instructions()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _has_finished:
		if _win_label != null and not _win_label.visible:
			_win_label.visible = true
			_restart_label.visible = true
		if Input.is_key_pressed(KEY_R):
			get_tree().change_scene_to_file("res://hotdog_main.tscn")
		return

	if not _has_started:
		return

	_elapsed_time += delta
	_timer_label.text = "Time: %02.1fs" % _elapsed_time

	if _player.position.z <= -50.0:
		_has_finished = true
