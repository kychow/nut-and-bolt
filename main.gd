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

var _hud_canvas_layer = null
var _win_label = null
var _restart_label = null

var _bgm_player: AudioStreamPlayer
var _instructions_layer: CanvasLayer = null


func _ready() -> void:
	GlobalTimer.stop_counting()
	RunningTrackBuilder.add_environment(self)
	RunningTrackBuilder.add_sun(self)
	RunningTrackBuilder.add_grass(self, track_length)
	RunningTrackBuilder.add_track(self, track_width, track_length)
	RunningTrackBuilder.add_lane_lines(self, track_width, track_length)
	RunningTrackBuilder.add_start_line(self, track_width)
	RunningTrackBuilder.add_finish_line(self, track_width)
	_spawn_player()
	_setup_camera()

	_create_hud()
	_setup_bgm()
	_create_instructions()

func is_game_started() -> bool:
	return _has_started


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

	var win_label := Label.new()
	win_label.name = "WinLabel"
	win_label.text = "YOU WIN!"
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	win_label.anchor_left = 0.0
	win_label.anchor_right = 1.0
	win_label.anchor_top = 0.0
	win_label.anchor_bottom = 0.0
	win_label.offset_right = 0.0
	win_label.offset_top = 68.0
	win_label.offset_bottom = 120.0
	win_label.add_theme_font_size_override("font_size", 48)
	win_label.add_theme_color_override("font_color", Color.WHITE)
	win_label.add_theme_color_override("font_outline_color", Color.BLACK)
	win_label.add_theme_constant_override("outline_size", 6)
	win_label.visible = false
	canvas_layer.add_child(win_label)

	var restart_label := Label.new()
	restart_label.name = "RestartLabel"
	restart_label.text = "Press R to restart"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	restart_label.anchor_left = 0.0
	restart_label.anchor_right = 1.0
	restart_label.anchor_top = 0.0
	restart_label.anchor_bottom = 0.0
	restart_label.offset_right = 0.0
	restart_label.offset_top = 124.0
	restart_label.offset_bottom = 156.0
	restart_label.add_theme_font_size_override("font_size", 24)
	restart_label.add_theme_color_override("font_color", Color.WHITE)
	restart_label.add_theme_color_override("font_outline_color", Color.BLACK)
	restart_label.add_theme_constant_override("outline_size", 6)
	restart_label.visible = false
	canvas_layer.add_child(restart_label)

	_hud_canvas_layer = canvas_layer
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
	GlobalTimer.start_counting()
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
			GlobalTimer.reset()
			get_tree().change_scene_to_file("res://hotdog_main.tscn")
		return

	if not _has_started:
		return

	if _player.position.z <= -50.0:
		_has_finished = true
		GlobalTimer.stop_counting()
