extends Node3D

# --- Stage 1: static head + one physics-driven ragdoll arm ---
# --- Stage 2: hand grab/release on a single hotdog prop ---
#
# Camera faces the character from the front (character facing +Z, toward the
# camera). Screen-left/right is therefore the OPPOSITE of the arm's own
# anatomical left/right, since the character mirrors the viewer. Input below
# is deliberately written directly in world/screen X (not the arm's own
# anatomical frame) so "A" always drags the target toward screen-left — this
# is the mirroring the design calls for, just implemented without an
# intermediate anatomical-frame step.

const LAYER_ARM := 1
const LAYER_HAND := 2
const LAYER_HOTDOG := 3
const LAYER_TABLE := 4
const LAYER_GROUND := 5
const LAYER_FACE := 6

const HEAD_RADIUS := 1.05
const MOUTH_RADIUS := 0.225

# Shoulder moved out from its original -0.3 by one original head length
# (2 * the pre-scale-up 0.35 head radius = 0.7), i.e. further from the head,
# then an additional 1/3 of the (now scaled-up) head radius further out
# still, so the shoulder clears the head with a visible gap instead of
# sitting inside its now much larger radius.
const SHOULDER_POS := Vector3(-1.0 - HEAD_RADIUS / 3.0, 1.4, 0.05)
const UPPER_ARM_LEN := 0.35
const FOREARM_LEN := 0.32
const UPPER_ARM_RADIUS := 0.055
const FOREARM_RADIUS := 0.05
const HAND_RADIUS := 0.05
const HAND_LEN := 0.05
const MAX_REACH := UPPER_ARM_LEN + FOREARM_LEN

const ELBOW_MIN_DEG := 0.0
const ELBOW_MAX_DEG := 140.0
const WRIST_LIMIT_DEG := 30.0

const GRAB_RADIUS := 0.08

const TABLE_TOP_Y := 1.05
const TABLE_SIZE := Vector3(0.5, TABLE_TOP_Y, 0.5)
const TABLE_POS := Vector3(0, TABLE_TOP_Y * 0.5, 0)

# Head center is placed so its bottom edge clears the tabletop by one full
# head length (diameter, 2*HEAD_RADIUS) of gap.
const HEAD_POS := Vector3(0, TABLE_TOP_Y + 2.0 * HEAD_RADIUS + HEAD_RADIUS, 0)

const HOTDOG_RADIUS := 0.045
const HOTDOG_LEN := 0.22

const HAND_OPEN_COLOR := Color(0.95, 0.75, 0.6)
const HAND_CLOSED_COLOR := Color(0.85, 0.5, 0.35)

# Thruster-style target control — deliberately floaty by design; see the
# arm-control section of the design doc for why this shouldn't be "fixed"
# with heavier damping.
const TARGET_DAMPING := 0.992

# The following are tunable live from the on-screen slider panel (see
# _setup_tuning_ui) — they're `var`s with these as just the starting values,
# not `const`s, so player-side tuning doesn't require touching code at all.
var _target_accel: float = 650.0

# PD spring driving the hand toward the target. Damping is set to ~40% of
# critical damping (2*sqrt(stiffness*mass)) for this stiffness/mass, which
# is the "fluid but bouncy" regime (visible overshoot, a couple of settling
# oscillations) rather than either robotically snapping (ratio ~1) or
# wobbling forever (ratio <0.15). See godot_ragdoll_physics_reference.md.
var _hand_spring_stiffness: float = 48.0
var _hand_spring_damping: float = 3.5

# The shoulder is ALSO a script-driven Hooke's-law torque spring (aligning
# the upper arm's pointing direction), not just a passively-dragged joint —
# native Generic6DOFJoint3D spring fields are deliberately avoided (Jolt has
# multiple undocumented spring modes with no documented way to tell which
# one Godot is actually using). The wrist stays passive (just its existing
# hard angular limit) — unlike the shoulder, it's limited on all 3 axes
# including roll, and an added active spring there fought that limit badly
# enough to peg the hand's angular velocity at an engine safety ceiling; not
# worth chasing down further given how minor the wrist's motion range is.
var _shoulder_spring_stiffness: float = 22.0
var _shoulder_spring_damping: float = 3.0

