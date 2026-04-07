extends Area2D

signal enemy_destroyed

var velocity = Vector2.ZERO
var gravity_force = 50  # Less gravity for heat-seekers
var explosion_scene = preload("res://explosion.tscn")
var crater_scene = preload("res://crater.tscn")
var target = null
var lock_strength = 0.0  # 0 to 1, how locked on we are
var tracking_speed = 3.0  # How fast missile adjusts course

func _ready():
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	play_launch_sound()

func play_launch_sound():
	var sample_rate = 22050
	var duration = 0.50
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
		var envelope = t / 0.008 if t < 0.008 else exp(-5.5 * (t - 0.008))

		# Ignition crack
		var crack = randf_range(-1.0, 1.0) * max(0.0, 1.0 - t / 0.020) * 0.60

		# Rocket hiss — slightly more whistley
		var hiss = randf_range(-1.0, 1.0) * 0.28 * (1.0 - progress)

		# Higher mid-tone (distinguishes seeker from standard missile)
		var mid = sin(TAU * 320.0 * t) * max(0.0, 1.0 - t / 0.12) * 0.18

		# Brief electronic seeker blip at ignition
		var seeker = sin(TAU * 2600.0 * t) * max(0.0, 1.0 - t / 0.045) * 0.22

		var sample_val = (crack + hiss + mid + seeker) * envelope
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
		var explosion = explosion_scene.instantiate()
		explosion.position = position
		get_parent().add_child(explosion)

		if body.has_method("damage"):
			body.damage(global_position, 40.0, 25.0)

		var crater = crater_scene.instantiate()
		crater.position = position
		crater.scale = Vector2(1.0, 1.0)
		crater.z_index = -1
		get_parent().add_child(crater)

		queue_free()

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

		# Change nosecone color to red when locked
		$Nosecone.color = Color(1.0, 0.2, 0.1, 1).lerp(Color(0.9, 0.9, 0.2, 1), 1.0 - lock_strength)
		$Body.color = Color(0.5, 0.3, 0.3, 1).lerp(Color(0.3, 0.4, 0.6, 1), 1.0 - lock_strength)
	else:
		# Lost target, apply more gravity
		velocity.y += gravity_force * 2.0 * delta
		lock_strength = max(lock_strength - delta * 3.0, 0.0)

		# Fade back to normal colors
		$Nosecone.color = Color(0.9, 0.9, 0.2, 1)
		$Body.color = Color(0.3, 0.4, 0.6, 1)

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
