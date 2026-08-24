
extends Control

const SKY := Color(0.60, 0.72, 0.85)
const TURF := Color(0.25, 0.50, 0.25)
const TRACK := Color(0.62, 0.30, 0.18)
const LINE := Color.WHITE
const WALL := Color(0.52, 0.52, 0.57)
const RISER := Color(0.43, 0.43, 0.48)
const TREAD := Color(0.67, 0.67, 0.71)
const ROOF := Color(0.33, 0.33, 0.39)
const POST := Color(0.42, 0.42, 0.47)
const CLOUD := Color(1.0, 1.0, 1.0, 0.93)

const SHIRTS: Array[Color] = [
	Color(0.85, 0.25, 0.25),
	Color(0.95, 0.55, 0.15),
	Color(0.95, 0.80, 0.20),
	Color(0.30, 0.65, 0.30),
	Color(0.25, 0.45, 0.85),
	Color(0.55, 0.35, 0.75),
	Color(0.90, 0.45, 0.65),
	Color(0.20, 0.65, 0.60)
]

const SKINS: Array[Color] = [
	Color(0.98, 0.85, 0.72),
	Color(0.90, 0.70, 0.55),
	Color(0.72, 0.52, 0.38),
	Color(0.55, 0.38, 0.26)
]

const ROW_FEET := [0.355, 0.415, 0.475]
const BOBS := [0.0, -2.0, -1.0]
const RAISES := [0.0, 0.45, 1.0]

const STAND_TOP := 0.295
const STAND_BOTTOM := 0.50
const ROOF_TOP := 0.26
const ROOF_BOTTOM := 0.288
const TRACK_TOP := 0.58
const TRACK_BOTTOM := 0.76
const FRAME_RATE := 3.0
const SPACING := 0.048

var _time := 0.0
var _spectators: Array[Dictionary] = []
var _clouds: Array[Dictionary] = []


func _ready() -> void:
	_generate_spectators()
	_generate_clouds()


func _process(delta: float) -> void:
	_time += delta

	for cloud in _clouds:
		cloud.x += cloud.v * delta

		if cloud.x > 1.18:
			cloud.x = -0.18

	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var u := h / 720.0

	draw_rect(Rect2(0.0, 0.0, w, h), SKY)
	_draw_clouds(w, h, u)
	_draw_stands(w, h, u)
	draw_rect(
		Rect2(
			0.0,
			h * STAND_BOTTOM,
			w,
			h * (TRACK_TOP - STAND_BOTTOM)
		),
		TURF
	)
	draw_rect(
		Rect2(
			0.0,
			h * TRACK_TOP,
			w,
			h * (TRACK_BOTTOM - TRACK_TOP)
		),
		TRACK
	)
	draw_rect(
		Rect2(
			0.0,
			h * TRACK_BOTTOM,
			w,
			h * (1.0 - TRACK_BOTTOM)
		),
		TURF
	)
	_draw_track_lines(w, h, u)
	_draw_spectators(h)


func _draw_clouds(w: float, h: float, u: float) -> void:
	for cloud in _clouds:
		var cx: float = cloud.x * w
		var cy: float = cloud.y * h
		var r: float = 34.0 * cloud.s * u

		draw_circle(Vector2(cx, cy), r, CLOUD)
		draw_circle(Vector2(cx - 0.95 * r, cy + 0.22 * r), 0.72 * r, CLOUD)
		draw_circle(Vector2(cx + 0.95 * r, cy + 0.20 * r), 0.78 * r, CLOUD)
		draw_circle(Vector2(cx + 0.20 * r, cy - 0.42 * r), 0.62 * r, CLOUD)
		draw_rect(
			Rect2(cx - 1.5 * r, cy + 0.05 * r, 3.0 * r, 0.55 * r),
			CLOUD
		)


func _draw_stands(w: float, h: float, u: float) -> void:
	draw_rect(
		Rect2(
			0.0,
			h * STAND_TOP,
			w,
			h * (STAND_BOTTOM - STAND_TOP)
		),
		WALL
	)

	for i in ROW_FEET.size():
		var foot: float = ROW_FEET[i]

		draw_rect(
			Rect2(0.0, h * (foot - 0.052), w, h * 0.052),
			RISER
		)
		draw_rect(
			Rect2(0.0, h * foot, w, h * 0.007),
			TREAD
		)

	for i in 5:
		var px := w * (0.12 + 0.19 * i)

		draw_rect(
			Rect2(
				px,
				h * ROOF_BOTTOM,
				5.0 * u,
				h * (0.40 - ROOF_BOTTOM)
			),
			POST
		)

	draw_rect(
		Rect2(
			0.0,
			h * ROOF_TOP,
			w,
			h * (ROOF_BOTTOM - ROOF_TOP)
		),
		ROOF
	)
	draw_rect(
		Rect2(0.0, h * ROOF_BOTTOM, w, 3.0 * u),
		ROOF.darkened(0.25)
	)


func _draw_track_lines(w: float, h: float, u: float) -> void:
	for i in 4:
		var y := TRACK_TOP + (TRACK_BOTTOM - TRACK_TOP) * i / 3.0
		var thick := 4.0 * u if (i == 0 or i == 3) else 2.5 * u

		draw_rect(
			Rect2(0.0, h * y - thick * 0.5, w, thick),
			LINE
		)


func _draw_spectators(h: float) -> void:
	var u := h / 720.0
	var global_frame := int(_time * FRAME_RATE)

	for s in _spectators:
		var f := (global_frame + int(s.phase)) % 3
		var bob: float = BOBS[f] * u
		var raise: float = RAISES[f] * float(s.amp)
		var x: float = s.x * size.x
		var foot: float = ROW_FEET[int(s.row)] * h + bob
		var body_w := 11.0 * u
		var body_h := 15.0 * u
		var head_r := 5.5 * u
		var body_top := foot - body_h

		draw_rect(
			Rect2(x - body_w * 0.5, body_top, body_w, body_h),
			s.shirt
		)
		draw_circle(
			Vector2(x, body_top - head_r * 0.9),
			head_r,
			s.skin
		)

		var shoulder_y := body_top + 2.5 * u

		for side: float in [-1.0, 1.0]:
			var sx := x + side * body_w * 0.62
			var hand_x := sx + side * 2.0 * u
			var hand_y := lerpf(
				shoulder_y + 8.0 * u,
				shoulder_y - 11.0 * u,
				raise
			)

			draw_line(
				Vector2(sx, shoulder_y),
				Vector2(hand_x, hand_y),
				s.shirt,
				3.0 * u
			)


func _generate_spectators() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260821

	for row in ROW_FEET.size():
		var x := 0.5 * SPACING if row % 2 == 1 else 0.0

		while x < 1.0:
			if rng.randf() > 0.12:
				_spectators.append({
					"x": x + rng.randf_range(-0.006, 0.006),
					"row": row,
					"shirt": SHIRTS[rng.randi() % SHIRTS.size()],
					"skin": SKINS[rng.randi() % SKINS.size()],
					"phase": rng.randi() % 3,
					"amp": rng.randf_range(0.35, 1.0)
				})

			x += SPACING


func _generate_clouds() -> void:
	_clouds = [
		{"x": 0.12, "y": 0.10, "s": 1.0, "v": 0.010},
		{"x": 0.42, "y": 0.17, "s": 0.7, "v": 0.007},
		{"x": 0.68, "y": 0.07, "s": 1.25, "v": 0.013},
		{"x": 0.90, "y": 0.15, "s": 0.85, "v": 0.008}
	]
