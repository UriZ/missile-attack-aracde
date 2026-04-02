extends Area2D

signal enemy_destroyed

var velocity = Vector2.ZERO
var gravity_force = 50  # Less gravity for heat-seekers
var explosion_scene = preload("res://explosion.tscn")
var target = null
var lock_strength = 0.0  # 0 to 1, how locked on we are
var tracking_speed = 3.0  # How fast missile adjusts course

func _ready():
	area_entered.connect(_on_area_entered)

func _process(delta):
	if target and is_instance_valid(target):
		# Track the target
		var target_dir = (target.global_position - global_position).normalized()
		var current_dir = velocity.normalized()

		# Gradually turn toward target
		var new_dir = current_dir.lerp(target_dir, tracking_speed * delta)
		var speed = velocity.length()
		velocity = new_dir * speed

		# Increase lock strength
		lock_strength = min(lock_strength + delta * 2.0, 1.0)

		# Show lock indicator
		$LockIndicator.visible = true
		$LockIndicator.default_color = Color(0, 1, 0, lock_strength)
	else:
		# Lost target, apply more gravity
		velocity.y += gravity_force * 2.0 * delta
		lock_strength = max(lock_strength - delta * 3.0, 0.0)
		$LockIndicator.visible = false

	# Apply slight gravity even when locked
	velocity.y += gravity_force * delta

	# Update position
	position += velocity * delta

	# Rotate to face direction of travel
	rotation = velocity.angle() + PI/2

	# Delete when off-screen
	if position.y > 1540 or position.y < -100 or position.x < -100 or position.x > 2660:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("enemy_missiles"):
		# Create explosion
		var explosion = explosion_scene.instantiate()
		explosion.position = position
		get_parent().add_child(explosion)

		# Notify score system
		enemy_destroyed.emit()

		# Destroy both missiles
		area.queue_free()
		queue_free()

func launch_to(target_pos: Vector2, locked_target = null):
	var displacement = target_pos - position
	var launch_time = 1.5

	# Initial velocity calculation
	velocity.x = displacement.x / launch_time
	velocity.y = (displacement.y - 0.5 * gravity_force * launch_time * launch_time) / launch_time

	# Set target if locked
	if locked_target:
		target = locked_target
		lock_strength = 0.5  # Start with partial lock
