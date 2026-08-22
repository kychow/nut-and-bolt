extends Node3D

# --- Stage 1: static head + one physics-driven ragdoll arm ---
# --- Stage 2: hand grab/release on a single hotdog prop ---
# --- Stage 3: mouth scoring trigger ---
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

# Reference head size for the shared (skin-independent) mouth-scoring
# trigger's own position/size math below — NOT the visual head size anymore
# (see SKIN_DEFS/_setup_head_skin: the old giant CSG placeholder head is
# gone now that a skin is always shown — see _ready). Derived from the
# Jamaican Sprinter's own head bbox half-width (0.115) at its own scale
# (1.34, see SKIN_DEFS): 0.115 * 1.34 ≈ 0.154.
const HEAD_RADIUS := 0.154

# Half the previous version's ratio (was implicitly 0.675/1.575 ≈ 0.4286) —
# per feedback, a smaller/harder scoring target at the same relative
# position. Feeds MOUTH_RADIUS_RATIO below, which both this generic trigger
# AND each skin's own visual mouth-hole (_apply_head_mouth_hole) use against
# THEIR OWN measured head size — so this one change shrinks both, everywhere.
const MOUTH_RADIUS := HEAD_RADIUS * 0.2143

# How far past the front opening a hotdog's center must travel before it
# counts as a score — placing the trigger volume itself this deep (rather
# than right at the rim, or tracking depth-traveled over time) means simply
# entering the trigger already implies clearing this depth, so a low-speed
# graze along the mouth's edge can't register.
const MOUTH_SCORE_DEPTH := MOUTH_RADIUS * 1.5

# Vertical placement of the mouth within the head: a fraction of the way up
# the head's own diameter, measured from the bottom — 0.25 instead of the
# geometric center (0.5), which is what actually reads as a mouth rather
# than an eye/nose-height hole. Expressed as a local Y offset FROM THE
# HEAD'S CENTER (negative = below center) so both the placeholder CSG
# mouth and the mouth-scoring trigger can share the exact same formula.
const MOUTH_HEIGHT_FRACTION := 0.25
const MOUTH_Y_OFFSET := (MOUTH_HEIGHT_FRACTION - 0.5) * 2.0 * HEAD_RADIUS

# Mouth radius as a fraction of the head's own radius — kept as an explicit
# ratio (not just the two raw constants) so a skin's mouth hole (see
# SKIN_DEFS / _apply_head_mouth_hole) can reproduce the exact same
# proportions on a completely different head mesh, measured from ITS OWN
# head size rather than this game's HEAD_RADIUS.
const MOUTH_RADIUS_RATIO := MOUTH_RADIUS / HEAD_RADIUS

const UPPER_ARM_LEN := 0.35
const FOREARM_LEN := 0.32
const UPPER_ARM_RADIUS := 0.055
const FOREARM_RADIUS := 0.05
const HAND_RADIUS := 0.05
const HAND_LEN := 0.05
const MAX_REACH := UPPER_ARM_LEN + FOREARM_LEN

const GRAB_RADIUS := 0.08

# --- "One avatar instance" layout ----------------------------------------
#
# Head, body, and arms all share the SAME per-skin scale (SKIN_DEFS
# "scale", reused directly for the head/body transform too — see
# _setup_head_skin) instead of the old giant-head/tiny-arm split. These
# position constants are derived from the Jamaican Sprinter rig's own
# measured bone positions at THAT skin's own scale (MAX_REACH /
# (0.28 + 0.22) = 1.34 — confirmed via the same headless bone-inspection
# script used for the original per-skin scale numbers):
#   hips (waist) local y = 1.0
#   head bbox center local y ≈ 1.7275
#   upperarm_L/R local origin ≈ (±0.24, 1.46, 0)
# Not pixel-perfect for the Joey Chestnut skin (its own scale, 1.1932, is
# slightly different) — same kind of minor cross-skin mismatch that already
# existed for head sizing before.

# Waist height doubles as the table height — literally the avatar's own hip
# bone, scaled (1.34 * 1.0).
const TABLE_TOP_Y := 1.34

# Flat table (no funnels/slopes — see _setup_table_and_pyramids), sized to
# comfortably span both arms' reach circles (MAX_REACH from each of the
# ± SHOULDER_POS.x positions below) with some margin.
const TABLE_SIZE := Vector3(2.0, TABLE_TOP_Y, 1.2)
const TABLE_POS := Vector3(0, TABLE_TOP_Y * 0.5, 0)

# Head attachment point — HEAD_POS.y is the avatar's own head-bbox-center,
# scaled, measured up from the same hip reference as TABLE_TOP_Y:
# 1.34 + 1.34*(1.7275 - 1.0).
const HEAD_POS := Vector3(0, 2.31, 0)

# Shoulder position MUST match the rig's own "upperarm" bone origin exactly
# (scaled, relative to HEAD_POS the same way TABLE_TOP_Y is relative to the
# hip) — _update_arm_skin_pose overrides that bone's position directly to
# arm.shoulder_pos every tick (confirmed by reading that function), so any
# mismatch here is a visible seam between the live-posed arm and the static
# torso, not just a feel/reach tweak.
const SHOULDER_POS := Vector3(-0.32, 1.96, 0.0)
# Second arm is a straight mirror of the first across x=0.
const RIGHT_SHOULDER_POS := Vector3(-SHOULDER_POS.x, SHOULDER_POS.y, SHOULDER_POS.z)

# Single shared pyramid, centered between both hands and within comfortable
# reach of each shoulder — no more funnels; a hotdog knocked off the table's
# edge is simply despawned and replaced (see _respawn_hotdog_chain_if_lost).
const PYRAMID_CENTER := Vector3(0, TABLE_TOP_Y, SHOULDER_POS.z + 0.4)

const HOTDOG_RADIUS := 0.045
const HOTDOG_LEN := 0.22

# Stage 4: each hotdog is a short chain of capsule segments on soft-limited
# joints (a rope-like ragdoll), not one rigid capsule — so it visibly bends
# when thrown or bounced, per the design doc. Segment radius matches the old
# single-capsule HOTDOG_RADIUS; segment length is chosen so the whole chain's
# length still lands close to the old HOTDOG_LEN.
const HOTDOG_SEGMENTS := 3
const HOTDOG_SEGMENT_RADIUS := 0.045
const HOTDOG_SEGMENT_LEN := 0.07
const HOTDOG_JOINT_LIMIT_DEG := 22.0

const PYRAMID_ROWS := [4, 3, 2, 1]
const PYRAMID_TOTAL := 10

# Stage 5: no timer — untimed until this many points, then a scene transition.
const WIN_SCORE := 10

# Placeholder beeps, per the doc ("basic sound cues... placeholder beeps are
# fine initially") — synthesized procedurally so the project doesn't need
# any external audio assets, distinguished only by pitch/length per cue.
const BOUNCE_SOUND_COOLDOWN_MS := 150
const BOUNCE_SOUND_MIN_SPEED := 0.6

const HAND_OPEN_COLOR := Color(0.95, 0.75, 0.6)
const HAND_CLOSED_COLOR := Color(0.85, 0.5, 0.35)

# Cosmetic "skins" — a rigged .glb overlaid on the invisible physics
# scaffolding (capsules stay the actual simulated bodies; the skin is purely
# visual, driven by posing its skeleton's bones each tick to match the
# physics arm segments). A skin is ALWAYS active (see _ready) — F2 cycles
# between these two only, there's no "no skin" placeholder mode anymore.
#
# Bone mapping is per-skin since naming conventions vary between rigs.
# Screen-left ("left_arm_bones") is this game's own screen-space left,
# which is the CHARACTER's anatomical right (see the file header comment on
# camera mirroring) — for a rig using the same "_L"/"_R" suffix convention
# as this one, that means screen-left maps to the rig's "_R" bones.
#
# "scale" maps the source rig's own rest-pose arm reach (shoulder to wrist)
# onto this game's MAX_REACH, computed here from the jamaican-sprinter rig's
# own measured rest bone lengths (upperarm_L: 0.28, forearm_L: 0.22,
# confirmed via a headless bone-inspection script before writing this), not
# a guess. Per the "one avatar instance" redesign, this SAME scale is now
# also reused directly for the head + body (see _setup_head_skin) — no more
# separate, much-larger "head_scale" field.
const SKIN_DEFS := [
	{
		"name": "Jamaican Sprinter",
		"glb_path": "res://skins/jamaican-sprinter-rigged.glb",
		"left_arm_bones": {"upper": "upperarm_R", "fore": "forearm_R", "hand": "hand_R"},
		"right_arm_bones": {"upper": "upperarm_L", "fore": "forearm_L", "hand": "hand_L"},
		"head_bone": "head",
		"hide_root_bone": "hips",
		"scale": MAX_REACH / (0.28 + 0.22),
	},
	{
		"name": "Joey Chestnut",
		"glb_path": "res://skins/joey-chestnut-nathans-rigged.glb",
		# This rig's own convention is "L"/"R" with no underscore
		# (upperarmL, not upperarm_L) — confirmed via the same headless
		# bone-inspection approach used for the sprinter rig. Same
		# screen-left/anatomical-right mirroring as that rig too.
		"left_arm_bones": {"upper": "upperarmR", "fore": "lowerarmR", "hand": "handR"},
		"right_arm_bones": {"upper": "upperarmL", "fore": "lowerarmL", "hand": "handL"},
		"head_bone": "head",
		"hide_root_bone": "hips",
		# Measured rest bone lengths (upperarmL: 0.30, lowerarmL: 0.26) via
		# the same headless bone-inspection approach as the sprinter rig
		# above.
		"scale": MAX_REACH / (0.30 + 0.26),
	},
]

