extends Area2D

signal enemy_destroyed

var velocity = Vector2.ZERO
var gravity_force = 50  # Less gravity for heat-seekers
var explosion_scene = preload("res://explosion.tscn")
var crater_scene = preload("res://crater.tscn")
var target = null
var lock_strength = 0.0  # 0 to 1, how locked on we are
var tracking_speed = 3.0  # How fast missile adjusts course

# Sound state
var motor_player: AudioStreamPlayer2D = null
var motor_base_pitch: float = 1.0

func _ready():
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	play_launch_sound()
	_start_motor_loop()

# === Launch sound — punchy ignition + electronic seeker acquisition ===
func play_launch_sound():
	var sample_rate = 22050
	var duration = 0.65
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

		# Sharp attack, exponential decay envelope
		var envelope: float
		if t < 0.006:
			envelope = t / 0.006
		else:
			envelope = exp(-4.5 * (t - 0.006))

		# === Ignition crack — sharp broadband pop ===
		var crack = randf_range(-1.0, 1.0) * max(0.0, 1.0 - t / 0.018) * 0.65

		# === Rocket motor rush — whooshing noise with low-pass character ===
		var rush_env = min(t / 0.03, 1.0) * exp(-2.5 * max(0.0, t - 0.05))
		var rush = randf_range(-1.0, 1.0) * randf_range(0.4, 1.0) * rush_env * 0.35

		# === Low sub-thump on ignition ===
		var sub = sin(TAU * 55.0 * t) * max(0.0, 1.0 - t / 0.08) * 0.25

		# === Mid-tone rocket body resonance ===
		var mid = sin(TAU * 280.0 * t * (1.0 - progress * 0.3)) * 0.12 * max(0.0, 1.0 - t / 0.2)

		# === Electronic seeker acquisition — descending chirp ===
		var chirp_freq = 3200.0 * exp(-12.0 * t)  # Rapid descending tone
		var chirp_env = max(0.0, 1.0 - t / 0.06) * 0.3
		var chirp = sin(TAU * chirp_freq * t) * chirp_env

		# === Seeker lock ping — short tonal blip at ~1800Hz ===
		var ping_start = 0.04
		var ping_dur = 0.035
		var ping = 0.0
		if t > ping_start and t < ping_start + ping_dur:
			var ping_t = t - ping_start
			var ping_env = sin(PI * ping_t / ping_dur)  # smooth bell shape
			ping = sin(TAU * 1800.0 * ping_t) * ping_env * 0.2

		# === Doppler rising whoosh (distant receding) ===
		var whoosh_env = clamp((t - 0.08) / 0.15, 0.0, 1.0) * exp(-3.0 * max(0.0, t - 0.25))
		var whoosh = randf_range(-1.0, 1.0) * whoosh_env * 0.18

		# Mix
		var sample_val = (crack + rush + sub + mid + chirp + ping + whoosh) * envelope
		sample_val = tanh(clamp(sample_val, -1.5, 1.5) * 1.4) / tanh(1.4)

		var int_val = int(sample_val * 30000)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data

	var player = AudioStreamPlayer2D.new()
	player.stream = audio
	player.volume_db = 3.0
	player.pitch_scale = randf_range(0.94, 1.06)
	player.max_distance = 2500.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

# === Continuous rocket motor loop — hiss + low rumble ===
func _start_motor_loop():
	var sample_rate = 22050
	var duration = 0.3  # Short loop that repeats
	var num_samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false
	audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	audio.loop_begin = 0
	audio.loop_end = num_samples

	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate

		# Jet hiss — filtered noise
		var hiss = randf_range(-1.0, 1.0) * randf_range(0.3, 1.0) * 0.15

		# Low motor rumble
		var rumble = sin(TAU * 72.0 * t) * 0.12
		rumble += sin(TAU * 144.0 * t) * 0.06  # harmonic

		# Mid whine (seeker electronics)
		var whine = sin(TAU * 520.0 * t) * 0.04
		whine += sin(TAU * 780.0 * t) * 0.02  # harmonic shimmer

		# Slight flutter modulation
		var flutter = 1.0 + sin(TAU * 18.0 * t) * 0.08

		var sample_val = (hiss + rumble + whine) * flutter
		sample_val = tanh(sample_val * 1.2) / tanh(1.2)

		var int_val = int(sample_val * 20000)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data

	motor_player = AudioStreamPlayer2D.new()
	motor_player.stream = audio
	motor_player.volume_db = -4.0
	motor_player.pitch_scale = randf_range(0.95, 1.05)
	motor_player.max_distance = 1800.0
	motor_player.bus = &"Master"
	motor_base_pitch = motor_player.pitch_scale
	add_child(motor_player)
	motor_player.play()

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
	# === Motor sound pitch follows speed ===
	if motor_player and is_instance_valid(motor_player):
		var speed_ratio = clamp(velocity.length() / 400.0, 0.6, 1.6)
		motor_player.pitch_scale = motor_base_pitch * speed_ratio
		# Volume rises slightly when tracking
		var target_vol = -2.0 if (target and is_instance_valid(target)) else -6.0
		motor_player.volume_db = lerp(motor_player.volume_db, target_vol, 4.0 * delta)

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
