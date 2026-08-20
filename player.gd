class_name Player
extends Node3D

const HIP_HEIGHT := 0.9
const LEG_LENGTH := 0.9
const HIP_OFFSET := 0.22
const SWING_ANGLE := 0.7
const SMOOTHING := 8.0

@export var move_speed := 1.5

var _left_pivot: Node3D
var _right_pivot: Node3D

func _ready() -> void:
	_setup_input_actions()
	_build_torso()
	_left_pivot = _build_leg("LeftLeg", Color(0.2, 0.5, 0.9), HIP_OFFSET)
	_right_pivot = _build_leg("RightLeg", Color(0.9, 0.3, 0.3), -HIP_OFFSET)

func _physics_process(delta: float) -> void:
	var left_pressed := Input.is_action_pressed("left_leg")
	var right_pressed := Input.is_action_pressed("right_leg")
	var left_target := SWING_ANGLE if left_pressed else 0.0
	var right_target := SWING_ANGLE if right_pressed else 0.0

	_left_pivot.rotation.x = lerpf(_left_pivot.rotation.x, left_target, SMOOTHING * delta)
	_right_pivot.rotation.x = lerpf(_right_pivot.rotation.x, right_target, SMOOTHING * delta)

	if left_pressed or right_pressed:
		position.z -= move_speed * delta

func _setup_input_actions() -> void:
	if not InputMap.has_action("left_leg"):
		InputMap.add_action("left_leg")
		InputMap.action_add_event("left_leg", _key_event(KEY_A))
	if not InputMap.has_action("right_leg"):
		InputMap.add_action("right_leg")
		InputMap.action_add_event("right_leg", _key_event(KEY_D))

func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	return event

func _build_torso() -> void:
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.8
	torso.mesh = mesh
	torso.position = Vector3(0, HIP_HEIGHT + LEG_LENGTH + 0.2, 0)
	torso.material_override = _material(Color(0.9, 0.55, 0.2))
	add_child(torso)

func _build_leg(leg_name: String, color: Color, x_offset: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = leg_name
	pivot.position = Vector3(x_offset, HIP_HEIGHT, 0)
	add_child(pivot)

	var leg := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.09
	mesh.bottom_radius = 0.11
	mesh.height = LEG_LENGTH
	leg.mesh = mesh
	leg.material_override = _material(color)
	leg.position = Vector3(0, -LEG_LENGTH / 2.0, 0)
	pivot.add_child(leg)

	return pivot

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material