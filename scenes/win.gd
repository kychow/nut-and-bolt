extends Node2D

var _dismissed := false

func _ready() -> void:
	var layer := CanvasLayer.new()

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var label := Label.new()
	label.text = "You win!\nPress Enter to continue"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position -= Vector2(300, 60)
	label.size = Vector2(600, 120)
	layer.add_child(label)

	add_child(layer)

func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ENTER:
		_dismissed = true
		get_tree().change_scene_to_file("res://main.tscn")