# Elbow uses HingeJoint3D's own native motor instead — a true 1-DOF hinge is
# exactly what that motor is a well-defined, non-ambiguous fit for. Driven
# toward a 2-link-IK elbow angle each tick, but torque-limited (max_impulse)
# so it's an assist, not a kinematic override — gravity/momentum/collisions
# can still overpower it, so the arm stays genuinely physics-driven.
var _elbow_motor_strength: float = 10.0
var _elbow_motor_gain: float = 4.0

# Arm segments get a bit of extra gravity_scale on top of the engine default
# so a released/undriven arm visibly sags — but not so much that the spring
# above can no longer lift it (see _hand_spring_stiffness).
var _arm_gravity_scale: float = 1.2

# The shoulder has genuinely zero angular limit (a real shoulder's wide
# range of motion, per the design), so nothing but this passively damps its
# spin around its own long axis — the align-torque spring above only
# corrects pointing direction, not roll, by design (see _align_torque).
# Without a reasonably strong damp here, that roll can idle in a persistent
# low-level spin indefinitely rather than settling.
var _arm_angular_damp: float = 8.0

# Gravity on the CONTROL TARGET itself, not just the physical arm. Without
# this, letting go of all keys leaves the target frozen at whatever height
# it last had, and a spring strong enough to actually lift the arm (see
# _hand_spring_stiffness) is then also strong enough to hold it there against
# gravity almost perfectly — the arm would never fall when idle. This makes
# the target itself sink when not being actively held up, same as the arm.
var _target_gravity: float = 9.8

# Vertical camera framing: ground at the bottom, up to one more head-radius
# of clear headspace above the head's own top edge. Originally this was
# purely table-height-derived (2x table height above the tabletop), but
# that no longer tracks anything meaningful now that the head's size and
# position are set independently of the table — re-anchored to the head
# itself so it doesn't end up cropped out of frame.
const CAMERA_FOV_DEG := 45.0
const FRAME_BOTTOM_Y := 0.0
const FRAME_TOP_Y := HEAD_POS.y + HEAD_RADIUS * 2.0

var _rest_dir: Vector3 = Vector3(0, -0.15, 1).normalized()

var _upper_arm: RigidBody3D
var _forearm: RigidBody3D
var _hand: RigidBody3D
var _hand_mesh: MeshInstance3D

var _hotdog: RigidBody3D
var _hotdog_rest_transform: Transform3D
var _held_hotdog: RigidBody3D = null
var _grab_joint: Generic6DOFJoint3D = null
var _elbow_joint: HingeJoint3D

var _arm_material: PhysicsMaterial
var _hotdog_material: PhysicsMaterial
var _environment_material: PhysicsMaterial

var _rest_transforms: Dictionary = {}

var _target_pos: Vector3
var _target_vel: Vector3 = Vector3.ZERO

var _debug_enabled: bool = false
var _debug_nodes: Array[Node3D] = []

func _ready() -> void:
	_setup_input_actions()
	_setup_materials()
	_setup_environment()
	_setup_lighting()
	_setup_ground()
	_setup_head()
	_setup_arm()
	_setup_table_and_hotdog()
	_setup_camera()
	_setup_controls_ui()
	_setup_tuning_ui()
	_target_pos = SHOULDER_POS + _rest_dir * (MAX_REACH * 0.7)

func _setup_materials() -> void:
	# Starting values kept low — bounce compounds with the active hand
	# spring on every contact, so what looks like a modest restitution value
	# can still grow bounce height over repeated hits rather than settling.
	# All three are live-editable from the tuning panel (see _setup_tuning_ui).
	_arm_material = _physics_material(0.15, 0.2)
	_hotdog_material = _physics_material(0.08, 0.35)
	_environment_material = _physics_material(0.15, 0.2)

func _setup_input_actions() -> void:
	var bindings := {
		"left_arm_y_pos": KEY_W,
		"left_arm_y_neg": KEY_S,
		"left_arm_x_neg": KEY_A,
		"left_arm_x_pos": KEY_D,
		"left_arm_z_neg": KEY_Q,
		"left_arm_z_pos": KEY_E,
		"left_arm_release": KEY_SHIFT,
		"reset_arms": KEY_R,
		"toggle_debug": KEY_F1,
	}
	for action_name in bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var event := InputEventKey.new()
			event.physical_keycode = bindings[action_name]
			InputMap.action_add_event(action_name, event)

func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.3, 0.32, 0.38)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.ambient_light_energy = 1.3
	env_node.environment = environment
	add_child(env_node)

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.position = Vector3(2, 4, 4)
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.light_energy = 1.8
	add_child(sun)

