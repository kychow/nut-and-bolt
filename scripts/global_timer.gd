extends Node

var _elapsed_time: float = 0.0
var _is_counting: bool = false
var _label: Label

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GlobalTimer"
	add_child(layer)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.0
	_label.anchor_bottom = 0.0
	_label.offset_right = 0.0
	_label.offset_top = 12.0
	_label.offset_bottom = 60.0
	_label.add_theme_font_size_override("font_size", 36)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.text = "Time: 0.0s"
	layer.add_child(_label)

func _process(delta: float) -> void:
	if _is_counting:
		_elapsed_time += delta
		_label.text = "Time: %02.1fs" % _elapsed_time

func start_counting() -> void:
	_is_counting = true

func stop_counting() -> void:
	_is_counting = false

func reset() -> void:
	_elapsed_time = 0.0
	_is_counting = false
	_label.text = "Time: 0.0s"
