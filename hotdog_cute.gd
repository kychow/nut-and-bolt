extends Node3D

# Bolt's Hot Dog — intentionally small, mobile-friendly game architecture.
# The imported GLB supplies the character. The feeding arm is procedural so
# the interaction does not depend on a particular Skeleton3D hierarchy.

const TABLE_HEIGHT := 1.016 # 4 ft in meters
const TABLE_WIDTH := 1.65
const TABLE_DEPTH := 0.62
const HOTDOG_Y := TABLE_HEIGHT + 0.085
const ARM_SHOULDER := Vector3(0.39, 1.43, 0.86)
const MOUTH := Vector3(0.0, 1.57, 0.86)
const ARM_REACH := 0.78
const HAND_RADIUS := 0.075
const PICKUP_DISTANCE := 0.14
const FEED_DISTANCE := 0.18

var camera: Camera3D
var hotdog: Node3D
var hand: Node3D
var upper_arm: MeshInstance3D
var forearm: MeshInstance3D
var hand_mesh: MeshInstance3D
var mouth_marker: MeshInstance3D
var status_label: Label
var hint_label: Label

var hand_target := Vector3(0.0, HOTDOG_Y + 0.02, 0.22)
var holding_hotdog := false
var won := false
var input_pointer := Vector2(480, 270)

func _ready() -> void:
	_build_world()
	_update_arm()
	_set_status("Pick up the hot dog")

func _process(_delta: float) -> void:
	if won:
		return
	_update_arm()
	if holding_hotdog and hotdog:
		hotdog.global_position = hand.global_position + Vector3(0.0, -0.025, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		input_pointer = event.position
		hand_target = _screen_to_play_space(input_pointer)
	elif event is InputEventScreenTouch:
		input_pointer = event.position
		hand_target = _screen_to_play_space(input_pointer)
		if event.pressed:
			_try_grab()
		else:
			_try_feed_or_release()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		input_pointer = event.position
		hand_target = _screen_to_play_space(input_pointer)
		if event.pressed:
			_try_grab()
		else:
			_try_feed_or_release()
	elif event is InputEventKey and event.pressed:
		# Desktop accessibility/testing fallback. A/D moves the hand horizontally.
		if event.keycode == KEY_A:
			hand_target.x -= 0.12
		elif event.keycode == KEY_D:
			hand_target.x += 0.12
		hand_target.x = clamp(hand_target.x, -0.55, 0.55)

func _build_world() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.75
	camera.position = Vector3(0.0, 1.22, 4.2)
	camera.look_at(Vector3(0.0, 1.15, 0.0))
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -20.0, 0.0)
	light.light_energy = 1.15
	add_child(light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 2.0, 2.0)
	fill.omni_range = 7.0
	fill.light_energy = 1.1
	add_child(fill)

	_add_floor()
	_add_table()
	_add_bolt()
	_add_hotdog()
	_add_arm()
	_add_ui()

func _add_floor() -> void:
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(5.5, 0.08, 3.5)
	floor.mesh = mesh
	floor.position = Vector3(0.0, -0.04, 0.0)
	floor.material_override = _mat(Color("#d9d0c1"))
	add_child(floor)

func _add_table() -> void:
	# Simple 4-ft folding table: thin rectangular top + four folding legs + braces.
	var top := _box(Vector3(TABLE_WIDTH, 0.075, TABLE_DEPTH), Vector3(0, TABLE_HEIGHT, 0.42), Color("#f1eee7"))
	add_child(top)

	for x in [-0.61, 0.61]:
		for z in [0.20, 0.64]:
			var leg := _cylinder(0.027, TABLE_HEIGHT - 0.075, Vector3(x, TABLE_HEIGHT / 2.0, z), Color("#8b8a86"))
			add_child(leg)
			var foot := _box(Vector3(0.16, 0.025, 0.035), Vector3(x, 0.02, z), Color("#777671"))
			add_child(foot)

	# Folding-leg braces give the silhouette without costly physics.
	for x in [-0.61, 0.61]:
		var brace := _box(Vector3(0.025, 0.55, 0.025), Vector3(x, 0.55, 0.42), Color("#a2a09a"))
		brace.rotation_degrees.z = 24.0 * (-1.0 if x < 0.0 else 1.0)
		add_child(brace)

func _add_bolt() -> void:
	var bolt_scene := load("res://assets/bolt.glb") as PackedScene
	if bolt_scene == null:
		push_error("assets/bolt.glb could not be loaded")
		return
	var bolt := bolt_scene.instantiate()
	bolt.name = "Bolt"
	bolt.position = Vector3(0.0, 0.0, 0.0)
	bolt.scale = Vector3.ONE
	add_child(bolt)

	# The source asset may have a closed/neutral mouth. A tiny black low-poly
	# mouth insert guarantees the gameplay target is visually obvious.
	mouth_marker = _ellipsoid(Vector3(0.11, 0.055, 0.018), MOUTH, Color("#171412"))
	add_child(mouth_marker)