# Thruster-style target control — deliberately floaty by design; see the
# arm-control section of the design doc for why this shouldn't be "fixed"
# with heavier damping.
const TARGET_DAMPING := 0.992

# The following are tunable live from the on-screen slider panel (see
# _setup_tuning_ui) — they're `var`s with these as just the starting values,
# not `const`s, so player-side tuning doesn't require touching code at all.
var _target_accel: float = 650.0

# How many recent physics ticks of hand velocity a throw can draw its peak
# from (see _release_held_hotdog) — confirmed via diagnostic that target
# gravity + damping alone bleed hand speed from ~2.0 down to ~0.5 within
# under half a second of releasing the movement key, well before a player
# can realistically also reach the separate release key. 16 ticks (~0.27s
# at the default 60Hz) covers a realistic reaction gap without letting a
# throw be "pre-charged" and released long after — tunable rather than a
# fixed guess, since the right amount of forgiveness here is a feel call.
var _throw_velocity_samples: float = 16.0

# Multiplies the peak velocity a throw uses at release — a hotdog released
# "at 1 m/s" actually flies at 3x that, same direction. Makes throws feel
# more forceful than the arm's own (deliberately floaty/weak) motion would
# otherwise produce; tunable since the right amount of extra oomph is a
# feel call, not a physical fact.
var _release_velocity_multiplier: float = 3.0

# Reflecting off the head's own collision using Jolt's default material
# response reads as "hitting a wall" rather than a clear bounce (and,
# confirmed via earlier diagnostic, isn't even usable directly — by the time
# the collision signal fires, the default response has already killed most
# of the incoming speed). Scripted instead: on the FIRST contact tick with
# the head (see _on_hotdog_segment_body_entered), reflect the segment's
# incoming velocity across the local "away from head center" direction — a
# real bounce, not just a shove — then scale it by this restitution. Since
# the mouth is a genuine hole in the head's collision (no contact fires
# there at all), this only ever triggers on the solid parts of the skull, so
# a trajectory aimed AT the mouth just sails through untouched, while one
# that clips the rim gets redirected — sometimes off into space, sometimes
# straight into the opening, exactly the "make it or bounce out" feel a
# hoop-toss goal should have.
var _head_bounce_restitution: float = 0.65

# PD spring driving the hand toward the target. Damping is set to ~40% of
# critical damping (2*sqrt(stiffness*mass)) for this stiffness/mass, which
# is the "fluid but bouncy" regime (visible overshoot, a couple of settling
# oscillations) rather than either robotically snapping (ratio ~1) or
# wobbling forever (ratio <0.15). See godot_ragdoll_physics_reference.md.
var _hand_spring_stiffness: float = 48.0
var _hand_spring_damping: float = 3.5

# The shoulder used to ALSO be a script-driven torque spring, independently
# aiming the upper arm's pointing direction at the target — removed (see
# reference_arm_physics_demo.html, which has no equivalent mechanism at
# all: its upper-arm direction is a pure byproduct of where the hand ends
# up, not something separately driven). With both the hand spring AND that
# torque converging on the same target, the whole chain tended to
# straighten out; now only the hand is actively driven, and the upper arm's
# orientation comes purely from what the elbow/wrist joints transmit back
# from that pull plus gravity — same free-hanging treatment as the elbow.
# The wrist stays passive too (just its existing hard angular limit) — an
# earlier attempt at an active wrist spring fought that limit badly enough
# to peg the hand's angular velocity at an engine safety ceiling; not worth
# chasing down further given how minor the wrist's motion range is.

# Arm segments get a bit of extra gravity_scale on top of the engine default
# so a released/undriven arm visibly sags — but not so much that the spring
# above can no longer lift it (see _hand_spring_stiffness).
var _arm_gravity_scale: float = 1.2

# The shoulder and elbow both have genuinely zero angular limit, so this is
# now the ONLY thing damping their spin at all (previously the shoulder's
# own align-torque spring also corrected its pointing direction, though
# never its roll). Lowered from 8.0 now that nothing else is damping the
# shoulder — trying for more of the reference demo's visible overshoot/
# wobble — but kept well above 0, since a truly undamped free shoulder
# idled in a persistent low-level spin indefinitely rather than settling
# (confirmed in earlier testing).
var _arm_angular_damp: float = 4.0

# Gravity on the CONTROL TARGET itself, not just the physical arm. Without
# this, letting go of all keys leaves the target frozen at whatever height
# it last had, and a spring strong enough to actually lift the arm (see
# _hand_spring_stiffness) is then also strong enough to hold it there against
# gravity almost perfectly — the arm would never fall when idle. This makes
# the target itself sink when not being actively held up, same as the arm.
var _target_gravity: float = 9.8

# Camera tilted down to look over the tabletop (per feedback: "tilted
# forwards about 30 degrees so you can see the whole tabletop") instead of
# the old level, straight-on shot — see _setup_camera. Vertical frame now
# spans from a bit in front of the table's near edge up to a bit above the
# head, so the table + torso + head fill most of the frame; refined by eye
# via render iteration, not meant to be exact to the pixel.
const CAMERA_FOV_DEG := 45.0
const CAMERA_TILT_DEG := 30.0
const FRAME_BOTTOM_Y := TABLE_TOP_Y - 0.5
const FRAME_TOP_Y := HEAD_POS.y + 0.6

var _rest_dir: Vector3 = Vector3(0, -0.15, 1).normalized()

## All per-arm state, so the exact same construction/driving/reset code runs
## for both arms instead of being duplicated — each instance owns one arm's
## bodies, joints, control target, and input action names.
class ArmState:
	var shoulder_pos: Vector3
	var input_prefix: String

	var upper_arm: RigidBody3D
	var forearm: RigidBody3D
	var hand: RigidBody3D
	var hand_mesh: MeshInstance3D
	var elbow_joint: HingeJoint3D

	var held_segment: RigidBody3D = null
	var held_hotdog_id: int = -1
	var grab_joint: Generic6DOFJoint3D = null

	var target_pos: Vector3
	var target_vel: Vector3 = Vector3.ZERO

	# Rolling window of recent hand velocity, so a throw can use the PEAK
	# speed from the last ~1/6 second rather than whatever the hand's
	# velocity happens to be at the exact instant release is pressed — see
	# _release_held_hotdog for why this matters.
	var hand_velocity_history: Array[Vector3] = []

	var rest_transforms: Dictionary = {}

	# Skin (see SKIN_DEFS): null when no skin is active on this arm.
	var skin_root: Node3D = null
	var skin_skeleton: Skeleton3D = null
	var skin_bone_idx: Dictionary = {}
	var skin_rest_dirs: Dictionary = {}
	var skin_scale: float = 1.0

var _arm_left: ArmState
var _arm_right: ArmState

## The skin head's own collision StaticBody3D (see _setup_head_skin) — the
## old giant CSG placeholder head is gone (a skin is always shown now, see
## _ready), so this is what _on_hotdog_segment_body_entered's head-bounce
## check compares against.
var _head_collision_body: StaticBody3D = null

var _arm_material: PhysicsMaterial
var _hotdog_material: PhysicsMaterial
var _environment_material: PhysicsMaterial

# Hotdog pyramid bookkeeping: each chain is a small array of connected
# capsule segments; a segment's index into _hotdog_chains is stashed in its
# own metadata so grab/score handlers can find "which hotdog is this part
# of" from just the RigidBody3D a signal handed them.
var _hotdog_chains: Array = []
var _hotdog_chain_joints: Array = []
var _hotdogs_remaining: int = 0

# Each hotdog segment's linear_velocity as of the START of the current
# physics tick, before that tick's collision response can alter it — see
# _on_hotdog_segment_body_entered for why the signal's own reported
# velocity is unusable for a scripted head-bounce.
var _pre_collision_velocity: Dictionary = {}

var _score: int = 0
var _score_label: Label
var _game_won: bool = false

var _grab_sound: AudioStreamPlayer
var _throw_sound: AudioStreamPlayer
var _bounce_sound: AudioStreamPlayer
var _score_sound: AudioStreamPlayer
var _last_bounce_sound_time: int = -1000000

var _debug_enabled: bool = false
var _debug_nodes: Array[Node3D] = []

# 0 = no skin (primitives visible); 1..SKIN_DEFS.size() = SKIN_DEFS[index-1].
var _current_skin_index: int = 0
var _head_skin_root: Node3D = null
var _skin_label: Label

func _ready() -> void:
	_setup_input_actions()
	_setup_materials()
	_setup_sounds()
	_setup_environment()
	_setup_lighting()
	_setup_ground()
	_setup_mouth_trigger()
	_arm_left = _setup_arm(SHOULDER_POS, "left_arm_")
	_arm_right = _setup_arm(RIGHT_SHOULDER_POS, "right_arm_")
	_setup_table_and_pyramids()
	_setup_camera()
	_setup_controls_ui()
	_setup_score_ui()
	_setup_skin_ui()
	_setup_tuning_ui()
	# Always show an avatar — no more "no skin" primitive placeholder mode
	# (see _cycle_skin/_apply_skin).
	_apply_skin(1)

