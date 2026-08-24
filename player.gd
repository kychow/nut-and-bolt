class_name Player
extends Node3D

@export_group("Leg Controls")
@export_range(0.0, 1.5, 0.05) var swing_angle := -0.65
@export_range(-2.0, 1.5, 0.05) var knee_bend_angle := 1.0 
@export_range(0.0, 1.5, 0.05) var lift_amount := 0.25 # Vertical leg lift
@export_range(1.0, 30.0, 0.5) var smoothing := 15.0

@export_group("Torso & Dynamic Dynamics")
@export_range(0.0, 0.2, 0.01) var body_bounce_height := 0.08
@export_range(0.0, 0.5, 0.05) var forward_lean_angle := 0.25

@export_group("Movement Mechanics")
@export var max_speed := 10.0
@export var push_force := 2.5
@export var speed_decay := 3.5
@export var max_hold_time := 0.15
@export var hold_penalty_mult := 8.0

@export_group("Audio")
@export var footstep_volume_db := 0.0
@export var footstep_pitch_min := 0.92
@export var footstep_pitch_max := 1.08

var character: Node3D
var skeleton: Skeleton3D

# Bone Indices
var hips: int = -1
var spine: int = -1
var left_thigh: int = -1
var right_thigh: int = -1
var left_shin: int = -1
var right_shin: int = -1
var upperarm_l: int = -1
var upperarm_r: int = -1

# Rest Transformations
var hips_neutral_pos := Vector3.ZERO
var spine_neutral := Quaternion.IDENTITY
var left_neutral := Quaternion.IDENTITY
var right_neutral := Quaternion.IDENTITY
var left_shin_neutral := Quaternion.IDENTITY
var right_shin_neutral := Quaternion.IDENTITY
var arm_l_neutral := Quaternion.IDENTITY
var arm_r_neutral := Quaternion.IDENTITY

# Mechanics Tracking
var current_speed := 0.0
var active_leg := 0 # -1 = Left (A), 1 = Right (D)
var key_hold_timer := 0.0
var animation_phase := 0.0 # Stride cycle (0.0 to PI)

# Audio
var footstep_player: AudioStreamPlayer
var footstep_streams: Array[AudioStream] = []

func _ready() -> void:
	_load_character()
	_find_skeleton()
	_setup_bones()
	_setup_footsteps()

func _load_character() -> void:
	var glb_scene := load("res://assets/nut.glb")
	if glb_scene == null:
		push_error("Player: Could not load res://assets/nut.glb")
		return

	character = glb_scene.instantiate() as Node3D
	character.name = "Bolt"
	character.position.y += 0.03
	character.position.x += 0.75
	character.rotation_degrees.y = 180
	add_child(character)

func _find_skeleton() -> void:
	if character == null: return
	skeleton = character.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		skeleton = _find_skeleton_recursive(character)

