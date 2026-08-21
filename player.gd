class_name Player
extends Node3D

@export_group("Leg Controls")
@export_range(0.0, 1.5, 0.05)
var swing_angle := -0.65

@export_range(-2.0, 1.5, 0.05)
var knee_bend_angle := 1.0 

@export_range(1.0, 30.0, 0.5)
var smoothing := 15.0

@export_group("Movement & Pace")
@export var move_speed := 5.0 
@export var pace_frequency := 12.0 # How fast the legs cycle per second

@export_group("Character")
@export var character_scale := 1.0


var character: Node3D
var skeleton: Skeleton3D

var left_thigh: int = -1
var right_thigh: int = -1
var left_shin: int = -1
var right_shin: int = -1

var left_neutral := Quaternion.IDENTITY
var right_neutral := Quaternion.IDENTITY
var left_shin_neutral := Quaternion.IDENTITY
var right_shin_neutral := Quaternion.IDENTITY

# Run Pace Variables
var stride_phase := 0.0
var current_speed := 0.0

func _ready() -> void:
	_load_character()
	_find_skeleton()
	_setup_bones()

func _load_character() -> void:
	var glb_scene := load("res://assets/jamaican-sprinter-rigged.glb")

	if glb_scene == null:
		push_error("Player: Could not load res://assets/jamaican-sprinter-rigged.glb")
		return

	character = glb_scene.instantiate() as Node3D

	if character == null:
		push_error("Player: GLB root is not a Node3D.")
		return

	character.name = "Bolt"
	character.scale = Vector3.ONE * character_scale
	character.position.y += 0.032
	character.rotation_degrees.y = 180

	add_child(character)


func _find_skeleton() -> void:
	if character == null:
		return

	# Skeleton3D is contained under the Athlete node
	skeleton = character.find_child("Skeleton3D", true, false) as Skeleton3D

	if skeleton == null:
		# Fallback: find any Skeleton3D in the imported hierarchy.
		skeleton = _find_skeleton_recursive(character)

	if skeleton == null:
		push_error("Player: Could not find Skeleton3D inside the GLB.")
		return

	print("Player skeleton found: ", skeleton.get_path())


func _find_skeleton_recursive(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D

	for child in node.get_children():
		var result := _find_skeleton_recursive(child)
		if result != null:
			return result

	return null


func _setup_bones() -> void:
	if skeleton == null:
		return

	left_thigh = skeleton.find_bone("thigh_L")
	right_thigh = skeleton.find_bone("thigh_R")

	left_shin = skeleton.find_bone("shin_L")
	right_shin = skeleton.find_bone("shin_R")

	if left_thigh == -1:
		push_error("Player: Could not find bone 'thigh_L'.")
	if right_thigh == -1:
		push_error("Player: Could not find bone 'thigh_R'.")

	# Save neutral poses for thighs
	if left_thigh != -1:
		left_neutral = skeleton.get_bone_pose_rotation(left_thigh)
	if right_thigh != -1:
		right_neutral = skeleton.get_bone_pose_rotation(right_thigh)
		
	# Save neutral poses for shins
	if left_shin != -1:
		left_shin_neutral = skeleton.get_bone_pose_rotation(left_shin)
	if right_shin != -1:
		right_shin_neutral = skeleton.get_bone_pose_rotation(right_shin)

	print("Left thigh index: ", left_thigh, " | Left shin index: ", left_shin)
	print("Right thigh index: ", right_thigh, " | Right shin index: ", right_shin)


func _physics_process(delta: float) -> void:
	if skeleton == null:
		return
	if left_thigh == -1 or right_thigh == -1:
		return

	var a_pressed := Input.is_key_pressed(KEY_A)
	var d_pressed := Input.is_key_pressed(KEY_D)

	var left_target := left_neutral
	var right_target := right_neutral
	var left_shin_target := left_shin_neutral
	var right_shin_target := right_shin_neutral

	# Check that only one key is being pressed to allow movement and stride
	if a_pressed and not d_pressed:
		# Left leg swings forward, knee bends
		left_target = left_neutral * Quaternion.from_euler(Vector3(swing_angle, 0.0, 0.0))
		left_shin_target = left_shin_neutral * Quaternion.from_euler(Vector3(knee_bend_angle, 0.0, 0.0))
		
		# Right leg swings backward (inverted swing_angle), shin stays straight
		right_target = right_neutral * Quaternion.from_euler(Vector3(-swing_angle, 0.0, 0.0))
		right_shin_target = right_shin_neutral
		
		# Move the character forward in local space (-Z is standard forward in Godot)
		position += transform.basis * Vector3(0, 0, -move_speed * delta)

	elif d_pressed and not a_pressed:
		# Right leg swings forward, knee bends
		right_target = right_neutral * Quaternion.from_euler(Vector3(swing_angle, 0.0, 0.0))
		right_shin_target = right_shin_neutral * Quaternion.from_euler(Vector3(knee_bend_angle, 0.0, 0.0))
		
		# Left leg swings backward (inverted swing_angle), shin stays straight
		left_target = left_neutral * Quaternion.from_euler(Vector3(-swing_angle, 0.0, 0.0))
		left_shin_target = left_shin_neutral
		
		# Move the character forward
		position += transform.basis * Vector3(0, 0, -move_speed * delta)

	var weight := 1.0 - exp(-smoothing * delta)

	# Apply Thigh Rotations
	var left_current := skeleton.get_bone_pose_rotation(left_thigh)
	var right_current := skeleton.get_bone_pose_rotation(right_thigh)
	
	skeleton.set_bone_pose_rotation(left_thigh, left_current.slerp(left_target, weight))
	skeleton.set_bone_pose_rotation(right_thigh, right_current.slerp(right_target, weight))
	
	# Apply Shin Rotations
	if left_shin != -1:
		var left_shin_current := skeleton.get_bone_pose_rotation(left_shin)
		skeleton.set_bone_pose_rotation(left_shin, left_shin_current.slerp(left_shin_target, weight))
		
	if right_shin != -1:
		var right_shin_current := skeleton.get_bone_pose_rotation(right_shin)
		skeleton.set_bone_pose_rotation(right_shin, right_shin_current.slerp(right_shin_target, weight))