func _setup_materials() -> void:
	# Starting values kept low — bounce compounds with the active hand
	# spring on every contact, so what looks like a modest restitution value
	# can still grow bounce height over repeated hits rather than settling.
	# All three are live-editable from the tuning panel (see _setup_tuning_ui).
	_arm_material = _physics_material(0.15, 0.2)
	_hotdog_material = _physics_material(0.08, 0.35)
	_environment_material = _physics_material(0.15, 0.2)

func _setup_sounds() -> void:
	_grab_sound = _make_sound_player(_make_beep_stream(440.0, 0.08))
	_throw_sound = _make_sound_player(_make_beep_stream(660.0, 0.1))
	_bounce_sound = _make_sound_player(_make_beep_stream(220.0, 0.06))
	_score_sound = _make_sound_player(_make_beep_stream(880.0, 0.25))

func _make_sound_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player

## Synthesizes a short sine-wave beep as 16-bit mono PCM — no external audio
## assets needed for these placeholder cues. A short linear fade in/out
## avoids the harsh click a hard-edged tone would otherwise have at the
## start and end of playback.
func _make_beep_stream(freq: float, duration: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var fade_time := 0.01
	for i in range(sample_count):
		var t := float(i) / mix_rate
		var envelope := minf(1.0, minf(t / fade_time, (duration - t) / fade_time))
		var sample := sin(TAU * freq * t) * envelope
		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _setup_input_actions() -> void:
	var bindings := {
		"left_arm_y_pos": KEY_W,
		"left_arm_y_neg": KEY_S,
		"left_arm_x_neg": KEY_A,
		"left_arm_x_pos": KEY_D,
		"left_arm_z_neg": KEY_Q,
		"left_arm_z_pos": KEY_E,
		"left_arm_release": KEY_SHIFT,
		"right_arm_y_pos": KEY_I,
		"right_arm_y_neg": KEY_K,
		"right_arm_x_neg": KEY_J,
		"right_arm_x_pos": KEY_L,
		"right_arm_z_neg": KEY_U,
		"right_arm_z_pos": KEY_O,
		"right_arm_release": KEY_SPACE,
		"reset_arms": KEY_R,
		"toggle_debug": KEY_F1,
		"cycle_skin": KEY_F2,
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

func _setup_mouth_trigger() -> void:
	var trigger := Area3D.new()
	trigger.name = "MouthScoreTrigger"
	trigger.set_collision_mask_value(LAYER_HOTDOG, true)
	trigger.body_entered.connect(_on_mouth_trigger_body_entered)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = MOUTH_RADIUS * 0.8
	shape.shape = sphere
	trigger.add_child(shape)

	# Same local offset as the mouth cutout itself, but pushed back along
	# the head's front-facing axis (+Z) by MOUTH_SCORE_DEPTH — the front
	# opening is at roughly local z = HEAD_RADIUS, so this sits that far
	# past it, inside the tunnel rather than right at the rim.
	trigger.position = HEAD_POS + Vector3(0, MOUTH_Y_OFFSET, HEAD_RADIUS - MOUTH_SCORE_DEPTH)
	add_child(trigger)

	var trigger_debug := _make_wire_sphere(sphere.radius)
	trigger_debug.position = trigger.position
	add_child(trigger_debug)
	_debug_nodes.append(trigger_debug)

func _on_mouth_trigger_body_entered(body: Node) -> void:
	if not (body is RigidBody3D):
		return
	var hotdog_id: int = body.get_meta("hotdog_id", -1)
	if hotdog_id == -1:
		return
	# Blocks scoring while ANY segment of this hotdog is still held by
	# either hand — matches the doc's "must release/throw it in" rule
	# rather than letting the player just push a held hotdog into the mouth.
	if hotdog_id == _arm_left.held_hotdog_id or hotdog_id == _arm_right.held_hotdog_id:
		return
	_score_hotdog(hotdog_id)

func _score_hotdog(hotdog_id: int) -> void:
	_score += 1
	_score_label.text = "Score: %d / %d" % [_score, WIN_SCORE]
	_score_sound.play()
	for joint in _hotdog_chain_joints[hotdog_id]:
		if is_instance_valid(joint):
			joint.queue_free()
	for seg in _hotdog_chains[hotdog_id]:
		if is_instance_valid(seg):
			seg.queue_free()
	_hotdog_chains[hotdog_id] = []
	_hotdog_chain_joints[hotdog_id] = []
	_hotdogs_remaining -= 1

	if _score >= WIN_SCORE:
		_on_win()
		return

	if _hotdogs_remaining <= 0:
		_restock_pyramids()

## Untimed — the game just runs until WIN_SCORE, then hands off to a
## placeholder next scene. That scene's real content isn't decided yet; this
## is just the transition hook so it's easy to swap out later.
func _on_win() -> void:
	# Stops _physics_process from touching this scene's bodies on later
	# frames while the transition is pending — change_scene_to_file frees
	# the current scene at end-of-frame, not instantly, and without this
	# guard the arm-driving code below kept firing on already-freed nodes
	# on the next physics tick (confirmed via diagnostic: "apply force
	# without a physics space" errors immediately after the winning score).
	_game_won = true
	get_tree().change_scene_to_file("res://scenes/next_level.tscn")

func _setup_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "MainCamera"
	camera.current = true
	camera.fov = CAMERA_FOV_DEG
	camera.keep_aspect = Camera3D.KEEP_HEIGHT

	var frame_height := FRAME_TOP_Y - FRAME_BOTTOM_Y
	var center_y := (FRAME_TOP_Y + FRAME_BOTTOM_Y) * 0.5
	var distance := (frame_height * 0.5) / tan(deg_to_rad(CAMERA_FOV_DEG * 0.5))

	# Tilted down CAMERA_TILT_DEG (see that constant) instead of the old
	# level shot — the camera sits back and UP from the look-at point along
	# the tilted axis, so pitching down still keeps the same framed subject
	# in view rather than just rotating away from it.
	var look_at_target := Vector3(0, center_y, PYRAMID_CENTER.z * 0.5)
	var tilt_rad := deg_to_rad(CAMERA_TILT_DEG)
	var back_dir := Vector3(0, sin(tilt_rad), cos(tilt_rad))
	camera.position = look_at_target + back_dir * distance
	add_child(camera)
	camera.look_at(look_at_target, Vector3.UP)

func _setup_controls_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ControlsUI"

	var label := Label.new()
	label.text = "Left arm — W/S: up/down   A/D: left/right   Q/E: back/forward   Left Shift: release\nRight arm — I/K: up/down   J/L: left/right   U/O: back/forward   Space: release\nR: reset arms   F1: toggle debug view   F2: cycle skin"
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)

	add_child(layer)

func _setup_score_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ScoreUI"

	_score_label = Label.new()
	_score_label.text = "Score: 0 / %d" % WIN_SCORE
	_score_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_score_label.position = Vector2(12, -40)
	_score_label.add_theme_font_size_override("font_size", 20)
	_score_label.add_theme_color_override("font_color", Color.WHITE)
	_score_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_score_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_score_label)

	add_child(layer)

func _setup_skin_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SkinUI"

	_skin_label = Label.new()
	_skin_label.text = "Skin: None (F2 to cycle)"
	_skin_label.position = Vector2(12, 88)
	_skin_label.add_theme_font_size_override("font_size", 16)
	_skin_label.add_theme_color_override("font_color", Color.WHITE)
	_skin_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_skin_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_skin_label)

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
	_add_slider(box, "Arm gravity scale", 0.0, 3.0, 0.1, _arm_gravity_scale, func(v):
		_arm_gravity_scale = v
		for arm in [_arm_left, _arm_right]:
			arm.upper_arm.gravity_scale = v
			arm.forearm.gravity_scale = v
			arm.hand.gravity_scale = v
	)
	_add_slider(box, "Arm angular damp", 0.0, 20.0, 0.5, _arm_angular_damp, func(v):
		_arm_angular_damp = v
		for arm in [_arm_left, _arm_right]:
			arm.upper_arm.angular_damp = v
			arm.forearm.angular_damp = v
			arm.hand.angular_damp = v
	)
	_add_slider(box, "Target gravity", 0.0, 20.0, 0.5, _target_gravity, func(v): _target_gravity = v)
	_add_slider(box, "Target accel", 100.0, 1200.0, 10.0, _target_accel, func(v): _target_accel = v)
	_add_slider(box, "Throw velocity window", 1.0, 40.0, 1.0, _throw_velocity_samples, func(v): _throw_velocity_samples = v)
	_add_slider(box, "Release velocity multiplier", 1.0, 8.0, 0.25, _release_velocity_multiplier, func(v): _release_velocity_multiplier = v)
	_add_slider(box, "Head bounce restitution", 0.0, 1.5, 0.05, _head_bounce_restitution, func(v): _head_bounce_restitution = v)
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

## Frosted-glass-style translucent material for the table/funnel surfaces —
## per feedback, rather than shrinking the funnel slope's own reach (real
## risk of undoing already-tuned "does a toss roll back" behavior), the
## table itself becomes see-through so a skin's giant body (deliberately
## sized to match its head, see _setup_body_skin) stays visible extending
## down through it instead of being hidden behind opaque terrain. High
## roughness (rather than a smooth/clear glass look) is what reads as
## "frosted" — a diffuse, foggy translucency instead of a sharp see-through.
func _frosted_material(color: Color, alpha: float = 0.35) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	material.metallic = 0.0
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