func _setup_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.set_collision_layer_value(LAYER_GROUND, true)
	ground.physics_material_override = _environment_material

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6, 0.2, 6)
	mesh_inst.mesh = box
	mesh_inst.material_override = _material(Color(0.3, 0.3, 0.33))
	mesh_inst.position = Vector3(0, -0.1, 0)
	ground.add_child(mesh_inst)

	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6, 0.2, 6)
	coll.shape = shape
	coll.position = Vector3(0, -0.1, 0)
	ground.add_child(coll)

	add_child(ground)

func _setup_head() -> void:
	var head := CSGCombiner3D.new()
	head.name = "Head"
	head.use_collision = true
	head.set_collision_layer_value(LAYER_FACE, true)
	head.position = HEAD_POS

	var skull := CSGSphere3D.new()
	skull.radius = HEAD_RADIUS
	skull.material = _material(Color(0.95, 0.8, 0.65))
	head.add_child(skull)

	var mouth := CSGCylinder3D.new()
	mouth.operation = CSGShape3D.OPERATION_SUBTRACTION
	mouth.radius = MOUTH_RADIUS
	mouth.height = HEAD_RADIUS * 2.2
	mouth.rotation_degrees.x = 90.0
	mouth.position = Vector3(0, -0.05, 0)
	head.add_child(mouth)

	add_child(head)

func _setup_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "MainCamera"
	camera.current = true
	camera.fov = CAMERA_FOV_DEG
	camera.keep_aspect = Camera3D.KEEP_HEIGHT

	var frame_height := FRAME_TOP_Y - FRAME_BOTTOM_Y
	var center_y := (FRAME_TOP_Y + FRAME_BOTTOM_Y) * 0.5
	var distance := (frame_height * 0.5) / tan(deg_to_rad(CAMERA_FOV_DEG * 0.5))

	camera.position = Vector3(0, center_y, distance)
	add_child(camera)
	camera.look_at(Vector3(0, center_y, 0), Vector3.UP)

func _setup_controls_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ControlsUI"

	var label := Label.new()
	label.text = "Left arm hand target — W: up   S: down   A: left   D: right   Q: back (toward face)   E: forward (toward table)\nLeft Shift: release   R: reset arm   F1: toggle debug view"
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)

	add_child(layer)

func _setup_tuning_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TuningUI"

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-260, 12)
	panel.custom_minimum_size = Vector2(248, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "Live tuning"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	_add_slider(box, "Hand spring stiffness", 0.0, 120.0, 1.0, _hand_spring_stiffness, func(v): _hand_spring_stiffness = v)
	_add_slider(box, "Hand spring damping", 0.0, 30.0, 0.5, _hand_spring_damping, func(v): _hand_spring_damping = v)
	_add_slider(box, "Shoulder spring stiffness", 0.0, 60.0, 1.0, _shoulder_spring_stiffness, func(v): _shoulder_spring_stiffness = v)
	_add_slider(box, "Shoulder spring damping", 0.0, 15.0, 0.25, _shoulder_spring_damping, func(v): _shoulder_spring_damping = v)
	_add_slider(box, "Elbow motor strength", 0.0, 40.0, 0.5, _elbow_motor_strength, func(v): _elbow_motor_strength = v)
	_add_slider(box, "Elbow motor gain", 0.0, 15.0, 0.25, _elbow_motor_gain, func(v): _elbow_motor_gain = v)
	_add_slider(box, "Arm gravity scale", 0.0, 3.0, 0.1, _arm_gravity_scale, func(v):
		_arm_gravity_scale = v
		_upper_arm.gravity_scale = v
		_forearm.gravity_scale = v
		_hand.gravity_scale = v
	)
	_add_slider(box, "Arm angular damp", 0.0, 20.0, 0.5, _arm_angular_damp, func(v):
		_arm_angular_damp = v
		_upper_arm.angular_damp = v
		_forearm.angular_damp = v
		_hand.angular_damp = v
	)
	_add_slider(box, "Target gravity", 0.0, 20.0, 0.5, _target_gravity, func(v): _target_gravity = v)
	_add_slider(box, "Target accel", 100.0, 1200.0, 10.0, _target_accel, func(v): _target_accel = v)
	_add_slider(box, "Arm bounce", 0.0, 1.0, 0.05, _arm_material.bounce, func(v): _arm_material.bounce = v)
	_add_slider(box, "Arm friction", 0.0, 1.0, 0.05, _arm_material.friction, func(v): _arm_material.friction = v)
	_add_slider(box, "Hotdog bounce", 0.0, 1.0, 0.05, _hotdog_material.bounce, func(v): _hotdog_material.bounce = v)
	_add_slider(box, "Hotdog friction", 0.0, 1.0, 0.05, _hotdog_material.friction, func(v): _hotdog_material.friction = v)
	_add_slider(box, "Ground/table bounce", 0.0, 1.0, 0.05, _environment_material.bounce, func(v): _environment_material.bounce = v)
	_add_slider(box, "Ground/table friction", 0.0, 1.0, 0.05, _environment_material.friction, func(v): _environment_material.friction = v)

	add_child(layer)

func _add_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step: float, initial: float, setter: Callable) -> void:
	var row := VBoxContainer.new()

	var header := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var value_label := Label.new()
	value_label.text = "%.2f" % initial
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8))
	header.add_child(value_label)
	row.add_child(header)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial
	slider.value_changed.connect(func(v):
		value_label.text = "%.2f" % v
		setter.call(v)
	)
	row.add_child(slider)

	parent.add_child(row)

