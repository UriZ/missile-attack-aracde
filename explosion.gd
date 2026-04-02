extends Node2D

func _ready():
	# Auto-delete after all particles finish
	# Regular explosion: 0.5s, Mega explosion: 1.0s
	var cleanup_time = 0.5
	if name == "MegaExplosion":
		cleanup_time = 1.0

	await get_tree().create_timer(cleanup_time).timeout
	queue_free()
