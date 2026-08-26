extends Node3D

# Hotdog AI prototype — actual GLB arm drives the interaction.
# The GLB is expected at res://bolt.glb and contains bones:
# shoulder_R -> upperarm_R -> forearm_R -> hand_R.

const TABLE_HEIGHT: float = 1.016
const TABLE_WIDTH: float = 1.65
const TABLE_DEPTH: float = 0.62
const HOTDOG_Y: float = TABLE_HEIGHT + 0.085
const HOTDOG_Z: float = 0.3
const PICKUP_DISTANCE: float = 0.16
const FEED_DISTANCE: float = 0.20
const ARM_MAX_REACH: float = 0.72

var camera: Camera3D
var bolt: Node3D
var skeleton: Skeleton3D
var upperarm_idx: int = -1
var forearm_idx: int = -1
var hand_idx: int = -1
var shoulder_idx: int = -1
var head_idx: int = -1
var animation_player: AnimationPlayer

var hotdog: Node3D
var mouth_marker: MeshInstance3D
var status_label: Label
var hint_label: Label

var hand_target: Vector3 = Vector3(0.0, HOTDOG_Y + 0.02, HOTDOG_Z)
var holding_hotdog: bool = false
var won: bool = false

var shoulder_world: Vector3 = Vector3.ZERO
var mouth_world: Vector3 = Vector3(1, 1.75, 0.88)
var head_tilt_angle: float = 0.0
var head_tilt_target: float = 0.0

var eating: bool = false
var bite_count: int = 0
var bite_timer: float = 0.0
const BITE_DURATION: float = 0.3
const CHOMP_ANGLE: float = 0.26
const ARM_CHOMP_OFFSET: float = 0.04
var head_tilt_base: float = 0.0
var clip_materials: Array[ShaderMaterial] = []

func _ready() -> void:
	_build_world()
	_setup_bolt_rig()
	_update_actual_arm()
	_set_status("Pick up the hot dog")

