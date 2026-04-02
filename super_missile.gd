extends Area2D

var velocity = Vector2.ZERO
var gravity_force = 80  # Low gravity - parachute slows descent
var explosion_scene = preload("res://mega_explosion.tscn")
var crater_scene = preload("res://crater.tscn")
var parachute_deployed = false
var parachute_speed = 35.0  # Very slow terminal velocity with parachute
var sway_time = 0.0  # For parachute swaying

func _ready():
	add_to_group("enemy_missiles")
	rotation = velocity.angle() + PI/2
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _on_body_entered(body):
	if body.is_in_group("terrain"):
		# Devastating terrain damage - multiple overlapping craters
		if body.has_method("damage"):
			body.damage(global_position, 180.0, 130.0)
			body.damage(global_position + Vector2(-40, 0), 80.0, 50.0)
			body.damage(global_position + Vector2(40, 0), 80.0, 50.0)

		# Triple explosion for super missile
		var explosion = explosion_scene.instantiate()
		explosion.position = position
		get_parent().add_child(explosion)

		var explosion2 = explosion_scene.instantiate()
		explosion2.position = position + Vector2(randf_range(-50, 50), randf_range(-30, 10))
		get_parent().add_child(explosion2)

		var explosion3 = explosion_scene.instantiate()
		explosion3.position = position + Vector2(randf_range(-40, 40), randf_range(-20, 15))
		get_parent().add_child(explosion3)

		# Big screen shake
		var main = get_tree().current_scene
		if main.has_method("shake_screen"):
			main.shake_screen(30.0)

		# Huge crater
		var crater = crater_scene.instantiate()
		crater.position = position
		crater.scale = Vector2(5, 5)
		crater.z_index = -1
		get_parent().add_child(crater)

		queue_free()

func _on_area_entered(area):
	if area.is_in_group("launchers"):
		# Annihilate the terrain
		var terrain_nodes = get_tree().get_nodes_in_group("terrain")
		for terrain in terrain_nodes:
			if terrain.has_method("damage"):
				terrain.damage(area.global_position, 220.0, 150.0)
				terrain.damage(area.global_position + Vector2(-60, 0), 100.0, 60.0)
				terrain.damage(area.global_position + Vector2(60, 0), 100.0, 60.0)

		# Massive screen shake
		var main = get_tree().current_scene
		if main.has_method("shake_screen"):
			main.shake_screen(45.0)

		# Triple mega explosion
		var explosion = explosion_scene.instantiate()
		explosion.position = area.global_position
		get_parent().add_child(explosion)

		var explosion2 = explosion_scene.instantiate()
		explosion2.position = area.global_position + Vector2(randf_range(-60, 60), randf_range(-40, 10))
		get_parent().add_child(explosion2)

		var explosion3 = explosion_scene.instantiate()
		explosion3.position = area.global_position + Vector2(randf_range(-50, 50), randf_range(-30, 15))
		get_parent().add_child(explosion3)

		# Massive crater
		var crater = crater_scene.instantiate()
		crater.position = area.global_position
		crater.scale = Vector2(7, 7)
		crater.z_index = -1
		get_parent().add_child(crater)

		area.queue_free()
		queue_free()

func _process(delta):
	# Deploy parachute when falling (velocity.y > 0 means going down)
	if velocity.y > 15.0 and not parachute_deployed:
		parachute_deployed = true
		$Parachute.visible = true
		# Slow down dramatically
		velocity.x *= 0.3
		gravity_force = 15

	if parachute_deployed:
		# Limit fall speed (parachute drag)
		if velocity.y > parachute_speed:
			velocity.y = lerp(velocity.y, parachute_speed, 3.0 * delta)

		# Gentle sway
		sway_time += delta
		velocity.x += sin(sway_time * 1.5) * 15.0 * delta

		# Parachute billowing animation
		var sway = sin(sway_time * 2.0) * 0.08
		$Parachute.rotation = sway

		# Keep missile pointing mostly down
		rotation = lerp_angle(rotation, PI, 2.0 * delta)
	else:
		velocity.y += gravity_force * delta
		rotation = velocity.angle() + PI/2

	position += velocity * delta

	# Delete when off-screen
	if position.y > 1600 or position.x < -200 or position.x > 2760:
		queue_free()

func launch_to(target: Vector2, launch_time: float = 8.0):
	var displacement = target - position
	velocity.x = displacement.x / launch_time
	velocity.y = (displacement.y - 0.5 * gravity_force * launch_time * launch_time) / launch_time
