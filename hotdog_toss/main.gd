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

const HEAD_RADIUS := 1.05 * 1.5
const MOUTH_RADIUS := 0.225 * 1.5 * 2.0

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

# Shoulder moved out from its original -0.3 by one original head length
# (2 * the pre-scale-up 0.35 head radius = 0.7), i.e. further from the head,
# then an additional 1/3 of the (now scaled-up) head radius further out
# still, so the shoulder clears the head with a visible gap instead of
# sitting inside its now much larger radius.
const SHOULDER_POS := Vector3(-1.0 - HEAD_RADIUS / 3.0, 1.4, 0.05)
# Second arm is a straight mirror of the first across x=0, matching the
# already-mirrored LEFT_PIT_POS/RIGHT_PIT_POS pair below.
const RIGHT_SHOULDER_POS := Vector3(-SHOULDER_POS.x, SHOULDER_POS.y, SHOULDER_POS.z)
const UPPER_ARM_LEN := 0.35
const FOREARM_LEN := 0.32
const UPPER_ARM_RADIUS := 0.055
const FOREARM_RADIUS := 0.05
const HAND_RADIUS := 0.05
const HAND_LEN := 0.05
const MAX_REACH := UPPER_ARM_LEN + FOREARM_LEN

const GRAB_RADIUS := 0.08

const TABLE_TOP_Y := 1.05
# Big floor now, not a small platform — footprint far bigger than the play
# area the camera actually frames, reading as effectively infinite.
const TABLE_SIZE := Vector3(20, TABLE_TOP_Y, 20)
const TABLE_POS := Vector3(0, TABLE_TOP_Y * 0.5, 0)

# Two funnel-shaped dips sloping down into small pits, one on each side next
# to where a hand naturally works — mirrored left/right of center so a
# missed or knocked-off hotdog rolls toward whichever hand is closer. Only
# the left arm exists so far, but the right pit is built now too, ready for
# the second arm (stage 4).
const PIT_RADIUS := 0.35
const PIT_DEPTH := 0.24
const DIP_OUTER_RADIUS := 0.9
const LEFT_PIT_POS := Vector3(SHOULDER_POS.x, TABLE_TOP_Y, 0.45)
const RIGHT_PIT_POS := Vector3(-SHOULDER_POS.x, TABLE_TOP_Y, 0.45)

# Beyond the small funnel (which handles the final approach into the pit
# itself), the WHOLE table now slants toward whichever pit is nearest, out
# to this much bigger radius — so a hotdog placed or tossed anywhere on the
# reachable table eventually rolls all the way in, not just near the rim.
# Depth is picked for a ~23 degree slope: comfortably above the ~15 degree
# angle of repose given the hotdog/table friction values (below that angle,
# friction alone can hold an object in place indefinitely regardless of how
# long the slope is — confirmed this matters via the small funnel needing a
# steeper re-tune earlier to actually reach the pit rather than stall
# partway), but NOT much more than that — a first pass at ~4 units of total
# relief sent a hotdog spawned near the middle rolling off-screen with far
# more speed than intended. Split at global x=0 (the midline between the
# two mirrored pits) so the two basins drain into their own pit rather than
# fighting each other in the overlap.
const LARGE_SLOPE_RADIUS := 6.0
const LARGE_SLOPE_DEPTH := 2.2

# Head center originally cleared the tabletop by a full head length (2 *
# HEAD_RADIUS) of gap plus the head's own radius; shifted down by one more
# head length (diameter, 2*HEAD_RADIUS) from that, per feedback that the
# head sat too high, then back up by half a head length (HEAD_RADIUS) once
# that turned out to sit too low (the skin head's own proportions extend
# further below center than the primitive sphere, overlapping the
# terrain) — net gap above the tabletop is now 2 * HEAD_RADIUS.
#
# Z is pushed back so the head's own FRONT surface (its +Z-facing edge,
# HEAD_RADIUS in front of center) lands exactly at the back edge of the
# small funnel (DIP_OUTER_RADIUS out from the pit center, on the -Z side) —
# the funnel itself, not the much bigger outer slope, since that's the
# part actually within arm's reach. Keeps the head from visually
# overlapping the depth range the arms actually work in.
const HEAD_POS := Vector3(0, TABLE_TOP_Y + HEAD_RADIUS + HEAD_RADIUS, LEFT_PIT_POS.z - DIP_OUTER_RADIUS - HEAD_RADIUS)

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

