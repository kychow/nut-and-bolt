extends CanvasLayer

const GAME_SCENE := "res://main.tscn"
const FADE_DURATION := 0.4

@onready var _root: Control = $Root

var _dismissed := false


func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		_dismiss()
	elif event is InputEventMouseButton and event.pressed:
		_dismiss()
	elif event is InputEventJoypadButton and event.pressed:
		_dismiss()


func _dismiss() -> void:
	_dismissed = true

	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(_change_scene)


func _change_scene() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