func _setup_arm(shoulder_pos: Vector3, input_prefix: String) -> ArmState:
	var arm := ArmState.new()
	arm.shoulder_pos = shoulder_pos
	arm.input_prefix = input_prefix

	var elbow_pos := shoulder_pos + _rest_dir * UPPER_ARM_LEN
	var wrist_pos := elbow_pos + _rest_dir * FOREARM_LEN

	var rest_basis := _basis_from_axis(_rest_dir)

	arm.upper_arm = _make_capsule_body("UpperArm", UPPER_ARM_RADIUS, UPPER_ARM_LEN + UPPER_ARM_RADIUS * 2.0, 1.2, Color(0.85, 0.6, 0.45), _arm_material)
	arm.upper_arm.global_transform = Transform3D(rest_basis, shoulder_pos + _rest_dir * (UPPER_ARM_LEN * 0.5))
	arm.upper_arm.gravity_scale = _arm_gravity_scale
	arm.upper_arm.angular_damp = _arm_angular_damp
	arm.upper_arm.set_collision_layer_value(LAYER_ARM, true)
	arm.upper_arm.set_collision_mask_value(LAYER_GROUND, true)
	arm.upper_arm.set_collision_mask_value(LAYER_FACE, true)
	arm.upper_arm.set_collision_mask_value(LAYER_TABLE, true)
	arm.upper_arm.set_collision_mask_value(LAYER_HOTDOG, true)
	add_child(arm.upper_arm)

	arm.forearm = _make_capsule_body("Forearm", FOREARM_RADIUS, FOREARM_LEN + FOREARM_RADIUS * 2.0, 0.8, Color(0.85, 0.6, 0.45), _arm_material)
	arm.forearm.global_transform = Transform3D(rest_basis, elbow_pos + _rest_dir * (FOREARM_LEN * 0.5))
	arm.forearm.gravity_scale = _arm_gravity_scale
	arm.forearm.angular_damp = _arm_angular_damp
	arm.forearm.set_collision_layer_value(LAYER_ARM, true)
	arm.forearm.set_collision_mask_value(LAYER_GROUND, true)
	arm.forearm.set_collision_mask_value(LAYER_FACE, true)
	arm.forearm.set_collision_mask_value(LAYER_TABLE, true)
	arm.forearm.set_collision_mask_value(LAYER_HOTDOG, true)
	add_child(arm.forearm)

	arm.hand = _make_capsule_body("Hand", HAND_RADIUS, HAND_LEN + HAND_RADIUS * 2.0, 0.4, Color(0.95, 0.75, 0.6), _arm_material)
	arm.hand.global_transform = Transform3D(rest_basis, wrist_pos + _rest_dir * (HAND_LEN * 0.5 + HAND_RADIUS))
	arm.hand.gravity_scale = _arm_gravity_scale
	arm.hand.angular_damp = _arm_angular_damp
	arm.hand.set_collision_layer_value(LAYER_HAND, true)
	arm.hand.set_collision_mask_value(LAYER_GROUND, true)
	arm.hand.set_collision_mask_value(LAYER_FACE, true)
	arm.hand.set_collision_mask_value(LAYER_TABLE, true)
	arm.hand.set_collision_mask_value(LAYER_HOTDOG, true)
	add_child(arm.hand)
	arm.hand_mesh = arm.hand.get_node("Mesh")

	var grab_area := Area3D.new()
	grab_area.name = "GrabArea"
	grab_area.set_collision_mask_value(LAYER_HOTDOG, true)
	var grab_shape := CollisionShape3D.new()
	var grab_sphere := SphereShape3D.new()
	grab_sphere.radius = GRAB_RADIUS
	grab_shape.shape = grab_sphere
	grab_area.add_child(grab_shape)
	grab_area.body_entered.connect(_on_grab_area_body_entered.bind(arm))
	arm.hand.add_child(grab_area)

	# Shoulder: Generic6DOFJoint3D, node_a left unset. Under Jolt (this
	# project's physics engine), an unassigned joint slot resolves to world —
	# the opposite convention from GodotPhysics — so this alone anchors the
	# joint to a fixed point in space without a separate static anchor body.
	var shoulder_joint := Generic6DOFJoint3D.new()
	add_child(shoulder_joint)
	shoulder_joint.global_transform = Transform3D(rest_basis, shoulder_pos)
	shoulder_joint.node_b = shoulder_joint.get_path_to(arm.upper_arm)
	shoulder_joint.exclude_nodes_from_collision = true
	_configure_6dof(shoulder_joint, -1.0)

	# Elbow: HingeJoint3D, hinge axis = world X (the joint's local Z axis).
	# Deliberately no angle limit and no motor — a free hinge the upper arm
	# and forearm swing through on their own momentum/gravity/collisions,
	# same as the shoulder's own unrestricted joint. Only the hinge's
	# position (elbow_pos, the pivot between the two segments) is fixed;
	# nothing constrains or drives the angle around it.
	arm.elbow_joint = HingeJoint3D.new()
	add_child(arm.elbow_joint)
	arm.elbow_joint.global_transform = Transform3D(_basis_from_axis(Vector3.RIGHT), elbow_pos)
	arm.elbow_joint.node_a = arm.elbow_joint.get_path_to(arm.upper_arm)
	arm.elbow_joint.node_b = arm.elbow_joint.get_path_to(arm.forearm)
	arm.elbow_joint.exclude_nodes_from_collision = true

	# Wrist: Generic6DOFJoint3D, linear locked but now free on all angular
	# axes too (previously a 30-degree cone) — that limit meant the hand
	# could only ever point within 30 degrees of wherever the forearm
	# itself happened to be aimed, and since nothing now actively steers
	# the forearm's own orientation (the elbow is a free hinge too), the
	# whole arm tended to hang/extend in one narrow range of directions,
	# making hotdogs that needed an awkward approach angle (e.g. toward
	# the back of a funnel) effectively unreachable. Same treatment as the
	# elbow: the joint still fixes the wrist's POSITION, only the angle
	# around it is unconstrained.
	var wrist_joint := Generic6DOFJoint3D.new()
	add_child(wrist_joint)
	wrist_joint.global_transform = Transform3D(rest_basis, wrist_pos)
	wrist_joint.node_a = wrist_joint.get_path_to(arm.forearm)
	wrist_joint.node_b = wrist_joint.get_path_to(arm.hand)
	wrist_joint.exclude_nodes_from_collision = true
	_configure_6dof(wrist_joint, -1.0)

	arm.target_pos = shoulder_pos + _rest_dir * (MAX_REACH * 0.7)

	arm.rest_transforms = {
		"upper_arm": arm.upper_arm.global_transform,
		"forearm": arm.forearm.global_transform,
		"hand": arm.hand.global_transform,
		"target": arm.target_pos,
	}

	_setup_debug_visuals(arm)
	return arm

## Just a flat table now — no funnels/slopes (see the "one avatar instance"
## redesign doc comment near TABLE_TOP_Y): a single shared pyramid spawns at
## PYRAMID_CENTER, and a hotdog knocked off the table's edge is despawned and
## replaced rather than chased/pulled back (see
## _respawn_hotdog_chain_if_lost) — there being no funnel to roll into
## anymore, "pull it back" doesn't have anywhere meaningful to pull it to.
func _setup_table_and_pyramids() -> void:
	var table := CSGBox3D.new()
	table.name = "Table"
	table.size = TABLE_SIZE
	table.use_collision = true
	table.collision_layer = 0
	table.set_collision_layer_value(LAYER_TABLE, true)
	table.material = _frosted_material(Color(0.5, 0.35, 0.22))
	table.position = TABLE_POS
	add_child(table)

	_restock_pyramids()

