extends Area2D

signal enemy_destroyed

var velocity = Vector2.ZERO
var speed = 1800.0  # Very fast
var lifetime = 1.2  # Auto-despawn
var age = 0.0
var explosion_scene = preload("res://explosion.tscn")

func _ready():
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	# Small collision shape set in scene

func _process(delta):
	age += delta
	if age > lifetime:
		queue_free()
		return

	position += velocity * delta
	rotation = velocity.angle() + PI / 2

	# Fade out near end of life
	if age > lifetime * 0.7:
		modulate.a = lerp(1.0, 0.0, (age - lifetime * 0.7) / (lifetime * 0.3))

	# Off-screen cleanup
	if position.y > 1540 or position.y < -100 or position.x < -100 or position.x > 2660:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("enemy_missiles"):
		# Small flash explosion (no big boom)
		var explosion = explosion_scene.instantiate()
		explosion.position = position
		explosion.scale = Vector2(0.4, 0.4)  # Tiny explosion
		get_parent().add_child(explosion)

		enemy_destroyed.emit()
		area.queue_free()
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("terrain"):
		# Tiny spark on terrain hit — no crater, no damage
		queue_free()

func fire(from_pos: Vector2, direction: Vector2):
	position = from_pos
	# Add slight random spread
	var spread_angle = randf_range(-0.04, 0.04)  # ~2.3 degrees
	velocity = direction.rotated(spread_angle) * speed
	rotation = velocity.angle() + PI / 2