# Optional cosmetic "skins" — a rigged .glb overlaid on the invisible
# physics scaffolding (capsules stay the actual simulated bodies; the skin
# is purely visual, driven by posing its skeleton's bones each tick to
# match the physics arm segments). Index 0 in the cycle is always "no skin"
# (the default primitives); SKIN_DEFS holds everything past that.
#
# Bone mapping is per-skin since naming conventions vary between rigs.
# Screen-left ("left_arm_bones") is this game's own screen-space left,
# which is the CHARACTER's anatomical right (see the file header comment on
# camera mirroring) — for a rig using the same "_L"/"_R" suffix convention
# as this one, that means screen-left maps to the rig's "_R" bones.
#
# "scale" maps the source rig's own rest-pose arm reach (shoulder to wrist)
# onto this game's MAX_REACH, so the skin's arm roughly matches how far the
# physics hand can actually travel — computed here from the jamaican-
# sprinter rig's own measured rest bone lengths (upperarm_L: 0.28,
# forearm_L: 0.22, confirmed via a headless bone-inspection script before
# writing this), not a guess.
const SKIN_DEFS := [
	{
		"name": "Jamaican Sprinter",
		"glb_path": "res://skins/jamaican-sprinter-rigged.glb",
		"left_arm_bones": {"upper": "upperarm_R", "fore": "forearm_R", "hand": "hand_R"},
		"right_arm_bones": {"upper": "upperarm_L", "fore": "forearm_L", "hand": "hand_L"},
		"head_bone": "head",
		"hide_root_bone": "hips",
		"scale": MAX_REACH / (0.28 + 0.22),
		# The head gets its OWN, much larger scale (applied only to the
		# head skin instance, not the arms) — matched to this game's
		# deliberately oversized cartoon head rather than the arm-reach
		# scale above, which would otherwise leave a realistically-tiny
		# head floating next to arm-scaled proportions. 0.22 is the source
		# rig's own head size (a near-cube, measured via a headless
		# vertex-bounds inspection of the vertices weighted to the "head"
		# bone: local AABB size (0.21, 0.23, 0.22)), so this maps that
		# measured size onto this game's head diameter (2 * HEAD_RADIUS).
		"head_scale": (2.0 * HEAD_RADIUS) / 0.22,
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
		# Measured local AABB of vertices weighted to the "head" bone:
		# (0.281, 0.302, 0.300) — close enough to a cube that, same as the
		# sprinter rig, one averaged dimension stands in for a single
		# "head diameter".
		"head_scale": (2.0 * HEAD_RADIUS) / 0.294,
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

# A gentle horizontal spring pulling anything within a funnel's outer
# radius (DIP_OUTER_RADIUS) toward that pit's exact XZ center — the slope
# and flat pit floor alone reliably get a settling hotdog CLOSE to center
# (confirmed via earlier diagnostic) but not necessarily to the exact
# bottom, and a resting arm segment can find complex stuck configurations
# on the slope that friction alone won't resolve (a multi-joint chain
# draped across a curved surface, unlike a single hotdog capsule). This
# force is scaled by distance from center like a real spring, so it's
# naturally zero right at the target point rather than needing a deadzone,
# and is gentle enough that a player actively driving the hand nearby
# (spring stiffness ~48) isn't fighting it in any noticeable way.
var _funnel_center_pull_strength: float = 3.0

# CSGShape3D (the head) has no physics_material_override slot (confirmed
# earlier — setting it there is a hard error), so a hotdog hitting the
# solid skull otherwise bounces with whatever Jolt's engine-default
# restitution happens to be, which reads as "hitting a wall" rather than a
# clear bounce. Scripted instead: on the FIRST contact tick with the head
# (see _on_hotdog_segment_body_entered), reflect the segment's incoming
# velocity across the local "away from head center" direction — a real
# bounce, not just a shove — then scale it by this restitution. Since the
# mouth is a genuine hole in the CSG collision (no contact fires there at
# all), this only ever triggers on the solid parts of the skull, so a
# trajectory aimed AT the mouth just sails through untouched, while one that
# clips the rim gets redirected — sometimes off into space, sometimes
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

var _head_visual: Node3D

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
	_setup_head()
	_setup_mouth_trigger()
	_arm_left = _setup_arm(SHOULDER_POS, "left_arm_")
	_arm_right = _setup_arm(RIGHT_SHOULDER_POS, "right_arm_")
	_setup_table_and_pyramids()
	_setup_table_walls()
	_setup_camera()
	_setup_controls_ui()
	_setup_score_ui()
	_setup_skin_ui()
	_setup_tuning_ui()

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
	mouth.position = Vector3(0, MOUTH_Y_OFFSET, 0)
	head.add_child(mouth)

	add_child(head)
	_head_visual = head

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

	camera.position = Vector3(0, center_y, distance)
	add_child(camera)
	camera.look_at(Vector3(0, center_y, 0), Vector3.UP)

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
	_add_slider(box, "Funnel center pull", 0.0, 15.0, 0.5, _funnel_center_pull_strength, func(v): _funnel_center_pull_strength = v)
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
	arm.upper_arm.contact_monitor = true
	arm.upper_arm.max_contacts_reported = 4
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
	arm.forearm.contact_monitor = true
	arm.forearm.max_contacts_reported = 4
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
	arm.hand.contact_monitor = true
	arm.hand.max_contacts_reported = 4
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

func _setup_table_and_pyramids() -> void:
	# CSG, not a plain box: a flat box's collision has no way to have a hole
	# in it, and simply overlaying the sloped funnel geometry on top isn't
	# enough on its own — the funnel dips BELOW the flat table's constant
	# height everywhere except right at its outer rim, so the still-present
	# flat table underneath stays the topmost surface and a hotdog never
	# actually reaches the slope (confirmed via diagnostic: it rested at
	# exactly flat-table height, not the lower sloped height). CSG's
	# use_collision generates real hole-having collision to match the
	# visual subtraction, which a hand-authored shape would have to
	# replicate manually anyway.
	var table := CSGBox3D.new()
	table.name = "Table"
	table.size = TABLE_SIZE
	table.use_collision = true
	table.collision_layer = 0
	table.set_collision_layer_value(LAYER_TABLE, true)
	table.material = _material(Color(0.5, 0.35, 0.22))
	# CSGShape3D has no physics_material_override (confirmed earlier on the
	# head — setting it there is a hard error), so this flat portion uses
	# engine-default bounce/friction; the funnel walls and pit floors below
	# (plain StaticBody3D, not CSG) still get the tuned _environment_material
	# where it actually matters for gameplay (the sloped/rolling surfaces).
	table.position = TABLE_POS

	for pit_pos in [LEFT_PIT_POS, RIGHT_PIT_POS]:
		var hole := CSGCylinder3D.new()
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		hole.radius = LARGE_SLOPE_RADIUS
		hole.height = TABLE_TOP_Y * 3.0
		hole.position = pit_pos - TABLE_POS
		table.add_child(hole)

	add_child(table)

	_make_funnel_pit(LEFT_PIT_POS)
	_make_funnel_pit(RIGHT_PIT_POS)
	_make_big_slope(LEFT_PIT_POS)
	_make_big_slope(RIGHT_PIT_POS)
	_setup_terrain_contours(LEFT_PIT_POS)
	_setup_terrain_contours(RIGHT_PIT_POS)

	_restock_pyramids()

## Four plain (invisible) StaticBody3D panels ringing the table's edge —
## nothing sits between the funnels and the table's own boundary (20x20,
## see TABLE_SIZE), so a hard throw or a big bounce off the big slope can
## otherwise send a hotdog sailing off the edge and falling forever, which
## reads as "lost the hotdog" rather than a bounce. These use the same
## tuned _environment_material as the rest of the terrain so they actually
## bounce hotdogs back toward play instead of just deadstopping them.
func _setup_table_walls() -> void:
	var walls := StaticBody3D.new()
	walls.name = "TableWalls"
	walls.collision_layer = 0
	walls.set_collision_layer_value(LAYER_TABLE, true)
	walls.physics_material_override = _environment_material

	var half_x := TABLE_SIZE.x * 0.5
	var half_z := TABLE_SIZE.z * 0.5
	var wall_thickness := 0.6
	# Tall enough to catch anything thrown with real force (release velocity
	# is tunable up to 8x peak hand speed) while staying well below the head,
	# which sits well above the table — see HEAD_POS.
	var wall_height := 6.0
	var wall_center_y := TABLE_TOP_Y + wall_height * 0.5

	var panels := [
		[Vector3(0, wall_center_y, half_z + wall_thickness * 0.5), Vector3(TABLE_SIZE.x + wall_thickness * 2.0, wall_height, wall_thickness)],
		[Vector3(0, wall_center_y, -half_z - wall_thickness * 0.5), Vector3(TABLE_SIZE.x + wall_thickness * 2.0, wall_height, wall_thickness)],
		[Vector3(half_x + wall_thickness * 0.5, wall_center_y, 0), Vector3(wall_thickness, wall_height, TABLE_SIZE.z + wall_thickness * 2.0)],
		[Vector3(-half_x - wall_thickness * 0.5, wall_center_y, 0), Vector3(wall_thickness, wall_height, TABLE_SIZE.z + wall_thickness * 2.0)],
	]
	for panel in panels:
		var coll := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = panel[1]
		coll.shape = box
		coll.position = panel[0]
		walls.add_child(coll)

	add_child(walls)

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
## spreading along Z, layers stacking up in Y) on the flat floor of the given
## pit — spawned directly in their resting arrangement rather than dropped
## from height, so nothing overlaps at spawn and the pyramid settles gently.
func _spawn_pyramid(pit_pos: Vector3) -> void:
	var pitch_z := HOTDOG_SEGMENT_RADIUS * 2.0 * 1.05
	var pitch_y := HOTDOG_SEGMENT_RADIUS * 2.0 * 0.87
	var base_y := pit_pos.y - PIT_DEPTH + 0.03 + HOTDOG_SEGMENT_RADIUS
	for row in range(PYRAMID_ROWS.size()):
		var count: int = PYRAMID_ROWS[row]
		for i in range(count):
			var z := (float(i) - float(count - 1) * 0.5) * pitch_z
			var y := base_y + row * pitch_y
			_make_hotdog_chain(Vector3(pit_pos.x, y, pit_pos.z + z))

func _restock_pyramids() -> void:
	_spawn_pyramid(LEFT_PIT_POS)
	_spawn_pyramid(RIGHT_PIT_POS)
	_hotdogs_remaining = PYRAMID_TOTAL * 2

## Builds one funnel-shaped dip: a sloped ring (DIP_OUTER_RADIUS, at the main
## table's height) down to a small flat pit (PIT_RADIUS, PIT_DEPTH lower) —
## overlaid directly on top of the flat table rather than actually cutting a
## hole in it, so a hotdog rolling near the pit meets the sloped surface
## first and never reaches the flat table underneath at that spot.
func _make_funnel_pit(pit_pos: Vector3) -> void:
	var container := Node3D.new()
	container.position = pit_pos
	add_child(container)

	var segments := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a1 := (float(i) / segments) * TAU
		var a2 := (float(i + 1) / segments) * TAU
		var outer1 := Vector3(cos(a1) * DIP_OUTER_RADIUS, 0.0, sin(a1) * DIP_OUTER_RADIUS)
		var outer2 := Vector3(cos(a2) * DIP_OUTER_RADIUS, 0.0, sin(a2) * DIP_OUTER_RADIUS)
		var inner1 := Vector3(cos(a1) * PIT_RADIUS, -PIT_DEPTH, sin(a1) * PIT_RADIUS)
		var inner2 := Vector3(cos(a2) * PIT_RADIUS, -PIT_DEPTH, sin(a2) * PIT_RADIUS)
		for tri in [[outer2, outer1, inner1], [inner2, outer2, inner1]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()

	var funnel_body := StaticBody3D.new()
	funnel_body.name = "FunnelWall"
	# collision_layer defaults to layer 1 already set — clear it first so
	# this body ends up on exactly LAYER_TABLE, not layer 1 AND LAYER_TABLE.
	funnel_body.collision_layer = 0
	funnel_body.set_collision_layer_value(LAYER_TABLE, true)
	funnel_body.physics_material_override = _environment_material

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = _material(Color(0.42, 0.29, 0.18))
	funnel_body.add_child(mesh_inst)

	# Collision is built from simple tilted BoxShape3D panels, NOT a
	# ConcavePolygonShape3D matching the visual mesh above — confirmed via
	# isolated diagnostic that a hand-built concave/trimesh shape here
	# provides no collision response at all under Jolt (a ball dropped onto
	# it free-fell straight through, reproduced at two different scales),
	# while the exact same slope built from primitive boxes works
	# correctly and a dropped ball visibly rolls toward the center as
	# intended. Visual mesh and collision proxy simply differ here, same as
	# the hotdog's cosmetic bun is meant to (per the original design doc).
	for i in range(segments):
		var mid := (float(i) + 0.5) / segments * TAU
		var outer_pt := Vector3(cos(mid) * DIP_OUTER_RADIUS, 0.0, sin(mid) * DIP_OUTER_RADIUS)
		var inner_pt := Vector3(cos(mid) * PIT_RADIUS, -PIT_DEPTH, sin(mid) * PIT_RADIUS)
		var panel_center := (outer_pt + inner_pt) * 0.5
		var radial_dir := (inner_pt - outer_pt).normalized()
		var tangent_dir := Vector3(-sin(mid), 0, cos(mid))
		var normal_dir := radial_dir.cross(tangent_dir).normalized()
		var panel_basis := Basis(tangent_dir, normal_dir, radial_dir)
		var panel_length := (inner_pt - outer_pt).length()
		var panel_width := (DIP_OUTER_RADIUS + PIT_RADIUS) * 0.5 * (TAU / segments) * 1.15

		var coll := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(panel_width, 0.03, panel_length)
		coll.shape = box
		coll.transform = Transform3D(panel_basis, panel_center)
		funnel_body.add_child(coll)
	container.add_child(funnel_body)

	var pit_floor := StaticBody3D.new()
	pit_floor.name = "PitFloor"
	pit_floor.collision_layer = 0
	pit_floor.set_collision_layer_value(LAYER_TABLE, true)
	pit_floor.physics_material_override = _environment_material
	pit_floor.position = Vector3(0, -PIT_DEPTH, 0)

	var floor_mesh_inst := MeshInstance3D.new()
	var floor_cyl := CylinderMesh.new()
	floor_cyl.top_radius = PIT_RADIUS
	floor_cyl.bottom_radius = PIT_RADIUS
	floor_cyl.height = 0.06
	floor_mesh_inst.mesh = floor_cyl
	floor_mesh_inst.material_override = _material(Color(0.32, 0.22, 0.14))
	pit_floor.add_child(floor_mesh_inst)

	var floor_coll := CollisionShape3D.new()
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = PIT_RADIUS
	floor_shape.height = 0.06
	floor_coll.shape = floor_shape
	pit_floor.add_child(floor_coll)
	container.add_child(pit_floor)

## Same radial-slope technique as _make_funnel_pit, extended out to
## LARGE_SLOPE_RADIUS so the whole table drains toward the pits, not just
## their immediate rims. Panels are clipped to global x on the same side as
## this pit — since the two pits are mirrored across x=0, that split IS the
## nearest-pit boundary, so the two basins drain into their own pit instead
## of overlapping and fighting each other. Meets the small funnel exactly
## at DIP_OUTER_RADIUS (same local height convention: 0 at that radius),
## so the two slopes join up continuously.
## Radius, along a given angle from this pit's own center, at which the
## cone would cross the seam (the vertical plane exactly between the two
## pits) — clamped to stay within [DIP_OUTER_RADIUS, LARGE_SLOPE_RADIUS] and
## nudged slightly past the exact crossing (SEAM_MARGIN) so neighboring
## panels' trimmed edges still touch with a hairline of overlap rather than
## risking a gap. Angles pointing away from the seam (or exactly along it)
## never cross, so they keep the full radius — this is what makes each
## pit's cone stop at the dividing line instead of extending across into
## the other cone and blocking sightlines through it.
func _slope_outer_radius(pit_offset_x: float, angle: float) -> float:
	const SEAM_MARGIN := 0.15
	var c := cos(angle)
	if c * pit_offset_x >= 0.0:
		return LARGE_SLOPE_RADIUS
	var r_cross := absf(pit_offset_x) / absf(c) + SEAM_MARGIN
	return clampf(r_cross, DIP_OUTER_RADIUS, LARGE_SLOPE_RADIUS)

func _make_big_slope(pit_pos: Vector3) -> void:
	var container := Node3D.new()
	container.position = pit_pos
	add_child(container)

	var segments := 40
	var seam_x := (LEFT_PIT_POS.x + RIGHT_PIT_POS.x) * 0.5
	var pit_offset_x := pit_pos.x - seam_x

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope_body := StaticBody3D.new()
	slope_body.name = "BigSlope"
	slope_body.collision_layer = 0
	slope_body.set_collision_layer_value(LAYER_TABLE, true)
	slope_body.physics_material_override = _environment_material

	for i in range(segments):
		var mid := (float(i) + 0.5) / segments * TAU
		var a1 := (float(i) / segments) * TAU
		var a2 := (float(i + 1) / segments) * TAU
		var outer_r_mid := _slope_outer_radius(pit_offset_x, mid)
		var outer_r1 := _slope_outer_radius(pit_offset_x, a1)
		var outer_r2 := _slope_outer_radius(pit_offset_x, a2)

		# The small funnel's own outer rim (DIP_OUTER_RADIUS) sits at LOCAL
		# height 0 (unmodified table height) — so for the two slopes to
		# connect continuously, THIS slope's inner edge must also be 0,
		# meaning its outer (far) edge has to be ELEVATED above baseline
		# and descend down TO baseline, not the reverse. Height at the
		# (possibly seam-trimmed) outer radius comes from the same shared
		# formula the contour rings use, so a trimmed panel's outer edge
		# still lands at the correct height for wherever it was cut off.
		var outer_pt := Vector3(cos(mid) * outer_r_mid, _terrain_height_at_radius(outer_r_mid), sin(mid) * outer_r_mid)
		var inner_pt := Vector3(cos(mid) * DIP_OUTER_RADIUS, 0.0, sin(mid) * DIP_OUTER_RADIUS)
		var outer1 := Vector3(cos(a1) * outer_r1, _terrain_height_at_radius(outer_r1), sin(a1) * outer_r1)
		var outer2 := Vector3(cos(a2) * outer_r2, _terrain_height_at_radius(outer_r2), sin(a2) * outer_r2)
		var inner1 := Vector3(cos(a1) * DIP_OUTER_RADIUS, 0.0, sin(a1) * DIP_OUTER_RADIUS)
		var inner2 := Vector3(cos(a2) * DIP_OUTER_RADIUS, 0.0, sin(a2) * DIP_OUTER_RADIUS)
		for tri in [[inner2, inner1, outer1], [outer2, inner2, outer1]]:
			for v in tri:
				st.add_vertex(v)

		var panel_center := (outer_pt + inner_pt) * 0.5
		var radial_dir := (inner_pt - outer_pt).normalized()
		var tangent_dir := Vector3(-sin(mid), 0, cos(mid))
		var normal_dir := radial_dir.cross(tangent_dir).normalized()
		var panel_basis := Basis(tangent_dir, normal_dir, radial_dir)
		var panel_length := (inner_pt - outer_pt).length()
		var panel_width := (outer_r_mid + DIP_OUTER_RADIUS) * 0.5 * (TAU / segments) * 1.15

		var coll := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(panel_width, 0.03, panel_length)
		coll.shape = box
		coll.transform = Transform3D(panel_basis, panel_center)
		slope_body.add_child(coll)

	st.generate_normals()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = _material(Color(0.48, 0.33, 0.2))
	slope_body.add_child(mesh_inst)
	container.add_child(slope_body)

## Local height (relative to a pit's own origin) at a given radius from its
## center — the exact same three-zone formula _make_funnel_pit and
## _make_big_slope build geometry from, kept in one place so the contour
## rings drawn below can never drift out of sync with the actual terrain.
func _terrain_height_at_radius(radius: float) -> float:
	if radius <= PIT_RADIUS:
		return -PIT_DEPTH
	if radius <= DIP_OUTER_RADIUS:
		return lerpf(-PIT_DEPTH, 0.0, (radius - PIT_RADIUS) / (DIP_OUTER_RADIUS - PIT_RADIUS))
	if radius <= LARGE_SLOPE_RADIUS:
		return lerpf(0.0, LARGE_SLOPE_DEPTH, (radius - DIP_OUTER_RADIUS) / (LARGE_SLOPE_RADIUS - DIP_OUTER_RADIUS))
	return LARGE_SLOPE_DEPTH

## World-space terrain surface height at an arbitrary (x, z) — whichever
## pit is nearer governs, matching how the slopes themselves are split.
## Anything placed procedurally (initial hotdog spawn, resets, etc.) should
## use this rather than assuming the old flat TABLE_TOP_Y: spawning below
## the actual (now often-elevated) surface means starting inside solid
## slope geometry, which the physics engine resolves by shoving the body
## out — plausibly the real cause of the reported "hotdog rolls off
## screen", not just the slope being too steep.
func _terrain_world_height_at(world_x: float, world_z: float) -> float:
	var dist_left := Vector2(world_x - LEFT_PIT_POS.x, world_z - LEFT_PIT_POS.z).length()
	var dist_right := Vector2(world_x - RIGHT_PIT_POS.x, world_z - RIGHT_PIT_POS.z).length()
	return TABLE_TOP_Y + _terrain_height_at_radius(minf(dist_left, dist_right))

## True while `body` is currently touching a table/funnel/slope/ground
## surface (any body tagged LAYER_TABLE or LAYER_GROUND) — requires
## contact_monitor + max_contacts_reported already set on `body` (true for
## hotdog segments and, now, arm segments too). Used to keep the funnel pull
## from grabbing hotdogs/arms mid-air (a held or just-thrown hotdog, or an
## arm reaching through the funnel's airspace) — it should only nudge things
## actually resting on a surface toward the pit center.
func _is_touching_table_surface(body: RigidBody3D) -> bool:
	for other in body.get_colliding_bodies():
		if other is CollisionObject3D and (other.get_collision_layer_value(LAYER_TABLE) or other.get_collision_layer_value(LAYER_GROUND)):
			return true
	return false

## Nudges anything within a funnel's outer radius toward that pit's exact
## XZ center — see _funnel_center_pull_strength for why this exists on top
## of the slope/floor geometry. Horizontal only (no Y component), so it
## never fights gravity or lifts anything; within the funnel, "toward
## center" and "downhill" are the same direction anyway, since terrain
## height there is purely a function of radius. Only applies to bodies
## actually resting on the table/funnel surface (see
## _is_touching_table_surface) — otherwise a thrown or held hotdog passing
## over a funnel mid-air, or an arm merely reaching over one, would get
## yanked sideways with no contact to justify it.
func _apply_funnel_center_pull(body: RigidBody3D) -> void:
	if not _is_touching_table_surface(body):
		return
	for pit_pos in [LEFT_PIT_POS, RIGHT_PIT_POS]:
		var offset := Vector3(body.global_position.x - pit_pos.x, 0.0, body.global_position.z - pit_pos.z)
		if offset.length() < DIP_OUTER_RADIUS:
			body.apply_central_force(-offset * _funnel_center_pull_strength)
			return

## Topographic contour rings (like a map's elevation lines) at fixed radius
## steps around a pit, each drawn flat at its own actual terrain height —
## a temporary read-the-terrain aid while shaping the slopes, toggled by
## F1 along with the other debug visualizations.
func _setup_terrain_contours(pit_pos: Vector3) -> void:
	var step := 0.5
	var radius := step
	while radius < LARGE_SLOPE_RADIUS:
		var ring := _make_wire_mesh(func(st: SurfaceTool) -> void:
			_add_wire_circle(st, radius, 48, Vector3.RIGHT, Vector3.FORWARD)
		)
		ring.position = pit_pos + Vector3(0, _terrain_height_at_radius(radius), 0)
		add_child(ring)
		_debug_nodes.append(ring)
		radius += step

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
	if body == _head_visual:
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

func _cycle_skin() -> void:
	_apply_skin((_current_skin_index + 1) % (SKIN_DEFS.size() + 1))

func _apply_skin(index: int) -> void:
	_teardown_skin()
	_current_skin_index = index

	if index == 0:
		_set_primitives_visible(true)
		_skin_label.text = "Skin: None (F2 to cycle)"
		return

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
	if _head_skin_root:
		_head_skin_root.queue_free()
		_head_skin_root = null

func _set_primitives_visible(is_visible: bool) -> void:
	for arm in [_arm_left, _arm_right]:
		arm.upper_arm.get_node("Mesh").visible = is_visible
		arm.forearm.get_node("Mesh").visible = is_visible
		arm.hand.get_node("Mesh").visible = is_visible
	_head_visual.visible = is_visible

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
	var head_scale := float(def["head_scale"])

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

	if bbox.size != Vector3.ZERO:
		_apply_head_mouth_hole(static_inst, bbox, head_scale)

const MOUTH_HOLE_SHADER_CODE := "
shader_type spatial;
uniform vec3 mouth_center_world;
uniform float mouth_radius_world;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

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

## Builds a plain, non-skinned ArrayMesh containing just the triangles
## whose vertices are predominantly weighted to one bone — used to pull a
## static copy of a skin's head geometry out of its full-body skinned
## mesh (see _setup_head_skin for why the head is rendered this way
## instead of staying a live skinned mesh like the arms). Vertex/normal
## data only — these are flat-colored materials with no UVs that matter
## here, and the head never animates, so nothing else is needed.
func _extract_bone_weighted_mesh(mesh: Mesh, bone_idx: int, min_weight: float = 0.4) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surf in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if verts.is_empty() or bones.is_empty():
			continue
		var bones_per_vertex := bones.size() / verts.size()

		var keep := PackedByteArray()
		keep.resize(verts.size())
		for i in range(verts.size()):
			var w := 0.0
			for b in range(bones_per_vertex):
				if bones[i * bones_per_vertex + b] == bone_idx:
					w += weights[i * bones_per_vertex + b]
			keep[i] = 1 if w >= min_weight else 0

		var tri_count := (indices.size() / 3) if not indices.is_empty() else (verts.size() / 3)
		var new_verts := PackedVector3Array()
		var new_normals := PackedVector3Array()
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

		if new_verts.is_empty():
			continue
		var new_arrays := []
		new_arrays.resize(Mesh.ARRAY_MAX)
		new_arrays[Mesh.ARRAY_VERTEX] = new_verts
		if not new_normals.is_empty():
			new_arrays[Mesh.ARRAY_NORMAL] = new_normals
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(surf))
	return out

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
		if orig_mat is BaseMaterial3D:
			orig_color = (orig_mat as BaseMaterial3D).albedo_color
		mat.set_shader_parameter("base_color", orig_color)
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
				_apply_funnel_center_pull(seg)

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

	_apply_funnel_center_pull(arm.upper_arm)
	_apply_funnel_center_pull(arm.forearm)
	_apply_funnel_center_pull(arm.hand)

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