# --- Arm construction --------------------------------------------------

func _basis_from_axis(dir: Vector3) -> Basis:
	var y_axis := dir.normalized()
	var helper := Vector3.FORWARD
	if abs(y_axis.dot(helper)) > 0.9:
		helper = Vector3.RIGHT
	var x_axis := helper.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

func _make_capsule_body(body_name: String, radius: float, height: float, mass: float, color: Color, material: PhysicsMaterial) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = body_name
	body.mass = mass
	body.can_sleep = false
	body.physics_material_override = material

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh_inst.mesh = mesh
	mesh_inst.material_override = _material(color)
	body.add_child(mesh_inst)

	var coll := CollisionShape3D.new()
	coll.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	coll.shape = shape
	body.add_child(coll)

	return body

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

func _physics_material(bounce: float, friction: float) -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.bounce = bounce
	mat.friction = friction
	return mat

func _configure_6dof(joint: Generic6DOFJoint3D, angular_limit_deg: float) -> void:
	for axis in ["x", "y", "z"]:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		var free_angular := angular_limit_deg < 0.0
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, not free_angular)
		if not free_angular:
			var rad := deg_to_rad(angular_limit_deg)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -rad)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, rad)

func _setup_arm() -> void:
	var elbow_pos := SHOULDER_POS + _rest_dir * UPPER_ARM_LEN
	var wrist_pos := elbow_pos + _rest_dir * FOREARM_LEN

	var rest_basis := _basis_from_axis(_rest_dir)

	_upper_arm = _make_capsule_body("UpperArm", UPPER_ARM_RADIUS, UPPER_ARM_LEN + UPPER_ARM_RADIUS * 2.0, 1.2, Color(0.85, 0.6, 0.45), _arm_material)
	_upper_arm.global_transform = Transform3D(rest_basis, SHOULDER_POS + _rest_dir * (UPPER_ARM_LEN * 0.5))
	_upper_arm.gravity_scale = _arm_gravity_scale
	_upper_arm.angular_damp = _arm_angular_damp
	_upper_arm.set_collision_layer_value(LAYER_ARM, true)
	_upper_arm.set_collision_mask_value(LAYER_GROUND, true)
	_upper_arm.set_collision_mask_value(LAYER_FACE, true)
	_upper_arm.set_collision_mask_value(LAYER_TABLE, true)
	_upper_arm.set_collision_mask_value(LAYER_HOTDOG, true)
	add_child(_upper_arm)

	_forearm = _make_capsule_body("Forearm", FOREARM_RADIUS, FOREARM_LEN + FOREARM_RADIUS * 2.0, 0.8, Color(0.85, 0.6, 0.45), _arm_material)
	_forearm.global_transform = Transform3D(rest_basis, elbow_pos + _rest_dir * (FOREARM_LEN * 0.5))
	_forearm.gravity_scale = _arm_gravity_scale
	_forearm.angular_damp = _arm_angular_damp
	_forearm.set_collision_layer_value(LAYER_ARM, true)
	_forearm.set_collision_mask_value(LAYER_GROUND, true)
	_forearm.set_collision_mask_value(LAYER_FACE, true)
	_forearm.set_collision_mask_value(LAYER_TABLE, true)
	_forearm.set_collision_mask_value(LAYER_HOTDOG, true)
	add_child(_forearm)

	_hand = _make_capsule_body("Hand", HAND_RADIUS, HAND_LEN + HAND_RADIUS * 2.0, 0.4, Color(0.95, 0.75, 0.6), _arm_material)
	_hand.global_transform = Transform3D(rest_basis, wrist_pos + _rest_dir * (HAND_LEN * 0.5 + HAND_RADIUS))
	_hand.gravity_scale = _arm_gravity_scale
	_hand.angular_damp = _arm_angular_damp
	_hand.set_collision_layer_value(LAYER_HAND, true)
	_hand.set_collision_mask_value(LAYER_GROUND, true)
	_hand.set_collision_mask_value(LAYER_FACE, true)
	_hand.set_collision_mask_value(LAYER_TABLE, true)
	_hand.set_collision_mask_value(LAYER_HOTDOG, true)
	add_child(_hand)
	_hand_mesh = _hand.get_node("Mesh")

	var grab_area := Area3D.new()
	grab_area.name = "GrabArea"
	grab_area.set_collision_mask_value(LAYER_HOTDOG, true)
	var grab_shape := CollisionShape3D.new()
	var grab_sphere := SphereShape3D.new()
	grab_sphere.radius = GRAB_RADIUS
	grab_shape.shape = grab_sphere
	grab_area.add_child(grab_shape)
	grab_area.body_entered.connect(_on_grab_area_body_entered)
	_hand.add_child(grab_area)

	# Shoulder: Generic6DOFJoint3D, node_a left unset. Under Jolt (this
	# project's physics engine), an unassigned joint slot resolves to world —
	# the opposite convention from GodotPhysics — so this alone anchors the
	# joint to a fixed point in space without a separate static anchor body.
	var shoulder_joint := Generic6DOFJoint3D.new()
	add_child(shoulder_joint)
	shoulder_joint.global_transform = Transform3D(rest_basis, SHOULDER_POS)
	shoulder_joint.node_b = shoulder_joint.get_path_to(_upper_arm)
	shoulder_joint.exclude_nodes_from_collision = true
	_configure_6dof(shoulder_joint, -1.0)

	# Elbow: HingeJoint3D, hinge axis = world X (the joint's local Z axis).
	_elbow_joint = HingeJoint3D.new()
	add_child(_elbow_joint)
	_elbow_joint.global_transform = Transform3D(_basis_from_axis(Vector3.RIGHT), elbow_pos)
	_elbow_joint.node_a = _elbow_joint.get_path_to(_upper_arm)
	_elbow_joint.node_b = _elbow_joint.get_path_to(_forearm)
	_elbow_joint.exclude_nodes_from_collision = true
	_elbow_joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	_elbow_joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(ELBOW_MIN_DEG))
	_elbow_joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(ELBOW_MAX_DEG))
	# Native motor (a true 1-DOF hinge is an unambiguous fit for this, unlike
	# the 6DOF spring fields) — target_velocity is driven each physics tick
	# in _physics_process from a 2-link-IK elbow angle; max_impulse here caps
	# how strongly it can push, so it's an assist, not a kinematic override.
	_elbow_joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	_elbow_joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, _elbow_motor_strength)

	# Wrist: Generic6DOFJoint3D, linear locked + modest angular limits.
	var wrist_joint := Generic6DOFJoint3D.new()
	add_child(wrist_joint)
	wrist_joint.global_transform = Transform3D(rest_basis, wrist_pos)
	wrist_joint.node_a = wrist_joint.get_path_to(_forearm)
	wrist_joint.node_b = wrist_joint.get_path_to(_hand)
	wrist_joint.exclude_nodes_from_collision = true
	_configure_6dof(wrist_joint, WRIST_LIMIT_DEG)

	_rest_transforms = {
		"upper_arm": _upper_arm.global_transform,
		"forearm": _forearm.global_transform,
		"hand": _hand.global_transform,
		"target": _target_pos,
	}

	_setup_debug_visuals(elbow_pos, wrist_pos, rest_basis)

