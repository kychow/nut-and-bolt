extends Node2D

## Placeholder win screen — the real next-stage content isn't designed yet;
## this is just a clean, swappable landing point for the _on_win() scene
## transition in main.gd.

func _ready() -> void:
	var layer := CanvasLayer.new()

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var label := Label.new()
	label.text = "You win!\nNext stage coming soon"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position -= Vector2(300, 60)
	label.size = Vector2(600, 120)
	layer.add_child(label)

	add_child(layer)