## Builds one capsule-chain hotdog (see HOTDOG_SEGMENTS etc.) centered at the
## given world position, with each segment tagged with its chain index so
## grab/score handlers can identify "which hotdog is this part of" from just
## the RigidBody3D a signal handed them. Returns that chain index.
func _make_hotdog_chain(center: Vector3) -> int:
	var hotdog_id := _hotdog_chains.size()
	var chain_dir := Vector3.RIGHT
	var chain_basis := _basis_from_axis(chain_dir)
	var total_len := HOTDOG_SEGMENTS * HOTDOG_SEGMENT_LEN
	var start_offset := -total_len * 0.5 + HOTDOG_SEGMENT_LEN * 0.5

	var segments: Array[RigidBody3D] = []
	for i in range(HOTDOG_SEGMENTS):
		var seg_center := center + chain_dir * (start_offset + i * HOTDOG_SEGMENT_LEN)
		var seg := _make_capsule_body("HotdogSeg", HOTDOG_SEGMENT_RADIUS, HOTDOG_SEGMENT_LEN + HOTDOG_SEGMENT_RADIUS * 2.0, 0.05, Color(0.75, 0.35, 0.25), _hotdog_material)
		seg.global_transform = Transform3D(chain_basis, seg_center)
		# Same rationale as the old single-capsule hotdog: a smooth capsule
		# has almost no rolling resistance from friction alone, so without
		# extra angular damping a single knock sends it rolling forever.
		seg.angular_damp = 3.0
		seg.set_collision_layer_value(LAYER_HOTDOG, true)
		seg.set_collision_mask_value(LAYER_GROUND, true)
		seg.set_collision_mask_value(LAYER_TABLE, true)
		seg.set_collision_mask_value(LAYER_ARM, true)
		seg.set_collision_mask_value(LAYER_HAND, true)
		seg.set_collision_mask_value(LAYER_FACE, true)
		seg.set_meta("hotdog_id", hotdog_id)
		# Contact monitoring drives the placeholder "bounce" sound cue — a
		# global cooldown plus a minimum speed (rather than per-segment
		# state) keeps a settling pyramid of dozens of segments from turning
		# into a machine-gun of retriggered beeps.
		seg.contact_monitor = true
		seg.max_contacts_reported = 4
		seg.body_entered.connect(_on_hotdog_segment_body_entered.bind(seg))
		add_child(seg)

		# Cosmetic bun piece, per the design doc: non-colliding, no joints,
		# just a child mesh riding along with this segment's own transform
		# automatically (no per-frame follow code needed). Offset to one
		# side rather than fully enclosing, "open-faced" like a real bun.
		var bun := MeshInstance3D.new()
		var bun_mesh := CapsuleMesh.new()
		bun_mesh.radius = HOTDOG_SEGMENT_RADIUS * 1.4
		bun_mesh.height = HOTDOG_SEGMENT_LEN + HOTDOG_SEGMENT_RADIUS * 1.6
		bun.mesh = bun_mesh
		bun.material_override = _material(Color(0.85, 0.65, 0.35))
		bun.position = Vector3(0, 0, HOTDOG_SEGMENT_RADIUS * 0.9)
		seg.add_child(bun)

		segments.append(seg)

	var joints: Array[Generic6DOFJoint3D] = []
	for i in range(HOTDOG_SEGMENTS - 1):
		var joint := Generic6DOFJoint3D.new()
		add_child(joint)
		var joint_pos := (segments[i].global_position + segments[i + 1].global_position) * 0.5
		joint.global_transform = Transform3D(chain_basis, joint_pos)
		joint.node_a = joint.get_path_to(segments[i])
		joint.node_b = joint.get_path_to(segments[i + 1])
		joint.exclude_nodes_from_collision = true
		# Some angular give so the chain visibly bends/flops (per the doc),
		# but still limited so it can't fold in half or self-intersect.
		_configure_6dof(joint, HOTDOG_JOINT_LIMIT_DEG)
		joints.append(joint)

	_hotdog_chains.append(segments)
	_hotdog_chain_joints.append(joints)
	return hotdog_id

## Lays out PYRAMID_TOTAL hotdog chains in a 4-3-2-1 stacked pyramid (rows
## spreading along Z, layers stacking up in Y) on the flat table, centered at
## the given point — spawned directly in their resting arrangement rather
## than dropped from height, so nothing overlaps at spawn and the pyramid
## settles gently.
func _spawn_pyramid(center: Vector3) -> void:
	var pitch_z := HOTDOG_SEGMENT_RADIUS * 2.0 * 1.05
	var pitch_y := HOTDOG_SEGMENT_RADIUS * 2.0 * 0.87
	var base_y := center.y + 0.03 + HOTDOG_SEGMENT_RADIUS
	for row in range(PYRAMID_ROWS.size()):
		var count: int = PYRAMID_ROWS[row]
		for i in range(count):
			var z := (float(i) - float(count - 1) * 0.5) * pitch_z
			var y := base_y + row * pitch_y
			_make_hotdog_chain(Vector3(center.x, y, center.z + z))

func _restock_pyramids() -> void:
	_spawn_pyramid(PYRAMID_CENTER)
	_hotdogs_remaining = PYRAMID_TOTAL

## A hotdog knocked off the table's edge is despawned and replaced rather
## than chased/pulled back — there's no funnel/wall to catch it in this flat-
## table version (see _setup_table_and_pyramids), so "well below the table"
## unambiguously means lost. Same cleanup _score_hotdog already does for a
## scored chain, plus a fresh one spawned back at the pile — doesn't touch
## _hotdogs_remaining/_score, since this isn't a scoring event.
func _respawn_hotdog_chain_if_lost(chain_index: int) -> void:
	var chain: Array = _hotdog_chains[chain_index]
	if chain.is_empty():
		return
	var lead: RigidBody3D = chain[0]
	if not is_instance_valid(lead) or lead.global_position.y > TABLE_TOP_Y - 0.5:
		return
	for joint in _hotdog_chain_joints[chain_index]:
		if is_instance_valid(joint):
			joint.queue_free()
	for seg in chain:
		if is_instance_valid(seg):
			seg.queue_free()
	_hotdog_chains[chain_index] = []
	_hotdog_chain_joints[chain_index] = []
	_make_hotdog_chain(PYRAMID_CENTER + Vector3(0, 0.1, 0))

func _on_grab_area_body_entered(body: Node, arm: ArmState) -> void:
	if arm.held_segment != null:
		return
	if not (body is RigidBody3D):
		return
	var hotdog_id: int = body.get_meta("hotdog_id", -1)
	if hotdog_id == -1:
		return
	_grab_hotdog(arm, body as RigidBody3D, hotdog_id)

func _grab_hotdog(arm: ArmState, segment: RigidBody3D, hotdog_id: int) -> void:
	arm.held_segment = segment
	arm.held_hotdog_id = hotdog_id

	# Snap the WHOLE chain by the same rigid delta (not just the grabbed
	# segment) so the grabbed link lines up exactly with the hand while
	# every inter-segment joint keeps zero slack — moving only the grabbed
	# segment would instantly violate its neighbors' zero-play linear limit
	# and pop the chain apart.
	var delta := arm.hand.global_transform * segment.global_transform.affine_inverse()
	for seg in _hotdog_chains[hotdog_id]:
		seg.global_transform = delta * seg.global_transform
		seg.linear_velocity = Vector3.ZERO
		seg.angular_velocity = Vector3.ZERO

	arm.grab_joint = Generic6DOFJoint3D.new()
	add_child(arm.grab_joint)
	arm.grab_joint.global_transform = arm.hand.global_transform
	arm.grab_joint.node_a = arm.grab_joint.get_path_to(arm.hand)
	arm.grab_joint.node_b = arm.grab_joint.get_path_to(segment)
	arm.grab_joint.exclude_nodes_from_collision = true
	_configure_6dof(arm.grab_joint, 5.0)

	arm.hand_mesh.material_override = _material(HAND_CLOSED_COLOR)
	_grab_sound.play()

func _record_hand_velocity(arm: ArmState) -> void:
	arm.hand_velocity_history.append(arm.hand.linear_velocity)
	while arm.hand_velocity_history.size() > int(_throw_velocity_samples):
		arm.hand_velocity_history.pop_front()

func _peak_hand_velocity(arm: ArmState) -> Vector3:
	var best := Vector3.ZERO
	for v in arm.hand_velocity_history:
		if v.length() > best.length():
			best = v
	return best

func _release_held_hotdog(arm: ArmState) -> void:
	if arm.held_segment == null:
		return
	# Uses the PEAK velocity from the last THROW_VELOCITY_SAMPLES ticks,
	# not the hand's exact velocity at this instant — confirmed via
	# diagnostic that a real swing-then-release play pattern (let go of
	# the movement key, THEN reach for the separate release key) loses
	# most of its speed to target gravity/damping in well under half a
	# second, before the player can physically press release. Without
	# this, a swing that clearly built up real speed a moment earlier
	# still throws with almost none. Then scaled up by
	# _release_velocity_multiplier (same direction, just faster) since the
	# arm's own motion alone reads as too weak to throw with.
	var release_velocity := _peak_hand_velocity(arm) * _release_velocity_multiplier
	# Applied to EVERY segment of the chain, not just the held one —
	# confirmed via diagnostic that setting only the held segment's
	# velocity doesn't survive the next physics step: the hotdog's own
	# inter-segment joints (zero linear play, permanent, separate from the
	# grab joint) immediately average that one segment's boosted velocity
	# against its still-slow neighbors, and the whole chain ends up well
	# below the intended speed within a single tick.
	for seg in _hotdog_chains[arm.held_hotdog_id]:
		if is_instance_valid(seg):
			seg.linear_velocity = release_velocity
			seg.angular_velocity = arm.hand.angular_velocity
	arm.grab_joint.queue_free()
	arm.grab_joint = null
	arm.held_segment = null
	arm.held_hotdog_id = -1
	arm.hand_mesh.material_override = _material(HAND_OPEN_COLOR)
	_throw_sound.play()