func _setup_table_and_hotdog() -> void:
	var table := StaticBody3D.new()
	table.name = "Table"
	table.set_collision_layer_value(LAYER_TABLE, true)
	table.physics_material_override = _environment_material

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = TABLE_SIZE
	mesh_inst.mesh = box
	mesh_inst.material_override = _material(Color(0.5, 0.35, 0.22))
	table.add_child(mesh_inst)

	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = TABLE_SIZE
	coll.shape = shape
	table.add_child(coll)

	table.position = TABLE_POS
	add_child(table)

	_hotdog = _make_capsule_body("Hotdog", HOTDOG_RADIUS, HOTDOG_LEN, 0.15, Color(0.75, 0.35, 0.25), _hotdog_material)
	# A smooth capsule lying on its side has almost no rolling resistance from
	# friction alone (the contact point barely slides even while rolling), so
	# without extra angular damping a single knock sends it rolling forever.
	_hotdog.angular_damp = 3.0
	_hotdog.set_collision_layer_value(LAYER_HOTDOG, true)
	_hotdog.set_collision_mask_value(LAYER_GROUND, true)
	_hotdog.set_collision_mask_value(LAYER_TABLE, true)
	_hotdog.set_collision_mask_value(LAYER_ARM, true)
	_hotdog.set_collision_mask_value(LAYER_HAND, true)
	_hotdog.set_collision_mask_value(LAYER_FACE, true)
	var hotdog_basis := _basis_from_axis(Vector3.RIGHT)
	_hotdog.global_transform = Transform3D(hotdog_basis, TABLE_POS + Vector3(0, TABLE_TOP_Y * 0.5 + HOTDOG_RADIUS, 0))
	add_child(_hotdog)
	_hotdog_rest_transform = _hotdog.global_transform

