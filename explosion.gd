extends Node2D

func _ready():
	# Play explosion sound
	play_explosion_sound()

	# Auto-delete after all particles finish
	var cleanup_time = 1.0
	if name == "MegaExplosion":
		cleanup_time = 1.5

	await get_tree().create_timer(cleanup_time).timeout
	queue_free()

func play_explosion_sound():
	var is_mega = name == "MegaExplosion"
	var sample_rate = 22050
	var duration = 0.7 if not is_mega else 1.1
	var num_samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit = 2 bytes per sample

	# Deeper bass frequencies
	var bass_freq = 35.0 if not is_mega else 22.0
	var sub_freq = 18.0 if not is_mega else 12.0  # Sub-bass thump
	var mid_freq = 80.0 if not is_mega else 55.0  # Mid rumble

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var progress = float(i) / num_samples

		# Envelope: sharp attack, slower decay with bass tail
		var envelope: float
		if t < 0.008:
			envelope = t / 0.008  # Snappy attack
		elif progress < 0.15:
			envelope = 1.0  # Sustain the initial blast
		else:
			# Slow exponential decay - bass lingers
			var decay_progress = (progress - 0.15) / 0.85
			envelope = pow(1.0 - decay_progress, 1.5)

		# Sub-bass thump (loudest, felt more than heard)
		var sub_bass = sin(TAU * sub_freq * t) * 0.35

		# Main bass boom with pitch drop
		var pitch_drop = 1.0 - progress * 0.5  # Pitch drops over time
		var bass = sin(TAU * bass_freq * t * pitch_drop) * 0.3

		# Mid rumble layer
		var mid = sin(TAU * mid_freq * t * pitch_drop) * 0.15

		# Filtered noise (low-pass feel - bias toward lower random values)
		var noise = randf_range(-1.0, 1.0) * randf_range(0.3, 1.0)
		# Mix consecutive noise samples for crude low-pass effect
		var noise_weight = 0.2 * (1.0 - progress * 0.5)

		# Crackle in the initial blast (high freq transient)
		var crackle = 0.0
		if t < 0.05:
			crackle = randf_range(-1.0, 1.0) * (1.0 - t / 0.05) * 0.25

		# Mix: heavy on bass, noise for texture
		var sample_val = (sub_bass + bass + mid + noise * noise_weight + crackle) * envelope
		sample_val = clamp(sample_val, -1.0, 1.0)

		# Soft clipping for warmth
		sample_val = tanh(sample_val * 1.5) / tanh(1.5)

		# Convert to 16-bit integer
		var int_val = int(sample_val * 32000)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data

	$Sound.stream = audio
	$Sound.volume_db = 6.0 if not is_mega else 10.0
	$Sound.pitch_scale = randf_range(0.75, 1.05)  # Lower pitch range
	$Sound.play()