## Fires on any hotdog-segment collision. Two independent things happen
## here: a scripted bounce off the head's solid skull (see
## _head_bounce_restitution for why this can't just be a physics material),
## and the placeholder "bounce" sound cue, gated by a single GLOBAL cooldown
## (not per-segment) so a whole pyramid settling at once can't turn into a
## machine-gun of beeps.
func _on_hotdog_segment_body_entered(body: Node, segment: RigidBody3D) -> void:
	if body == _head_collision_body:
		var away := segment.global_position - HEAD_POS
		if away.length() > 0.001:
			var normal := away.normalized()
			# NOT segment.linear_velocity — confirmed via diagnostic that by
			# the time this signal fires, Jolt has already run this tick's
			# collision response against the head's un-tunable default
			# material and killed almost all of the incoming speed (an
			# actual ~4 m/s impact showed up here as ~0.2-0.4 m/s), so
			# reflecting that would produce a barely-visible nudge instead
			# of a real bounce. _pre_collision_velocity holds each segment's
			# velocity from the START of this same physics tick (set in
			# _physics_process, which always runs before the physics step
			# that triggers this signal), i.e. the true pre-impact velocity.
			var v: Vector3 = _pre_collision_velocity.get(segment, segment.linear_velocity)
			segment.linear_velocity = (v - 2.0 * v.dot(normal) * normal) * _head_bounce_restitution

	if segment.linear_velocity.length() < BOUNCE_SOUND_MIN_SPEED:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bounce_sound_time < BOUNCE_SOUND_COOLDOWN_MS:
		return
	_last_bounce_sound_time = now
	_bounce_sound.play()

# --- Skins ----------------------------------------------------------------
#
# A skin overlays a rigged .glb's mesh on top of the invisible physics
# scaffolding (the capsules stay the actual simulated bodies and keep their
# collision; only their cosmetic "Mesh" child gets hidden). Each arm's three
# relevant bones (upper/fore/hand) are posed every physics tick via
# Skeleton3D.set_bone_global_pose_override to match that arm's capsules; the
# head bone gets one fixed pose at setup time since the head never moves.
#
# The whole rest of the rig (torso, legs, the OTHER arm) is hidden by
# collapsing a single ancestor bone ("hide_root_bone", e.g. "hips") to a
# near-zero scale — confirmed via an isolated bone-posing test that an
# explicitly-overridden DESCENDANT bone still renders normally at its own
# override transform regardless of an ancestor's collapsed override, which
# is exactly what makes "show only this one arm chain" possible from a
# single full-body skinned mesh without any actual mesh editing.

## A skin is always active — no "no skin" state to cycle through anymore
## (see _ready) — so this just wraps around the two entries in SKIN_DEFS.
func _cycle_skin() -> void:
	_apply_skin((_current_skin_index % SKIN_DEFS.size()) + 1)

func _apply_skin(index: int) -> void:
	_teardown_skin()
	_current_skin_index = index

	var def: Dictionary = SKIN_DEFS[index - 1]
	_set_primitives_visible(false)
	_setup_arm_skin(_arm_left, def, def["left_arm_bones"])
	_setup_arm_skin(_arm_right, def, def["right_arm_bones"])
	_setup_head_skin(def, _arm_left.skin_skeleton)
	_skin_label.text = "Skin: %s (F2 to cycle)" % def["name"]

func _teardown_skin() -> void:
	for arm in [_arm_left, _arm_right]:
		if arm.skin_root:
			arm.skin_root.queue_free()
			arm.skin_root = null
			arm.skin_skeleton = null
			arm.skin_bone_idx = {}
			arm.skin_rest_dirs = {}
			arm.skin_scale = 1.0
	_head_collision_body = null
	if _head_skin_root:
		_head_skin_root.queue_free()
		_head_skin_root = null

func _set_primitives_visible(is_visible: bool) -> void:
	for arm in [_arm_left, _arm_right]:
		arm.upper_arm.get_node("Mesh").visible = is_visible
		arm.forearm.get_node("Mesh").visible = is_visible
		arm.hand.get_node("Mesh").visible = is_visible

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

## Accumulates a bone's REST transform (parent-relative) up its whole parent
## chain to get its rest pose in the skeleton's own space — used to measure
## the rig's own rest-pose "arm direction" per bone (see _compute_rest_dirs)
## and, for the head, to keep its natural rest orientation when relocating it.
func _bone_global_rest(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	var chain := []
	var idx := bone_idx
	while idx >= 0:
		chain.push_front(idx)
		idx = skeleton.get_bone_parent(idx)
	var accum := Transform3D.IDENTITY
	for b in chain:
		accum = accum * skeleton.get_bone_rest(b)
	return accum

## For each of upper/fore/hand, the direction (in that BONE'S OWN rest-local
## frame) the rig's rest pose points "down the limb" toward the next joint —
## this is the fixed reference we rotate at runtime to match wherever our
## physics capsule currently points (see _pose_skin_bone). The hand has no
## child bone to measure toward, so it reuses the forearm's own direction as
## a reasonable proxy (a common convention: the hand roughly continues the
## forearm's rest-pose pointing direction).
func _compute_rest_dirs(skeleton: Skeleton3D, bones: Dictionary) -> Dictionary:
	var upper_idx: int = skeleton.find_bone(bones["upper"])
	var fore_idx: int = skeleton.find_bone(bones["fore"])
	var hand_idx: int = skeleton.find_bone(bones["hand"])

	var upper_rest := _bone_global_rest(skeleton, upper_idx)
	var fore_rest := _bone_global_rest(skeleton, fore_idx)
	var hand_rest := _bone_global_rest(skeleton, hand_idx)

	var upper_dir_world := (fore_rest.origin - upper_rest.origin).normalized()
	var fore_dir_world := (hand_rest.origin - fore_rest.origin).normalized()

	return {
		"upper": upper_rest.basis.inverse() * upper_dir_world,
		"fore": fore_rest.basis.inverse() * fore_dir_world,
		"hand": fore_rest.basis.inverse() * fore_dir_world,
	}

func _setup_arm_skin(arm: ArmState, def: Dictionary, bones: Dictionary) -> void:
	var packed: PackedScene = load(def["glb_path"])
	var inst := packed.instantiate()
	add_child(inst)

	var skeleton := _find_skeleton(inst)
	arm.skin_root = inst
	arm.skin_skeleton = skeleton
	arm.skin_scale = float(def["scale"])

	var tiny := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), Vector3.ZERO)
	skeleton.set_bone_global_pose_override(skeleton.find_bone(def["hide_root_bone"]), tiny, 1.0, true)

	arm.skin_bone_idx = {
		"upper": skeleton.find_bone(bones["upper"]),
		"fore": skeleton.find_bone(bones["fore"]),
		"hand": skeleton.find_bone(bones["hand"]),
	}
	arm.skin_rest_dirs = _compute_rest_dirs(skeleton, bones)

## Unlike the arms, the head never moves dynamically in this game, so it
## doesn't need to stay a live skinned mesh at all — a plain positioned
## MeshInstance3D, set once, does the job (see _extract_bone_weighted_mesh).
##
## source_skeleton is an ALREADY-instantiated skeleton — in practice one of
## the two arm skins' own — deliberately reused here rather than instancing
## this glb a third time. Confirmed via bisection across several diagnostic
## renders that a THIRD live instance of the same skinned scene corrupts
## rendering somewhere entirely unrelated to anything this function does
## with it afterward (symptoms varied run to run — a large wrongly-shaped
## mass, or the whole scene going black — and a minimal instantiate-and-
## add_child-only reproduction, with no bone/mesh logic at all, showed it
## too). Since only mesh/bone-rest DATA is needed here, not a live scene of
## its own, reading it off an instance that already exists sidesteps the
## bug rather than working around its symptoms.
func _setup_head_skin(def: Dictionary, source_skeleton: Skeleton3D) -> void:
	var head_idx := source_skeleton.find_bone(def["head_bone"])
	var head_rest := _bone_global_rest(source_skeleton, head_idx)
	# Same scale as the arms — "one avatar instance" means head, body, and
	# arms are all one consistently-scaled character, not an independently
	# oversized head (see SKIN_DEFS).
	var head_scale := float(def["scale"])

	var source_mesh_inst := _find_mesh_instance(source_skeleton)
	var bbox := _measure_bone_weighted_aabb(source_mesh_inst.mesh, head_idx)
	var head_mesh := _extract_bone_weighted_mesh(source_mesh_inst.mesh, head_idx)

	if head_mesh.get_surface_count() == 0:
		return

	var static_inst := MeshInstance3D.new()
	static_inst.mesh = head_mesh
	# Anchor on the head MESH's own bounding-box center, not the head
	# BONE's rest origin — a rig's head bone sits near the jaw/chin (this
	# one's rest origin is at the very bottom of the head's own AABB, not
	# its middle), so anchoring on the bone origin mapped the chin, not the
	# center, onto HEAD_POS and left the whole head floating too high.
	var anchor_local := bbox.position + bbox.size * 0.5
	var scaled_basis := head_rest.basis.scaled(Vector3.ONE * head_scale)
	static_inst.transform = Transform3D(scaled_basis, HEAD_POS - scaled_basis * anchor_local)
	add_child(static_inst)
	_head_skin_root = static_inst

	# Head collision — the old giant CSG placeholder head is gone (a skin is
	# always shown now), so hotdogs need something right-sized to bounce off
	# for the "goal" mechanic (see _on_hotdog_segment_body_entered). Same
	# convex-hull-on-LAYER_FACE treatment as the body below.
	var head_static := StaticBody3D.new()
	head_static.name = "SkinHeadCollision"
	head_static.collision_layer = 0
	head_static.set_collision_layer_value(LAYER_FACE, true)
	head_static.physics_material_override = _environment_material
	var head_coll := CollisionShape3D.new()
	head_coll.shape = head_mesh.create_convex_shape(true, false)
	head_static.add_child(head_coll)
	static_inst.add_child(head_static)
	_head_collision_body = head_static

	_setup_body_skin(def, source_skeleton, source_mesh_inst.mesh, head_idx, static_inst)

	if bbox.size != Vector3.ZERO:
		_apply_head_mouth_hole(static_inst, bbox, head_scale)