func _add_hotdog() -> void:
	hotdog = Node3D.new()
	hotdog.name = "HotDog"
	hotdog.position = Vector3(0.0, HOTDOG_Y, 0.42)
	add_child(hotdog)

	var bun := _ellipsoid(Vector3(0.23, 0.055, 0.075), Vector3.ZERO, Color("#c9853e"))
	hotdog.add_child(bun)
	var sausage := _cylinder(0.038, 0.32, Vector3(0.0, 0.018, 0.0), Color("#a73f2f"))
	sausage.rotation_degrees.z = 90.0
	hotdog.add_child(sausage)
	var mustard := _curve_strip(Vector3(0.0, 0.064, 0.0))
	hotdog.add_child(mustard)

func _add_arm() -> void:
	# Procedural two-bone arm. This is deliberately independent of the GLB rig.
	# It can later be replaced with Skeleton3D/IK without changing game input.
	hand = Node3D.new()
	hand.name = "HandTarget"
	add_child(hand)

	upper_arm = _cylinder(0.065, 0.32, Vector3.ZERO, Color("#7a513d"))
	forearm = _cylinder(0.055, 0.29, Vector3.ZERO, Color("#845641"))
	hand_mesh = _ellipsoid(Vector3(HAND_RADIUS, HAND_RADIUS * 1.1, HAND_RADIUS * 0.85), Vector3.ZERO, Color("#8b5c46"))
	hand.add_child(upper_arm)
	hand.add_child(forearm)
	hand.add_child(hand_mesh)

func _update_arm() -> void:
	if hand == null:
		return
	hand_target.x = clamp(hand_target.x, -0.58, 0.58)
	hand_target.y = clamp(hand_target.y, TABLE_HEIGHT + 0.06, 1.72)
	hand_target.z = 0.86

	var shoulder := ARM_SHOULDER
	var target := hand_target
	var to_target := target - shoulder
	var distance: float = clamp(to_target.length(), 0.18, ARM_REACH)
	var direction := to_target.normalized()
	var elbow: Vector3 = shoulder + direction * (distance * 0.52) + Vector3(0.0, 0.12, 0.0)
	var wrist := shoulder + direction * distance

	# Position hand at IK target and orient the two bone segments toward it.
	hand.global_position = wrist
	_set_segment(upper_arm, shoulder, elbow)
	_set_segment(forearm, elbow, wrist)

func _try_grab() -> void:
	if hotdog == null:
		return
	if won:
		_reset_game()
		return
	if hotdog.global_position.distance_to(hand.global_position) <= PICKUP_DISTANCE:
		holding_hotdog = true
		_set_status("Drag to the mouth")

func _try_feed_or_release() -> void:
	if not holding_hotdog or hotdog == null:
		return
	if hand.global_position.distance_to(MOUTH) <= FEED_DISTANCE:
		winning_feed()
	else:
		holding_hotdog = false
		_set_status("Pick up the hot dog")

func _reset_game() -> void:
	won = false
	holding_hotdog = false
	if hotdog:
		hotdog.global_position = Vector3(0.0, HOTDOG_Y, 0.42)
	_set_status("Pick up the hot dog")
	hint_label.text = "Move the pointer/finger to move the hand • hold to grab • release near mouth"

func winning_feed() -> void:
	won = true
	holding_hotdog = false
	hotdog.global_position = MOUTH
	_set_status("Nice. Fed successfully.")
	hint_label.text = "TAP / CLICK TO PLAY AGAIN"

func _screen_to_play_space(screen: Vector2) -> Vector3:
	var viewport_size := get_viewport().get_visible_rect().size
	var nx := (screen.x / viewport_size.x) * 2.0 - 1.0
	var ny := (screen.y / viewport_size.y) * 2.0 - 1.0
	# Orthographic camera: horizontal/vertical screen coordinates map directly to world.
	return Vector3(nx * 0.95, 1.32 - ny * 0.72, 0.86)

func _add_ui() -> void:
	var layer := CanvasLayer.new()
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

func _set_segment(segment: Node3D, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	segment.global_position = mid
	segment.look_at(b, Vector3.UP)
	segment.rotate_object_local(Vector3.RIGHT, PI / 2.0)

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	n.mesh = m
	n.position = pos
	n.material_override = _mat(color)
	return n

func _cylinder(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 8
	n.mesh = m
	n.position = pos
	n.material_override = _mat(color)
	return n

func _ellipsoid(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var m := SphereMesh.new()
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
	# A short yellow capsule is visually enough for mustard in a low-poly game.
	var n := _cylinder(0.009, 0.16, pos + Vector3(0.0, 0.0, 0.0), Color("#e0ad27"))
	n.rotation_degrees.z = 90.0
	return n

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
