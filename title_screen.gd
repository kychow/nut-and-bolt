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
	

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		take_screenshot()

func take_screenshot() -> void:
	# Wait for the frame to finish drawing
	await RenderingServer.frame_post_draw
	
	# Ensure the screenshots folder exists
	var dir_path = "user://screenshots"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_absolute(dir_path)
	
	# Generate a unique timestamp (YYYY-MM-DD_HH-MM-SS)
	var datetime = Time.get_datetime_dict_from_system()
	var timestamp = "%04d-%02d-%02d_%02d-%02d-%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]
	
	# Combine into the final file path
	var file_path = dir_path + "/screenshot_" + timestamp + ".png"
	
	# Capture and save the image
	var img = get_viewport().get_texture().get_image()
	img.save_png(file_path)
	
	print("Screenshot saved to: ", ProjectSettings.globalize_path(file_path))