func _on_grab_area_body_entered(body: Node) -> void:
	if _held_hotdog != null:
		return
	if body == _hotdog:
		_grab_hotdog(body as RigidBody3D)

func _grab_hotdog(hotdog: RigidBody3D) -> void:
	_held_hotdog = hotdog
	hotdog.global_transform = _hand.global_transform
	hotdog.linear_velocity = Vector3.ZERO
	hotdog.angular_velocity = Vector3.ZERO

	_grab_joint = Generic6DOFJoint3D.new()
	add_child(_grab_joint)
	_grab_joint.global_transform = _hand.global_transform
	_grab_joint.node_a = _grab_joint.get_path_to(_hand)
	_grab_joint.node_b = _grab_joint.get_path_to(hotdog)
	_grab_joint.exclude_nodes_from_collision = true
	_configure_6dof(_grab_joint, 5.0)

	_hand_mesh.material_override = _material(HAND_CLOSED_COLOR)

func _release_held_hotdog() -> void:
	if _held_hotdog == null:
		return
	_held_hotdog.linear_velocity = _hand.linear_velocity
	_held_hotdog.angular_velocity = _hand.angular_velocity
	_grab_joint.queue_free()
	_grab_joint = null
	_held_hotdog = null
	_hand_mesh.material_override = _material(HAND_OPEN_COLOR)

# --- Per-frame control ---------------------------------------------------

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_debug"):
		_debug_enabled = not _debug_enabled
		for node in _debug_nodes:
			node.visible = _debug_enabled

	if Input.is_action_just_pressed("reset_arms"):
		_reset_arm()
		return

	if Input.is_action_just_pressed("left_arm_release"):
		_release_held_hotdog()

	var accel := Vector3.ZERO
	if Input.is_action_pressed("left_arm_y_pos"):
		accel.y += _target_accel
	if Input.is_action_pressed("left_arm_y_neg"):
		accel.y -= _target_accel
	if Input.is_action_pressed("left_arm_x_neg"):
		accel.x -= _target_accel
	if Input.is_action_pressed("left_arm_x_pos"):
		accel.x += _target_accel
	if Input.is_action_pressed("left_arm_z_neg"):
		accel.z -= _target_accel
	if Input.is_action_pressed("left_arm_z_pos"):
		accel.z += _target_accel

	accel.y -= _target_gravity
	_target_vel += accel * delta
	_target_vel *= TARGET_DAMPING
	_target_pos += _target_vel * delta

	var offset := _target_pos - SHOULDER_POS
	if offset.length() > MAX_REACH:
		var radial_dir := offset.normalized()
		_target_pos = SHOULDER_POS + radial_dir * MAX_REACH
		# Drop only the outward component so the target doesn't keep
		# accumulating unbounded "phantom" velocity while pinned at the
		# reach limit — that pent-up velocity made direction changes feel
		# sluggish (and was overshooting into wild uncontrolled swings).
		var outward_vel := _target_vel.dot(radial_dir)
		if outward_vel > 0.0:
			_target_vel -= radial_dir * outward_vel

	var error := _target_pos - _hand.global_position
	var force := error * _hand_spring_stiffness - _hand.linear_velocity * _hand_spring_damping
	_hand.apply_central_force(force)

	_drive_shoulder_spring()
	_drive_elbow_motor()

