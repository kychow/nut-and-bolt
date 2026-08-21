class_name Player
extends Node3D

@export_group("Leg Controls")
@export_range(0.0, 1.5, 0.05)
var swing_angle := 0.65

@export_range(1.0, 30.0, 0.5)
var smoothing := 10.0

@export_group("Character")
@export var character_scale := 1.0


var character: Node3D
var skeleton: Skeleton3D

var left_thigh: int = -1
var right_thigh: int = -1

var left_neutral := Quaternion.IDENTITY
var right_neutral := Quaternion.IDENTITY

func _ready() -> void:
	_load_character()
	_find_skeleton()
	_setup_bones()


func _load_character() -> void:
	var glb_scene := load("res://assets/jamaican-sprinter-rigged.glb")

	if glb_scene == null:
		push_error(
			"Player: Could not load res://assets/jamaican-sprinter-rigged.glb"
		)
		return

	character = glb_scene.instantiate() as Node3D

	if character == null:
		push_error("Player: GLB root is not a Node3D.")
		return

	character.name = "Athlete"
	character.scale = Vector3.ONE * character_scale
	character.rotation_degrees.y = 180

	add_child(character)


func _find_skeleton() -> void:
	if character == null:
		return

	# Your GLB contains the Skeleton3D under the Athlete node.
	skeleton = character.find_child(
		"Skeleton3D",
		true,
		false
	) as Skeleton3D

	if skeleton == null:
		# Fallback: find any Skeleton3D in the imported hierarchy.
		skeleton = _find_skeleton_recursive(character)

	if skeleton == null:
		push_error(
			"Player: Could not find Skeleton3D inside the GLB."
		)
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

	if left_thigh == -1:
		push_error(
			"Player: Could not find bone 'thigh_L'."
		)

	if right_thigh == -1:
		push_error(
			"Player: Could not find bone 'thigh_R'."
		)

	if left_thigh != -1:
		left_neutral = skeleton.get_bone_pose_rotation(
			left_thigh
		)

	if right_thigh != -1:
		right_neutral = skeleton.get_bone_pose_rotation(
			right_thigh
		)

	print("Left thigh bone index: ", left_thigh)
	print("Right thigh bone index: ", right_thigh)
	
	


func _physics_process(delta: float) -> void:
	if skeleton == null:
		return

	if left_thigh == -1 or right_thigh == -1:
		return

	var a_pressed := Input.is_key_pressed(KEY_A)
	var d_pressed := Input.is_key_pressed(KEY_D)

	var left_target := left_neutral
	var right_target := right_neutral

	if a_pressed:
		left_target = left_neutral * Quaternion.from_euler(
			Vector3(swing_angle, 0.0, 0.0)
		)

	if d_pressed:
		right_target = right_neutral * Quaternion.from_euler(
			Vector3(swing_angle, 0.0, 0.0)
		)

	var weight := 1.0 - exp(-smoothing * delta)

	var left_current := skeleton.get_bone_pose_rotation(left_thigh)
	var right_current := skeleton.get_bone_pose_rotation(right_thigh)

	skeleton.set_bone_pose_rotation(
		left_thigh,
		left_current.slerp(left_target, weight)
	)

	skeleton.set_bone_pose_rotation(
		right_thigh,
		right_current.slerp(right_target, weight)
	)