func _find_skeleton_recursive(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node as Skeleton3D
	for child in node.get_children():
		var res := _find_skeleton_recursive(child)
		if res != null: return res
	return null

func _setup_bones() -> void:
	if skeleton == null: return

	hips = skeleton.find_bone("hips")
	spine = skeleton.find_bone("spine")
	left_thigh = skeleton.find_bone("thigh_L")
	right_thigh = skeleton.find_bone("thigh_R")
	left_shin = skeleton.find_bone("shin_L")
	right_shin = skeleton.find_bone("shin_R")
	upperarm_l = skeleton.find_bone("upperarm_L")
	upperarm_r = skeleton.find_bone("upperarm_R")

	if hips != -1: hips_neutral_pos = skeleton.get_bone_pose_position(hips)
	if spine != -1: spine_neutral = skeleton.get_bone_pose_rotation(spine)
	if left_thigh != -1: left_neutral = skeleton.get_bone_pose_rotation(left_thigh)
	if right_thigh != -1: right_neutral = skeleton.get_bone_pose_rotation(right_thigh)
	if left_shin != -1: left_shin_neutral = skeleton.get_bone_pose_rotation(left_shin)
	if right_shin != -1: right_shin_neutral = skeleton.get_bone_pose_rotation(right_shin)
	if upperarm_l != -1: arm_l_neutral = skeleton.get_bone_pose_rotation(upperarm_l)
	if upperarm_r != -1: arm_r_neutral = skeleton.get_bone_pose_rotation(upperarm_r)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.is_echo():
		return

	# Block running before instructions dismissed (main.gd flag-gate, keeps BGM playing)
	var parent := get_parent()
	if parent != null and parent.has_method("is_game_started") and not parent.is_game_started():
		return

	if event.is_action_pressed("ui_left") or event.keycode == KEY_A:
		_process_step(-1)
	elif event.is_action_pressed("ui_right") or event.keycode == KEY_D:
		_process_step(1)

func _setup_footsteps() -> void:
	footstep_player = AudioStreamPlayer.new()
	footstep_player.name = "FootstepPlayer"
	footstep_player.bus = "Master"
	footstep_player.volume_db = footstep_volume_db
	add_child(footstep_player)

	var base_path := "res://audio/Draft 1 audio files/Footfall_%d.wav"
	for i in range(1, 7):
		var stream_path := base_path % i
		var stream := load(stream_path) as AudioStream
		if stream != null:
			footstep_streams.append(stream)
		else:
			push_warning("Player: Could not load footstep stream: %s" % stream_path)

func _play_footstep() -> void:
	if footstep_player == null or footstep_streams.is_empty():
		return
	footstep_player.stream = footstep_streams.pick_random()
	footstep_player.pitch_scale = randf_range(footstep_pitch_min, footstep_pitch_max)
	footstep_player.volume_db = footstep_volume_db
	footstep_player.play()

func _process_step(leg: int) -> void:
	if leg != active_leg:
		active_leg = leg
		key_hold_timer = 0.0
		animation_phase = 0.0
		current_speed = min(current_speed + push_force, max_speed)
		_play_footstep()

func _physics_process(delta: float) -> void:
	if skeleton == null: return

	var a_held := Input.is_key_pressed(KEY_A)
	var d_held := Input.is_key_pressed(KEY_D)

	current_speed = max(0.0, current_speed - speed_decay * delta)

	# Movement & Stride Progress
	if current_speed > 0.01:
		animation_phase = min(animation_phase + delta * (current_speed * 1.5), PI)
		position += transform.basis * Vector3(0, 0, -current_speed * delta)
	else:
		animation_phase = lerp(animation_phase, 0.0, delta * 10.0)

	_animate_character(delta)

func _animate_character(delta: float) -> void:
	var stride_factor := sin(animation_phase)
	var speed_ratio := current_speed / max_speed

	var left_target := left_neutral
	var right_target := right_neutral
	var left_shin_target := left_shin_neutral
	var right_shin_target := right_shin_neutral
	var arm_l_target := arm_l_neutral
	var arm_r_target := arm_r_neutral
	var spine_target := spine_neutral

	# 1. Torso Bounce & Dynamic Forward Lean
	var bounce_offset: Vector3 = Vector3.UP * (abs(sin(animation_phase)) * body_bounce_height * speed_ratio)
	var hips_target_pos := hips_neutral_pos + bounce_offset * 4
	spine_target = spine_neutral * Quaternion.from_euler(Vector3(forward_lean_angle * speed_ratio, 0.0, 0.0))

	# 2. Leg Lift & Stride Mechanics
	if active_leg == -1: # Left leg leading
		# High knee drive + upward translation (lifts leg off the ground)
		left_target = left_neutral * Quaternion.from_euler(Vector3((swing_angle - lift_amount) * stride_factor, 0.0, 0.0))
		left_shin_target = left_shin_neutral * Quaternion.from_euler(Vector3(knee_bend_angle * stride_factor, 0.0, 0.0))
		
		# Trailing leg extended back
		right_target = right_neutral * Quaternion.from_euler(Vector3(-swing_angle * stride_factor, 0.0, 0.0))
		
		# Arm counterbalance
		arm_l_target = arm_l_neutral * Quaternion.from_euler(Vector3(-swing_angle * stride_factor, 0.0, 0.0))
		arm_r_target = arm_r_neutral * Quaternion.from_euler(Vector3(swing_angle * stride_factor, 0.0, 0.0))

	elif active_leg == 1: # Right leg leading
		right_target = right_neutral * Quaternion.from_euler(Vector3((swing_angle - lift_amount) * stride_factor, 0.0, 0.0))
		right_shin_target = right_shin_neutral * Quaternion.from_euler(Vector3(knee_bend_angle * stride_factor, 0.0, 0.0))
		
		left_target = left_neutral * Quaternion.from_euler(Vector3(-swing_angle * stride_factor, 0.0, 0.0))
		
		arm_r_target = arm_r_neutral * Quaternion.from_euler(Vector3(-swing_angle * stride_factor, 0.0, 0.0))
		arm_l_target = arm_l_neutral * Quaternion.from_euler(Vector3(swing_angle * stride_factor, 0.0, 0.0))

	var weight := 1.0 - exp(-smoothing * delta)

	# Apply Pose Updates
	if hips != -1:
		skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips).lerp(hips_target_pos, weight))
	if spine != -1:
		skeleton.set_bone_pose_rotation(spine, skeleton.get_bone_pose_rotation(spine).slerp(spine_target, weight))
	if left_thigh != -1:
		skeleton.set_bone_pose_rotation(left_thigh, skeleton.get_bone_pose_rotation(left_thigh).slerp(left_target, weight))
	if right_thigh != -1:
		skeleton.set_bone_pose_rotation(right_thigh, skeleton.get_bone_pose_rotation(right_thigh).slerp(right_target, weight))
	if left_shin != -1:
		skeleton.set_bone_pose_rotation(left_shin, skeleton.get_bone_pose_rotation(left_shin).slerp(left_shin_target, weight))
	if right_shin != -1:
		skeleton.set_bone_pose_rotation(right_shin, skeleton.get_bone_pose_rotation(right_shin).slerp(right_shin_target, weight))
	if upperarm_l != -1:
		skeleton.set_bone_pose_rotation(upperarm_l, skeleton.get_bone_pose_rotation(upperarm_l).slerp(arm_l_target, weight))
	if upperarm_r != -1:
		skeleton.set_bone_pose_rotation(upperarm_r, skeleton.get_bone_pose_rotation(upperarm_r).slerp(arm_r_target, weight))