## Gives the floating head an actual body — everything but the head and
## arms (see _extract_body_mesh) from the SAME source mesh, in the SAME
## bind-pose coordinate space, added as a CHILD of the head's own
## MeshInstance3D with an identity local transform, so it inherits that
## exact same scaled_basis/HEAD_POS-anchored transform rather than getting
## an independently derived one — head and body read as the same avatar
## instance at the same scale, just showing more of it below the neck,
## instead of a separately-resized statue bolted on underneath (freeing
## _head_skin_root in _teardown_skin cleans this up too, no separate
## tracking var needed). Also builds a matching STATIC collision hull (a
## convex hull, not a concave trimesh — a hand-built concave shape gave zero
## collision response under Jolt in earlier testing) on LAYER_FACE, the same
## layer the head itself collides on, so hotdogs/arms already masked for
## that layer bounce off it with no extra collision-mask setup.
func _setup_body_skin(def: Dictionary, source_skeleton: Skeleton3D, source_mesh: Mesh, head_idx: int, head_mesh_inst: MeshInstance3D) -> void:
	var excluded_bones := [head_idx]
	for side_bones in [def["left_arm_bones"], def["right_arm_bones"]]:
		for key in ["upper", "fore", "hand"]:
			var idx := source_skeleton.find_bone(side_bones[key])
			if idx >= 0:
				excluded_bones.append(idx)

	var body_mesh := _extract_body_mesh(source_mesh, excluded_bones)
	if body_mesh.get_surface_count() == 0:
		return

	var body_mesh_inst := MeshInstance3D.new()
	body_mesh_inst.mesh = body_mesh
	head_mesh_inst.add_child(body_mesh_inst)

	var body_static := StaticBody3D.new()
	body_static.name = "SkinBody"
	body_static.collision_layer = 0
	body_static.set_collision_layer_value(LAYER_FACE, true)
	body_static.physics_material_override = _environment_material
	var body_coll := CollisionShape3D.new()
	body_coll.shape = body_mesh.create_convex_shape(true, false)
	body_static.add_child(body_coll)
	head_mesh_inst.add_child(body_static)

const MOUTH_HOLE_SHADER_CODE := "
shader_type spatial;
uniform vec3 mouth_center_world;
uniform float mouth_radius_world;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D base_texture : source_color;
uniform bool has_texture = false;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Paints the mouth region dark rather than discarding it — a discard
	// sphere centered near the face's front surface doesn't reach back
	// far enough to also discard the head's own back-interior wall, so it
	// only ever revealed a solid (if oddly shaded) patch of the mesh's own
	// inside rather than true background, confirmed via diagnostic render.
	if (distance(v_world_pos, mouth_center_world) < mouth_radius_world) {
		ALBEDO = vec3(0.02, 0.02, 0.02);
	} else if (has_texture) {
		// Some skins (Joey Chestnut) bake facial detail — eyes, mouth — into
		// a small textured surface rather than flat per-surface colors;
		// confirmed via diagnostic that this surface's own material has
		// albedo forced to flat white specifically because the texture is
		// meant to supply all of its actual color. Falling back to base_color
		// (as this shader originally did unconditionally) discarded that
		// texture entirely, rendering it as a blank white patch instead of a
		// face — sample it here instead, same as the un-shadered surfaces
		// already do natively.
		ALBEDO = texture(base_texture, UV).rgb;
	} else {
		ALBEDO = base_color.rgb;
	}
}
"

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null

## Bounding box, in the mesh's own bind-pose (pre-pose, object-local) space,
## of vertices weighted predominantly to one bone — measures a skin's own
## head size/shape at runtime rather than hardcoding per-skin numbers, so
## the mouth-hole placement below works unmodified for any similarly-rigged
## skin. Scans every surface, not just surface 0, since a multi-material
## mesh (like this rig's 5 material surfaces) can split head geometry
## across more than one.
func _measure_bone_weighted_aabb(mesh: Mesh, bone_idx: int, min_weight: float = 0.4) -> AABB:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	var found := false
	for surf in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.is_empty():
			continue
		var bones_per_vertex := bones.size() / verts.size()
		for i in range(verts.size()):
			for b in range(bones_per_vertex):
				var idx := i * bones_per_vertex + b
				if bones[idx] == bone_idx and weights[idx] >= min_weight:
					found = true
					min_v = min_v.min(verts[i])
					max_v = max_v.max(verts[i])
					break
	if not found:
		return AABB()
	return AABB(min_v, max_v - min_v)

## Shared triangle-copy machinery behind _extract_bone_weighted_mesh (a
## skin's head) and _extract_body_mesh (everything else — see
## _setup_head_skin) — builds a plain, non-skinned ArrayMesh containing just
## the triangles whose vertices all satisfy keep_vertex(vertex_index,
## bones_per_vertex, bones, weights). UVs are preserved (not just
## vertex/normal) — most surfaces here are flat-colored with no UVs that
## matter, but at least one (Joey Chestnut's face) bakes its actual detail
## into a texture, and losing UVs would leave that surface unsampleable.
func _extract_mesh_where(mesh: Mesh, keep_vertex: Callable) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surf in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		# A surface with no UVs at all reports this slot as null, not an
		# empty array (confirmed via diagnostic against the sprinter rig,
		# which has none) — the typed assignment below would otherwise fail.
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if verts.is_empty() or bones.is_empty():
			continue
		var bones_per_vertex := bones.size() / verts.size()

		var keep := PackedByteArray()
		keep.resize(verts.size())
		for i in range(verts.size()):
			keep[i] = 1 if keep_vertex.call(i, bones_per_vertex, bones, weights) else 0

		var tri_count := (indices.size() / 3) if not indices.is_empty() else (verts.size() / 3)
		var new_verts := PackedVector3Array()
		var new_normals := PackedVector3Array()
		var new_uvs := PackedVector2Array()
		for t in range(tri_count):
			var i0: int
			var i1: int
			var i2: int
			if indices.is_empty():
				i0 = t * 3
				i1 = t * 3 + 1
				i2 = t * 3 + 2
			else:
				i0 = indices[t * 3]
				i1 = indices[t * 3 + 1]
				i2 = indices[t * 3 + 2]
			if keep[i0] and keep[i1] and keep[i2]:
				new_verts.append(verts[i0])
				new_verts.append(verts[i1])
				new_verts.append(verts[i2])
				if not normals.is_empty():
					new_normals.append(normals[i0])
					new_normals.append(normals[i1])
					new_normals.append(normals[i2])
				if not uvs.is_empty():
					new_uvs.append(uvs[i0])
					new_uvs.append(uvs[i1])
					new_uvs.append(uvs[i2])

		if new_verts.is_empty():
			continue
		var new_arrays := []
		new_arrays.resize(Mesh.ARRAY_MAX)
		new_arrays[Mesh.ARRAY_VERTEX] = new_verts
		if not new_normals.is_empty():
			new_arrays[Mesh.ARRAY_NORMAL] = new_normals
		if not new_uvs.is_empty():
			new_arrays[Mesh.ARRAY_TEX_UV] = new_uvs
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(surf))
	return out

## Builds a plain, non-skinned ArrayMesh containing just the triangles
## whose vertices are predominantly weighted to one bone — used to pull a
## static copy of a skin's head geometry out of its full-body skinned
## mesh (see _setup_head_skin for why the head is rendered this way
## instead of staying a live skinned mesh like the arms).
func _extract_bone_weighted_mesh(mesh: Mesh, bone_idx: int, min_weight: float = 0.4) -> ArrayMesh:
	return _extract_mesh_where(mesh, func(i: int, bpv: int, bones: PackedInt32Array, weights: PackedFloat32Array) -> bool:
		var w := 0.0
		for b in range(bpv):
			if bones[i * bpv + b] == bone_idx:
				w += weights[i * bpv + b]
		return w >= min_weight
	)

## The complement of _extract_bone_weighted_mesh: everything NOT
## predominantly weighted to one of excluded_bones — used to pull a skin's
## torso+legs out as a separate static "body" beneath its head, excluding
## both the head bone (its own separate mesh, see above) and every arm bone
## (those stay a LIVE skinned mesh, posed each tick onto the physics arms —
## see _setup_arm_skin; a static copy of them here would just double up as
## a second, non-moving arm frozen in the rig's rest pose).
func _extract_body_mesh(mesh: Mesh, excluded_bones: Array) -> ArrayMesh:
	return _extract_mesh_where(mesh, func(i: int, bpv: int, bones: PackedInt32Array, weights: PackedFloat32Array) -> bool:
		var excluded_w := 0.0
		for b in range(bpv):
			if excluded_bones.has(bones[i * bpv + b]):
				excluded_w += weights[i * bpv + b]
		return excluded_w < 0.4
	)