## Aligns only the body's long (local Y) axis toward desired_dir — deliberately
## NOT a full 3-axis orientation spring. A capsule is rotationally symmetric
## around its own long axis, so there's no physically meaningful "desired
## roll" to spring toward, and that axis has much lower moment of inertia
## than the other two — a full orientation spring drives it with the same
## damping used for the (much higher-inertia) pointing direction, which is
## wildly underdamped for roll and causes the body to spin in place
## indefinitely around its own axis even after it's pointing the right way.
## cross(current, desired) has no such roll component by construction: it's
## zero exactly when current already equals desired, regardless of roll.
func _align_torque(body: RigidBody3D, desired_dir: Vector3, stiffness: float, damping: float) -> Vector3:
	var current_dir := body.global_transform.basis.y
	return current_dir.cross(desired_dir) * stiffness - body.angular_velocity * damping

func _drive_shoulder_spring() -> void:
	var to_target := _target_pos - SHOULDER_POS
	if to_target.length() < 0.001:
		return
	_upper_arm.apply_torque(_align_torque(_upper_arm, to_target.normalized(), _shoulder_spring_stiffness, _shoulder_spring_damping))

func _drive_elbow_motor() -> void:
	# Desired elbow bend via 2-link law-of-cosines IK toward the current
	# target distance — used only as a torque-limited motor target (see
	# _elbow_motor_strength), so this assists rather than replaces physics.
	var dist := clampf((_target_pos - SHOULDER_POS).length(), 0.001, UPPER_ARM_LEN + FOREARM_LEN - 0.001)
	var cos_interior := clampf((UPPER_ARM_LEN * UPPER_ARM_LEN + FOREARM_LEN * FOREARM_LEN - dist * dist) / (2.0 * UPPER_ARM_LEN * FOREARM_LEN), -1.0, 1.0)
	var interior_angle := acos(cos_interior)
	var desired_flex := PI - interior_angle

	var hinge_axis := Vector3.RIGHT
	var upper_ref := (_upper_arm.global_transform.basis.y - hinge_axis * _upper_arm.global_transform.basis.y.dot(hinge_axis)).normalized()
	var forearm_ref := (_forearm.global_transform.basis.y - hinge_axis * _forearm.global_transform.basis.y.dot(hinge_axis)).normalized()
	var current_flex := upper_ref.signed_angle_to(forearm_ref, hinge_axis)

	var target_velocity := clampf((desired_flex - current_flex) * _elbow_motor_gain, -8.0, 8.0)
	_elbow_joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, target_velocity)
	_elbow_joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, _elbow_motor_strength)

func _reset_arm() -> void:
	_upper_arm.global_transform = _rest_transforms["upper_arm"]
	_upper_arm.linear_velocity = Vector3.ZERO
	_upper_arm.angular_velocity = Vector3.ZERO
	_forearm.global_transform = _rest_transforms["forearm"]
	_forearm.linear_velocity = Vector3.ZERO
	_forearm.angular_velocity = Vector3.ZERO
	_hand.global_transform = _rest_transforms["hand"]
	_hand.linear_velocity = Vector3.ZERO
	_hand.angular_velocity = Vector3.ZERO
	_target_pos = _rest_transforms["target"]
	_target_vel = Vector3.ZERO

	if _held_hotdog != null:
		_grab_joint.queue_free()
		_grab_joint = null
		_held_hotdog = null
		_hand_mesh.material_override = _material(HAND_OPEN_COLOR)
	_hotdog.global_transform = _hotdog_rest_transform
	_hotdog.linear_velocity = Vector3.ZERO
	_hotdog.angular_velocity = Vector3.ZERO

# --- Debug visualization (F1) --------------------------------------------

func _make_wire_mesh(builder: Callable) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(Color(0.2, 1.0, 0.4, 0.9))
	builder.call(st)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mesh_inst.material_override = mat
	mesh_inst.visible = false
	return mesh_inst