func _process(delta: float) -> void:
	if won:
		return
	if eating:
		_process_eating(delta)
		return
	_update_actual_arm()
	if holding_hotdog and hotdog:
		hotdog.global_position = _current_hand_world() + Vector3(0.0, -0.025, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if eating:
		return
	if event is InputEventMouseMotion:
		hand_target = _screen_to_play_space(event.position)
	elif event is InputEventScreenTouch:
		hand_target = _screen_to_play_space(event.position)
		if event.pressed:
			_try_grab()
		else:
			_try_feed_or_release()
	elif event is InputEventScreenDrag:
		hand_target = _screen_to_play_space(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		hand_target = _screen_to_play_space(event.position)
		if event.pressed:
			_try_grab()
		else:
			_try_feed_or_release()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_A:
			hand_target.x -= 0.12
		elif event.keycode == KEY_D:
			hand_target.x += 0.12
		hand_target.x = clamp(hand_target.x, -0.58, 0.58)

func _build_world() -> void:
	RunningTrackBuilder.add_environment(self)
	RunningTrackBuilder.add_sun(self)
	RunningTrackBuilder.add_grass(self, 30.0)
	RunningTrackBuilder.add_track(self, 12.0, 30.0)
	RunningTrackBuilder.add_lane_lines(self, 12.0, 30.0)
	RunningTrackBuilder.add_start_line(self, 12.0)
	RunningTrackBuilder.add_finish_line(self, 12.0)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.55
	camera.position = Vector3(0.0, 1.30, 4.20)
	camera.look_at(Vector3(0.0, 1.25, 0.0))
	add_child(camera)

	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(0.0, 2.0, 2.0)
	fill.omni_range = 7.0
	fill.light_energy = 1.1
	add_child(fill)

	_add_table()
	_add_bolt()
	_add_hotdog()
	_add_ui()

func _add_table() -> void:
	var top: MeshInstance3D = _box(Vector3(TABLE_WIDTH, 0.075, TABLE_DEPTH), Vector3(0.0, TABLE_HEIGHT, HOTDOG_Z), Color("#f1eee7"))
	add_child(top)

	for x: float in [-0.61, 0.61]:
		for z: float in [0.20, 0.64]:
			var leg: MeshInstance3D = _cylinder(0.027, TABLE_HEIGHT - 0.075, Vector3(x, TABLE_HEIGHT / 2.0, z), Color("#8b8a86"))
			add_child(leg)
			var foot: MeshInstance3D = _box(Vector3(0.16, 0.025, 0.035), Vector3(x, 0.02, z), Color("#777671"))
			add_child(foot)

	for x: float in [-0.61, 0.61]:
		var brace: MeshInstance3D = _box(Vector3(0.025, 0.55, 0.025), Vector3(x, 0.55, HOTDOG_Z), Color("#a2a09a"))
		brace.rotation_degrees.z = 24.0 * (-1.0 if x < 0.0 else 1.0)
		add_child(brace)

func _add_bolt() -> void:
	var bolt_scene: PackedScene = load("res://assets/bolt.glb") as PackedScene
	if bolt_scene == null:
		push_error("res://bolt.glb could not be loaded")
		return

	bolt = bolt_scene.instantiate() as Node3D
	bolt.name = "Bolt"
	add_child(bolt)

	# Stop any imported animation so the feeding pose owns the arm.
	animation_player = _find_animation_player(bolt)
	if animation_player:
		animation_player.stop()
		animation_player.active = false

	mouth_marker = _ellipsoid(Vector3(0.075, 0.025, 0.01), mouth_world, Color("#171412"))
	add_child(mouth_marker)

func _setup_bolt_rig() -> void:
	skeleton = _find_skeleton(bolt)
	if skeleton == null:
		push_error("No Skeleton3D found in bolt.glb")
		return

	shoulder_idx = skeleton.find_bone("shoulder_R")
	upperarm_idx = skeleton.find_bone("upperarm_R")
	forearm_idx = skeleton.find_bone("forearm_R")
	hand_idx = skeleton.find_bone("hand_R")

	if shoulder_idx < 0 or upperarm_idx < 0 or forearm_idx < 0 or hand_idx < 0:
		push_error("Expected right-arm bones were not found in bolt.glb")
		return

	shoulder_world = _bone_world_position(shoulder_idx)

	head_idx = skeleton.find_bone("head")

	# Head base position from GLB rest pose (bone at 0, 1.60, 0).
	# Mouth offset from original code: (0.25, 0.215, HOTDOG_Z) relative to head.
	mouth_world = Vector3(0.0, 1.60, 0.0) + Vector3(0.0, 0.215, HOTDOG_Z)
	if mouth_marker:
		mouth_marker.global_position = mouth_world

func _update_actual_arm() -> void:
	if skeleton == null or upperarm_idx < 0:
		return

	shoulder_world = _bone_world_position(shoulder_idx)

	var target: Vector3 = hand_target
	target.z = HOTDOG_Z

	var shoulder_to_target: Vector3 = target - shoulder_world
	var target_distance: float = clamp(shoulder_to_target.length(), 0.22, ARM_MAX_REACH)
	var target_dir: Vector3 = shoulder_to_target.normalized()

	# Solve a simple two-bone chain using the GLB's actual bone lengths.
	var upper_len: float = _bone_length(upperarm_idx, forearm_idx)
	var fore_len: float = _bone_length(forearm_idx, hand_idx)
	var total_len: float = max(upper_len + fore_len, 0.30)
	var desired: float = min(target_distance, total_len * 0.98)

	# Bend the elbow slightly toward the camera so the hand remains visible.
	var bend_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
	var side: Vector3 = target_dir.cross(bend_axis)
	if side.length_squared() < 0.001:
		side = Vector3.LEFT
	side = side.normalized()

	var cos_a: float = clamp((upper_len * upper_len + desired * desired - fore_len * fore_len) / max(2.0 * upper_len * desired, 0.001), -1.0, 1.0)
	var sin_a: float = sqrt(max(0.0, 1.0 - cos_a * cos_a))
	var elbow_dir: Vector3 = (target_dir * cos_a + side * sin_a).normalized()
	var elbow_world: Vector3 = shoulder_world + elbow_dir * upper_len

	_aim_bone_world(upperarm_idx, shoulder_world, elbow_world)
	_aim_bone_world(forearm_idx, elbow_world, target)

	# Force the hand bone's position to the target while retaining its rest orientation.
	var hand_pose: Transform3D = skeleton.get_bone_global_pose_no_override(hand_idx)
	hand_pose.origin = skeleton.global_transform.affine_inverse() * target
	skeleton.set_bone_global_pose_override(hand_idx, hand_pose, 1.0, true)

	# --- Head tilt: pitch forward as the hand rises ---
	var tilt_height_min: float = HOTDOG_Y
	var tilt_height_max: float = HOTDOG_Y + 0.45
	var tilt_max_deg: float = 30.0
	var raw: float = clamp((hand_target.y - tilt_height_min) / (tilt_height_max - tilt_height_min), 0.0, 1.0)
	head_tilt_target = deg_to_rad(tilt_max_deg) * raw
	head_tilt_angle = lerp(head_tilt_angle, head_tilt_target, 0.12)

	# Apply tilt to the head bone so the mesh visually tilts forward.
	if head_idx >= 0:
		var head_pose: Transform3D = skeleton.get_bone_global_pose_no_override(head_idx)
		head_pose.basis = Basis(Quaternion(Vector3.RIGHT, head_tilt_angle)) * head_pose.basis
		head_pose.origin = skeleton.global_transform.affine_inverse() * Vector3(0.0, 1.60, 0.0)
		skeleton.set_bone_global_pose_override(head_idx, head_pose, 1.0, true)

	# Rotate the mouth offset around the head base (X-axis tilt).
	var head_base: Vector3 = Vector3(0.0, 1.60, 0.0)
	var mouth_offset: Vector3 = Vector3(0.0, 0.05, 0.15)
	var cos_t: float = cos(head_tilt_angle)
	var sin_t: float = sin(head_tilt_angle)
	var rotated_offset: Vector3 = Vector3(
		mouth_offset.x,
		mouth_offset.y * cos_t - mouth_offset.z * sin_t,
		mouth_offset.y * sin_t + mouth_offset.z * cos_t
	)
	mouth_world = head_base + rotated_offset
	if mouth_marker:
		mouth_marker.global_position = mouth_world

func _aim_bone_world(bone_idx: int, start_world: Vector3, end_world: Vector3) -> void:
	var direction_world: Vector3 = (end_world - start_world).normalized()
	if direction_world.length_squared() < 0.0001:
		return

	var skeleton_inv: Transform3D = skeleton.global_transform.affine_inverse()
	var start_local: Vector3 = skeleton_inv * start_world
	var end_local: Vector3 = skeleton_inv * end_world
	var direction_local: Vector3 = (end_local - start_local).normalized()

	# Imported bones point down their local -Y axis.
	var rotation: Quaternion = Quaternion(Vector3.DOWN, direction_local)
	var pose: Transform3D = skeleton.get_bone_global_pose_no_override(bone_idx)
	pose.origin = start_local
	pose.basis = Basis(rotation)
	skeleton.set_bone_global_pose_override(bone_idx, pose, 1.0, true)

func _bone_world_position(bone_idx: int) -> Vector3:
	var pose: Transform3D = skeleton.get_bone_global_pose_no_override(bone_idx)
	return skeleton.global_transform * Vector3(-0.25, 1.42, -0.12)

func _bone_length(parent_idx: int, child_idx: int) -> float:
	var parent_pose: Transform3D = skeleton.get_bone_global_pose_no_override(parent_idx)
	var child_pose: Transform3D = skeleton.get_bone_global_pose_no_override(child_idx)
	return max(parent_pose.origin.distance_to(child_pose.origin), 0.05)

func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found:
			return found
	return null

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found:
			return found
	return null

func _current_hand_world() -> Vector3:
	if skeleton != null and hand_idx >= 0:
		var pose: Transform3D = skeleton.get_bone_global_pose(hand_idx)
		return skeleton.global_transform * pose.origin
	return hand_target

func _try_grab() -> void:
	if hotdog == null or won:
		if won:
			_reset_game()
		return

	var actual_hand: Vector3 = _current_hand_world()
	if hotdog.global_position.distance_to(actual_hand) <= PICKUP_DISTANCE:
		holding_hotdog = true
		_set_status("Drag to the mouth")

func _try_feed_or_release() -> void:
	if not holding_hotdog or hotdog == null:
		return

	var actual_hand: Vector3 = _current_hand_world()
	if actual_hand.distance_to(mouth_world) <= FEED_DISTANCE:
		winning_feed()
	else:
		holding_hotdog = false
		_set_status("Pick up the hot dog")

func _reset_game() -> void:
	won = false
	holding_hotdog = false
	eating = false
	bite_count = 0
	bite_timer = 0.0
	head_tilt_angle = 0.0
	head_tilt_target = 0.0
	if hotdog:
		hotdog.global_position = Vector3(0.0, HOTDOG_Y, HOTDOG_Z)
		hotdog.visible = true
	for mat in clip_materials:
		mat.set_shader_parameter("clip_x", 0.3)
	hand_target = Vector3(0.0, HOTDOG_Y + 0.02, HOTDOG_Z)
	_set_status("Pick up the hot dog")
	if hint_label:
		hint_label.text = "Move the pointer/finger to move the hand • hold to grab • release near mouth"
		hint_label.visible = true

func winning_feed() -> void:
	eating = true
	bite_count = 0
	bite_timer = 0.0
	head_tilt_base = head_tilt_angle
	holding_hotdog = false
	if hotdog:
		hotdog.global_position = mouth_world
	_set_status("")
	if hint_label:
		hint_label.visible = false

func _process_eating(delta: float) -> void:
	bite_timer += delta
	var t: float = bite_timer / BITE_DURATION

	if t < 1.0:
		# Chomp animation phases
		var chomp_t: float
		if t < 0.4:
			# Phase 0: head tilts forward, arm tugs toward mouth
			chomp_t = t / 0.4
		elif t < 0.6:
			# Phase 1: hold — head stays, arm static
			chomp_t = 1.0
		else:
			# Phase 2: head retracts, arm relaxes
			chomp_t = 1.0 - (t - 0.6) / 0.4

		# Head chomp
		head_tilt_angle = head_tilt_base + CHOMP_ANGLE * chomp_t

		# Arm tug toward mouth
		var arm_offset: Vector3 = Vector3(0.0, 0.0, -ARM_CHOMP_OFFSET) * chomp_t
		hand_target = mouth_world + arm_offset

		# Clip the hotdog: each third instantly vanishes at the start of its bite
		var clip_x: float = 0.3 - float(bite_count + 1) * 0.2
		for mat in clip_materials:
			mat.set_shader_parameter("clip_x", clip_x)

		_update_actual_arm()
	else:
		# Bite complete
		bite_count += 1
		bite_timer = 0.0
		if bite_count >= 3:
			_finish_eating()

func _finish_eating() -> void:
	eating = false
	won = true
	if hotdog:
		hotdog.visible = false
	_set_status("Nice. Fed successfully.")
	if hint_label:
		hint_label.text = "TAP / CLICK TO PLAY AGAIN"
		hint_label.visible = true

func _screen_to_play_space(screen: Vector2) -> Vector3:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var nx: float = (screen.x / viewport_size.x) * 2.0 - 1.0
	var ny: float = (screen.y / viewport_size.y) * 2.0 - 1.0
	return Vector3(nx * 0.82, 1.48 - ny * 0.55, HOTDOG_Z)

func _add_hotdog() -> void:
	hotdog = Node3D.new()
	hotdog.name = "HotDog"
	hotdog.position = Vector3(0.0, HOTDOG_Y, HOTDOG_Z)
	add_child(hotdog)

	var clip_shader: Shader = Shader.new()
	clip_shader.code = """shader_type spatial;
	uniform vec4 base_color : source_color = vec4(1.0);
	uniform float clip_x : hint_range(-1.0, 1.0) = 0.3;
	void fragment() {
		ALBEDO = base_color.rgb;
		if (VERTEX.x > clip_x) discard;
	}"""

	var bun: MeshInstance3D = _ellipsoid(Vector3(0.23, 0.055, 0.075), Vector3.ZERO, Color("#c9853e"))
	var bun_mat: ShaderMaterial = ShaderMaterial.new()
	bun_mat.shader = clip_shader
	bun_mat.set_shader_parameter("base_color", Color("#c9853e"))
	bun_mat.set_shader_parameter("clip_x", 0.3)
	bun.material_override = bun_mat
	clip_materials.append(bun_mat)
	hotdog.add_child(bun)

	var sausage: MeshInstance3D = _cylinder(0.038, 0.32, Vector3(0.0, 0.018, 0.0), Color("#a73f2f"))
	sausage.rotation_degrees.z = 90.0
	var sausage_mat: ShaderMaterial = ShaderMaterial.new()
	sausage_mat.shader = clip_shader
	sausage_mat.set_shader_parameter("base_color", Color("#a73f2f"))
	sausage_mat.set_shader_parameter("clip_x", 0.3)
	sausage.material_override = sausage_mat
	clip_materials.append(sausage_mat)
	hotdog.add_child(sausage)

	var mustard: MeshInstance3D = _curve_strip(Vector3.ZERO)
	var mustard_mat: ShaderMaterial = ShaderMaterial.new()
	mustard_mat.shader = clip_shader
	mustard_mat.set_shader_parameter("base_color", Color("#e0ad27"))
	mustard_mat.set_shader_parameter("clip_x", 0.3)
	mustard.material_override = mustard_mat
	clip_materials.append(mustard_mat)
	hotdog.add_child(mustard)

func _add_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	status_label = Label.new()
	status_label.position = Vector2(28, 22)
	status_label.add_theme_font_size_override("font_size", 26)
	layer.add_child(status_label)
	hint_label = Label.new()
	hint_label.position = Vector2(28, 62)
	hint_label.text = "Move the pointer/finger to move the hand • hold to grab • release near mouth"
	hint_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(hint_label)

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var n: MeshInstance3D = MeshInstance3D.new()
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	n.mesh = m
	n.position = pos
	n.material_override = _mat(color)
	return n

func _cylinder(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var n: MeshInstance3D = MeshInstance3D.new()
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 8
	n.mesh = m
	n.position = pos
	n.material_override = _mat(color)
	return n

func _ellipsoid(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var n: MeshInstance3D = MeshInstance3D.new()
	var m: SphereMesh = SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 12
	m.rings = 6
	n.mesh = m
	n.scale = size
	n.position = pos
	n.material_override = _mat(color)
	return n

func _curve_strip(pos: Vector3) -> MeshInstance3D:
	var n: MeshInstance3D = _cylinder(0.009, 0.16, pos, Color("#e0ad27"))
	n.rotation_degrees.z = 90.0
	return n

func _mat(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