## Marks the mouth on a skin's head mesh — the skinned-mesh equivalent of
## the placeholder head's CSG subtraction, since you can't boolean-
## subtract an arbitrary imported skinned mesh. A per-surface shader
## paints a world-space sphere near the mouth position dark (preserving
## each surface's own flat color everywhere else) rather than trying to
## discard through to the background — a discard sphere centered near the
## face's front surface doesn't reach back far enough to also discard the
## head's own back-interior wall, so it only ever revealed a solid patch
## of the mesh's own inside rather than true background (confirmed via
## diagnostic render), and a plain dark patch reads as a mouth well enough
## without needing to solve that. Position/size come from MEASURING the
## skin's own head mesh
## at runtime (see _measure_bone_weighted_aabb) and reusing this game's own
## mouth proportions (MOUTH_HEIGHT_FRACTION, MOUTH_RADIUS_RATIO) against
## that measurement — not a hardcoded per-skin number — so this works
## unmodified for any similarly-rigged skin (front = +Z is this whole
## skin system's existing convention, not a new one introduced here).
func _apply_head_mouth_hole(mesh_inst: MeshInstance3D, bbox: AABB, head_scale: float) -> void:
	var local_pos := Vector3(
		bbox.position.x + bbox.size.x * 0.5,
		bbox.position.y + bbox.size.y * MOUTH_HEIGHT_FRACTION,
		bbox.position.z + bbox.size.z * 0.9
	)
	var own_head_radius := bbox.size.x * 0.5
	var local_radius := own_head_radius * MOUTH_RADIUS_RATIO

	# mesh_inst.transform already maps this exact bind-pose space to world
	# (see _setup_head_skin), so the mouth point rides along automatically.
	var mouth_world: Vector3 = mesh_inst.global_transform * local_pos
	var mouth_radius_world := local_radius * head_scale

	for surf in range(mesh_inst.mesh.get_surface_count()):
		var shader := Shader.new()
		shader.code = MOUTH_HOLE_SHADER_CODE
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("mouth_center_world", mouth_world)
		mat.set_shader_parameter("mouth_radius_world", mouth_radius_world)
		var orig_mat := mesh_inst.mesh.surface_get_material(surf)
		var orig_color := Color.WHITE
		var orig_texture: Texture2D = null
		if orig_mat is BaseMaterial3D:
			orig_color = (orig_mat as BaseMaterial3D).albedo_color
			orig_texture = (orig_mat as BaseMaterial3D).albedo_texture
		mat.set_shader_parameter("base_color", orig_color)
		mat.set_shader_parameter("has_texture", orig_texture != null)
		if orig_texture != null:
			mat.set_shader_parameter("base_texture", orig_texture)
		mesh_inst.set_surface_override_material(surf, mat)

## Poses one arm's three skinned bones to match its physics capsules —
## rotation comes from rotating each bone's own rest-local "arm direction"
## (see _compute_rest_dirs) onto the capsule's current pointing direction
## (its local Y, by this project's own capsule-orientation convention),
## scaled by this skin's own arm scale (see the _setup_head_skin comment on
## why that scale has to be baked into the override basis, not inst.scale);
## origin is that joint's actual current position, not the capsule's own
## center (a bone's origin is the PROXIMAL joint, confirmed by comparing the
## rig's measured rest bone positions against its own parent chain).
func _update_arm_skin_pose(arm: ArmState) -> void:
	if arm.skin_skeleton == null:
		return
	var skeleton := arm.skin_skeleton
	var to_local := skeleton.global_transform.affine_inverse()
	var scale_vec := Vector3.ONE * arm.skin_scale

	var upper_basis := arm.upper_arm.global_transform.basis
	var elbow_pos := arm.upper_arm.global_position + upper_basis.y * (UPPER_ARM_LEN * 0.5)
	var upper_rot := Basis(Quaternion(arm.skin_rest_dirs["upper"], upper_basis.y.normalized())).scaled(scale_vec)
	skeleton.set_bone_global_pose_override(arm.skin_bone_idx["upper"], to_local * Transform3D(upper_rot, arm.shoulder_pos), 1.0, true)

	var fore_basis := arm.forearm.global_transform.basis
	var wrist_pos := arm.forearm.global_position + fore_basis.y * (FOREARM_LEN * 0.5)
	var fore_rot := Basis(Quaternion(arm.skin_rest_dirs["fore"], fore_basis.y.normalized())).scaled(scale_vec)
	skeleton.set_bone_global_pose_override(arm.skin_bone_idx["fore"], to_local * Transform3D(fore_rot, elbow_pos), 1.0, true)

	var hand_basis := arm.hand.global_transform.basis
	var hand_rot := Basis(Quaternion(arm.skin_rest_dirs["hand"], hand_basis.y.normalized())).scaled(scale_vec)
	skeleton.set_bone_global_pose_override(arm.skin_bone_idx["hand"], to_local * Transform3D(hand_rot, wrist_pos), 1.0, true)

# --- Per-frame control ---------------------------------------------------

func _physics_process(delta: float) -> void:
	if _game_won:
		return

	if Input.is_action_just_pressed("toggle_debug"):
		_debug_enabled = not _debug_enabled
		for node in _debug_nodes:
			node.visible = _debug_enabled

	if Input.is_action_just_pressed("reset_arms"):
		_reset_arms()
		return

	if Input.is_action_just_pressed("cycle_skin"):
		_cycle_skin()

	for chain in _hotdog_chains:
		for seg in chain:
			if is_instance_valid(seg):
				# Snapshot BEFORE this tick's physics step resolves any new
				# collision — see _on_hotdog_segment_body_entered/
				# _pre_collision_velocity for why the signal itself can't be
				# trusted for this.
				_pre_collision_velocity[seg] = seg.linear_velocity
	for i in range(_hotdog_chains.size()):
		_respawn_hotdog_chain_if_lost(i)

	_process_arm(_arm_left, delta)
	_process_arm(_arm_right, delta)

func _process_arm(arm: ArmState, delta: float) -> void:
	if Input.is_action_just_pressed(arm.input_prefix + "release"):
		_release_held_hotdog(arm)

	var accel := Vector3.ZERO
	if Input.is_action_pressed(arm.input_prefix + "y_pos"):
		accel.y += _target_accel
	if Input.is_action_pressed(arm.input_prefix + "y_neg"):
		accel.y -= _target_accel
	if Input.is_action_pressed(arm.input_prefix + "x_neg"):
		accel.x -= _target_accel
	if Input.is_action_pressed(arm.input_prefix + "x_pos"):
		accel.x += _target_accel
	if Input.is_action_pressed(arm.input_prefix + "z_neg"):
		accel.z -= _target_accel
	if Input.is_action_pressed(arm.input_prefix + "z_pos"):
		accel.z += _target_accel

	accel.y -= _target_gravity
	arm.target_vel += accel * delta
	arm.target_vel *= TARGET_DAMPING
	arm.target_pos += arm.target_vel * delta

	var offset := arm.target_pos - arm.shoulder_pos
	if offset.length() > MAX_REACH:
		var radial_dir := offset.normalized()
		arm.target_pos = arm.shoulder_pos + radial_dir * MAX_REACH
		# Drop only the outward component so the target doesn't keep
		# accumulating unbounded "phantom" velocity while pinned at the
		# reach limit — that pent-up velocity made direction changes feel
		# sluggish (and was overshooting into wild uncontrolled swings).
		var outward_vel := arm.target_vel.dot(radial_dir)
		if outward_vel > 0.0:
			arm.target_vel -= radial_dir * outward_vel

	var error := arm.target_pos - arm.hand.global_position
	var force := error * _hand_spring_stiffness - arm.hand.linear_velocity * _hand_spring_damping
	arm.hand.apply_central_force(force)

	_update_arm_skin_pose(arm)
	_record_hand_velocity(arm)

func _reset_arm(arm: ArmState) -> void:
	arm.upper_arm.global_transform = arm.rest_transforms["upper_arm"]
	arm.upper_arm.linear_velocity = Vector3.ZERO
	arm.upper_arm.angular_velocity = Vector3.ZERO
	arm.forearm.global_transform = arm.rest_transforms["forearm"]
	arm.forearm.linear_velocity = Vector3.ZERO
	arm.forearm.angular_velocity = Vector3.ZERO
	arm.hand.global_transform = arm.rest_transforms["hand"]
	arm.hand.linear_velocity = Vector3.ZERO
	arm.hand.angular_velocity = Vector3.ZERO
	arm.target_pos = arm.rest_transforms["target"]
	arm.target_vel = Vector3.ZERO

	if arm.held_segment != null:
		arm.grab_joint.queue_free()
		arm.grab_joint = null
		arm.held_segment = null
		arm.held_hotdog_id = -1
		arm.hand_mesh.material_override = _material(HAND_OPEN_COLOR)

func _reset_arms() -> void:
	_reset_arm(_arm_left)
	_reset_arm(_arm_right)

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

func _setup_debug_visuals(arm: ArmState) -> void:
	var reach_sphere := _make_wire_sphere(MAX_REACH)
	reach_sphere.position = arm.shoulder_pos
	add_child(reach_sphere)
	_debug_nodes.append(reach_sphere)

	# No elbow limit arc or wrist limit cone here anymore — both are now
	# free joints with no angle limit (see _setup_arm), so there's no
	# bound left to illustrate for either.

	# Hand grab radius, parented to the hand so it tracks automatically.
	var grab_sphere_debug := _make_wire_sphere(GRAB_RADIUS)
	arm.hand.add_child(grab_sphere_debug)
	_debug_nodes.append(grab_sphere_debug)
