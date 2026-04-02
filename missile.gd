extends Area2D

signal enemy_destroyed

var velocity = Vector2.ZERO
var gravity_force = 200  # pixels per second squared
var explosion_scene = preload("res://explosion.tscn")
var crater_scene = preload("res://crater.tscn")

func _ready():
	rotation = velocity.angle() + PI/2  # point missile in direction of travel
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("terrain"):
		# Explode on terrain
		var explosion = explosion_scene.instantiate()
		explosion.position = position
		get_parent().add_child(explosion)

		# Small terrain damage from interceptor
		if body.has_method("damage"):
			body.damage(global_position, 40.0, 25.0)

		# Small crater mark
		var crater = crater_scene.instantiate()
		crater.position = position
		crater.scale = Vector2(1.0, 1.0)
		crater.z_index = -1
		get_parent().add_child(crater)

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

func _process(delta):
	# apply gravity
	velocity.y += gravity_force * delta

	# update position
	position += velocity * delta

	# rotate to face direction of travel
	rotation = velocity.angle() + PI/2

	# delete when off-screen
	if position.y > 1540 or position.y < -100 or position.x < -100 or position.x > 2660:
		queue_free()

func launch_to(target: Vector2, launch_time: float = 1.5):
	# calculate initial velocity needed to reach target
	var displacement = target - position
	print("Missile launching from ", position, " to ", target)
	print("Displacement: ", displacement)

	# solve for initial velocity using kinematic equations
	# displacement.y = velocity.y * t + 0.5 * gravity_force * t^2
	# displacement.x = velocity.x * t
	velocity.x = displacement.x / launch_time
	velocity.y = (displacement.y - 0.5 * gravity_force * launch_time * launch_time) / launch_time
	print("Initial velocity: ", velocity)