func _add_wire_circle(st: SurfaceTool, radius: float, segments: int, axis_a: Vector3, axis_b: Vector3) -> void:
	for i in range(segments):
		var a1 := (float(i) / segments) * TAU
		var a2 := (float(i + 1) / segments) * TAU
		st.add_vertex(axis_a * cos(a1) * radius + axis_b * sin(a1) * radius)
		st.add_vertex(axis_a * cos(a2) * radius + axis_b * sin(a2) * radius)

func _make_wire_sphere(radius: float) -> MeshInstance3D:
	return _make_wire_mesh(func(st: SurfaceTool) -> void:
		_add_wire_circle(st, radius, 32, Vector3.RIGHT, Vector3.UP)
		_add_wire_circle(st, radius, 32, Vector3.UP, Vector3.FORWARD)
		_add_wire_circle(st, radius, 32, Vector3.RIGHT, Vector3.FORWARD)
	)

func _make_wire_arc(radius: float, start_deg: float, end_deg: float) -> MeshInstance3D:
	return _make_wire_mesh(func(st: SurfaceTool) -> void:
		var segments := 16
		var start_rad := deg_to_rad(start_deg)
		var end_rad := deg_to_rad(end_deg)
		var prev := Vector3.RIGHT * cos(start_rad) * radius + Vector3.UP * sin(start_rad) * radius
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(prev)
		for i in range(1, segments + 1):
			var t := start_rad + (end_rad - start_rad) * (float(i) / segments)
			var p := Vector3.RIGHT * cos(t) * radius + Vector3.UP * sin(t) * radius
			st.add_vertex(prev)
			st.add_vertex(p)
			prev = p
		st.add_vertex(prev)
		st.add_vertex(Vector3.ZERO)
	)

func _make_wire_cone(half_angle_deg: float, length: float) -> MeshInstance3D:
	return _make_wire_mesh(func(st: SurfaceTool) -> void:
		var ring_radius := length * tan(deg_to_rad(half_angle_deg))
		var apex := Vector3.ZERO
		var tip := Vector3.FORWARD * length
		var segments := 16
		var prev := Vector3.ZERO
		for i in range(segments + 1):
			var a := (float(i) / segments) * TAU
			var p := tip + Vector3.RIGHT * cos(a) * ring_radius + Vector3.UP * sin(a) * ring_radius
			if i > 0:
				st.add_vertex(prev)
				st.add_vertex(p)
			prev = p
		for i in range(4):
			var a := (float(i) / 4) * TAU
			var p := tip + Vector3.RIGHT * cos(a) * ring_radius + Vector3.UP * sin(a) * ring_radius
			st.add_vertex(apex)
			st.add_vertex(p)
	)

func _setup_debug_visuals(elbow_pos: Vector3, wrist_pos: Vector3, rest_basis: Basis) -> void:
	var reach_sphere := _make_wire_sphere(MAX_REACH)
	reach_sphere.position = SHOULDER_POS
	add_child(reach_sphere)
	_debug_nodes.append(reach_sphere)

	# Elbow limit arc, parented to the upper arm so it moves with it. Computed
	# once relative to the upper arm's own frame — valid for the joint's
	# lifetime since the hinge axis is fixed relative to that body.
	var elbow_arc := _make_wire_arc(0.15, ELBOW_MIN_DEG, ELBOW_MAX_DEG)
	var elbow_local_basis: Basis = _upper_arm.global_transform.basis.inverse() * _basis_from_axis(Vector3.RIGHT)
	var elbow_local_pos: Vector3 = _upper_arm.global_transform.basis.inverse() * (elbow_pos - _upper_arm.global_position)
	elbow_arc.transform = Transform3D(elbow_local_basis, elbow_local_pos)
	_upper_arm.add_child(elbow_arc)
	_debug_nodes.append(elbow_arc)

	# Wrist limit cone, parented to the forearm the same way.
	var wrist_cone := _make_wire_cone(WRIST_LIMIT_DEG, 0.15)
	var wrist_local_basis: Basis = _forearm.global_transform.basis.inverse() * rest_basis
	var wrist_local_pos: Vector3 = _forearm.global_transform.basis.inverse() * (wrist_pos - _forearm.global_position)
	wrist_cone.transform = Transform3D(wrist_local_basis, wrist_local_pos)
	_forearm.add_child(wrist_cone)
	_debug_nodes.append(wrist_cone)

	# Hand grab radius, parented to the hand so it tracks automatically.
	var grab_sphere_debug := _make_wire_sphere(GRAB_RADIUS)
	_hand.add_child(grab_sphere_debug)
	_debug_nodes.append(grab_sphere_debug)
