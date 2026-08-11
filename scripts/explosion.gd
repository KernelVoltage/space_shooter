extends AnimatedSprite2D

func _ready() -> void:
	animation_finished.connect(_on_animation_finished)
	play("Explosion")
	$Explosion.play()

func _on_animation_finished() -> void:
	queue_free()
