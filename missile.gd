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
	play_launch_sound()

func play_launch_sound():
	var sample_rate = 22050
	var duration = 0.45
	var num_samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var progress = t / duration

		# Sharp attack, exponential decay
		var envelope = t / 0.008 if t < 0.008 else exp(-6.5 * (t - 0.008))

		# Ignition crack — broadband noise burst
		var crack = randf_range(-1.0, 1.0) * max(0.0, 1.0 - t / 0.022) * 0.75

		# Rocket hiss — decaying noise
		var hiss = randf_range(-1.0, 1.0) * 0.30 * (1.0 - progress)

		# Low rumble
		var rumble = sin(TAU * 85.0 * t) * 0.18 * (1.0 - progress * 0.8)

		var sample_val = (crack + hiss + rumble) * envelope
		sample_val = tanh(clamp(sample_val, -1.5, 1.5) * 1.3) / tanh(1.3)

		var int_val = int(sample_val * 28000)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data

	var player = AudioStreamPlayer2D.new()
	player.stream = audio
	player.volume_db = 1.0
	player.pitch_scale = randf_range(0.92, 1.08)
	player.max_distance = 2000.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

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
