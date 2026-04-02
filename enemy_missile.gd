extends Area2D

var velocity = Vector2.ZERO
var gravity_force = 200
var explosion_scene = preload("res://explosion.tscn")
var mega_explosion_scene = preload("res://mega_explosion.tscn")
var crater_scene = preload("res://crater.tscn")

func _ready():
	add_to_group("enemy_missiles")
	rotation = velocity.angle() + PI/2
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _on_body_entered(body):
	# Hit terrain
	if body.is_in_group("terrain"):
		# Damage the terrain
		if body.has_method("damage"):
			body.damage(global_position, 55.0, 40.0)

		# Create explosion
		var explosion = explosion_scene.instantiate()
		explosion.position = position
		get_parent().add_child(explosion)

		# Create crater scorch marks
		var crater = crater_scene.instantiate()
		crater.position = position
		crater.z_index = -1  # Behind terrain
		get_parent().add_child(crater)

		queue_free()

func _on_area_entered(area):
	# Hit launcher
	if area.is_in_group("launchers"):
		# Damage the terrain under the launcher
		var terrain_nodes = get_tree().get_nodes_in_group("terrain")
		for terrain in terrain_nodes:
			if terrain.has_method("damage"):
				terrain.damage(area.global_position, 80.0, 60.0)

		# Screen shake!
		var main = get_tree().current_scene
		if main.has_method("shake_screen"):
			main.shake_screen(25.0)

		var mega_explosion = mega_explosion_scene.instantiate()
		mega_explosion.position = area.global_position
		get_parent().add_child(mega_explosion)

		# Create crater where launcher was
		var crater = crater_scene.instantiate()
		crater.position = area.global_position
		crater.scale = Vector2(2, 2)  # Bigger crater for launcher destruction
		crater.z_index = -1
		get_parent().add_child(crater)

		# Destroy launcher
		area.queue_free()
		queue_free()

func _process(delta):
	velocity.y += gravity_force * delta
	position += velocity * delta
	rotation = velocity.angle() + PI/2

	# delete when way off-screen (collision will handle terrain hits)
	if position.y > 1600 or position.x < -100 or position.x > 2660:
		queue_free()

func launch_to(target: Vector2, launch_time: float = 2.0):
	var displacement = target - position
	velocity.x = displacement.x / launch_time
	velocity.y = (displacement.y - 0.5 * gravity_force * launch_time * launch_time) / launch_time
