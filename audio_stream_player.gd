extends AudioStreamPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	autoplay = true
	var fade_in_music = create_tween()
	fade_in_music.tween_property(self, "volume_db", linear_to_db(1.0), 1.0).from(linear_to_db(0.1))
	play()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
