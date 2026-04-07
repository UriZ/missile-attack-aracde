extends Area2D

# Vulkan Cannon — rapid fire anti-air with overheat mechanic

signal launcher_clicked(launcher)

var is_selected = false
var glow_tween: Tween = null

# Overheat system
var heat = 0.0           # 0.0 = cool, 1.0 = max
var heat_per_shot = 0.018 # Each shot adds this much heat (~56 shots to overheat, ~3.9s)
var cool_rate = 0.32      # Heat lost per second when not firing
var overheat_cool_rate = 0.18  # Slower cooling when overheated
var overheated = false    # Locked out when true
var overheat_threshold = 1.0  # Heat level that triggers lockout
var overheat_recover = 0.3    # Must cool to this level to recover

# Firing
var fire_rate = 0.07      # Seconds between shots (about 14/sec)
var fire_timer = 0.0
var is_firing = false
var barrel_spin = 0.0     # Current barrel rotation in degrees
var barrel_speed = 0.0    # Current spin speed in degrees/sec

var vulkan_bullet_scene = preload("res://vulkan_bullet.tscn")

# Sound state
var fire_sound_player: AudioStreamPlayer2D = null
var spool_player: AudioStreamPlayer2D = null

func _ready():
	add_to_group("launchers")
	input_event.connect(_on_input_event)
	_create_fire_sound()
	_create_spool_sound()

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		launcher_clicked.emit(self)
		get_viewport().set_input_as_handled()

func _process(delta):
	# Turret tracking
	if has_node("Turret"):
		var mouse_pos = get_global_mouse_position()
		var direction = mouse_pos - global_position
		var target_angle = direction.angle() + PI / 2
		target_angle = clamp(target_angle, deg_to_rad(-80), deg_to_rad(80))
		$Turret.rotation = lerp_angle($Turret.rotation, target_angle, 12.0 * delta)

	# Firing logic — only when selected and mouse held
	if is_selected and is_firing and not overheated:
		fire_timer -= delta
		if fire_timer <= 0:
			fire_timer = fire_rate
			fire_bullet()
			heat = min(heat + heat_per_shot, 1.0)
			if heat >= overheat_threshold:
				overheated = true
				is_firing = false  # Force stop
	
	# Cooling
	if overheated:
		heat = max(heat - overheat_cool_rate * delta, 0.0)
		if heat <= overheat_recover:
			overheated = false
	elif not is_firing:
		heat = max(heat - cool_rate * delta, 0.0)

	# Barrel spin visual
	if is_firing and not overheated:
		barrel_speed = lerp(barrel_speed, 1200.0, 5.0 * delta)  # Spin up fast
	else:
		barrel_speed = lerp(barrel_speed, 0.0, 3.0 * delta)  # Spin down gradually
	
	barrel_spin += barrel_speed * delta
	if barrel_spin > 360.0:
		barrel_spin -= 360.0

	if has_node("Turret/BarrelGroup"):
		$Turret/BarrelGroup.rotation = deg_to_rad(barrel_spin)

	# === Spool sound follows barrel speed ===
	if spool_player and is_instance_valid(spool_player):
		var spool_ratio = clamp(barrel_speed / 1200.0, 0.0, 1.0)
		spool_player.pitch_scale = 0.5 + spool_ratio * 1.0  # 0.5 → 1.5
		var target_vol = -20.0 + spool_ratio * 18.0  # -20 → -2 dB
		spool_player.volume_db = lerp(spool_player.volume_db, target_vol, 6.0 * delta)

	# Heat glow visual (tints barrels, housing, muzzle)
	update_heat_visual()

func fire_bullet():
	var bullet = vulkan_bullet_scene.instantiate()
	var launch_pos = get_launch_position()
	var mouse_pos = get_global_mouse_position()
	var direction = (mouse_pos - launch_pos).normalized()
	
	get_parent().add_child(bullet)
	bullet.fire(launch_pos, direction)
	bullet.enemy_destroyed.connect(func(): 
		get_tree().current_scene._on_enemy_destroyed()
	)
	
	# Tiny screen shake per shot
	var main = get_tree().current_scene
	if main.has_method("shake_screen"):
		main.shake_screen(0.8)

	# Play fire sound (rapid click/crack per shot)
	_play_shot_sound()

# === Per-shot sound — tiny metallic crack ===
func _play_shot_sound():
	if not fire_sound_player or not is_instance_valid(fire_sound_player):
		_create_fire_sound()
	fire_sound_player.pitch_scale = randf_range(0.85, 1.15)
	fire_sound_player.volume_db = randf_range(-3.0, 0.0)
	fire_sound_player.play()

# === Create reusable per-shot audio ===
func _create_fire_sound():
	var sample_rate = 22050
	var duration = 0.06
	var num_samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate

		# Ultra-sharp attack, fast decay
		var envelope = min(t / 0.001, 1.0) * exp(-60.0 * t)

		# Sharp metallic crack
		var crack = randf_range(-1.0, 1.0) * 0.8

		# Brief metallic ring
		var ring = sin(TAU * 1200.0 * t) * 0.3 * max(0.0, 1.0 - t / 0.02)

		# Tiny bass punch
		var punch = sin(TAU * 120.0 * t) * 0.25 * max(0.0, 1.0 - t / 0.015)

		var sample_val = (crack + ring + punch) * envelope
		sample_val = tanh(sample_val * 1.5) / tanh(1.5)

		var int_val = int(sample_val * 24000)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data

	fire_sound_player = AudioStreamPlayer2D.new()
	fire_sound_player.stream = audio
	fire_sound_player.volume_db = -2.0
	fire_sound_player.max_distance = 2000.0
	add_child(fire_sound_player)

# === Spool-up / spin-down motor whine ===
func _create_spool_sound():
	var sample_rate = 22050
	var duration = 0.2  # Short loop
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

		# Mechanical whir — layered sine tones
		var whir = sin(TAU * 180.0 * t) * 0.15
		whir += sin(TAU * 360.0 * t) * 0.08  # 2nd harmonic
		whir += sin(TAU * 540.0 * t) * 0.04  # 3rd harmonic

		# Bearing rattle
		var rattle = randf_range(-1.0, 1.0) * 0.05

		# Motor hum
		var hum = sin(TAU * 90.0 * t) * 0.08

		var sample_val = whir + rattle + hum
		sample_val = tanh(sample_val * 1.3) / tanh(1.3)

		var int_val = int(sample_val * 18000)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data

	spool_player = AudioStreamPlayer2D.new()
	spool_player.stream = audio
	spool_player.volume_db = -20.0  # Start silent
	spool_player.max_distance = 1800.0
	add_child(spool_player)
	spool_player.play()

func update_heat_visual():
	# Tint barrel tips red-hot when heated
	if has_node("Turret/BarrelGroup/Tip1"):
		var heat_color: Color
		if overheated:
			# Pulsing bright red/orange when overheated
			var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.012) * 0.3
			heat_color = Color(1.0, 0.15 * pulse, 0.05, 1)
		else:
			heat_color = Color(0.5 + heat * 0.5, 0.5 - heat * 0.35, 0.55 - heat * 0.5, 1)
		for tip_name in ["Tip1", "Tip2", "Tip3", "Tip4", "Tip5", "Tip6"]:
			if has_node("Turret/BarrelGroup/" + tip_name):
				$Turret/BarrelGroup.get_node(tip_name).color = heat_color
	
	# Tint housing at high heat
	if has_node("Turret/BarrelHousing"):
		if overheated:
			var pulse = 0.5 + sin(Time.get_ticks_msec() * 0.008) * 0.2
			$Turret/BarrelHousing.color = Color(0.6 + pulse * 0.2, 0.18, 0.1, 1)
		elif heat > 0.4:
			var t = (heat - 0.4) / 0.6
			$Turret/BarrelHousing.color = Color(0.32 + t * 0.35, 0.32 - t * 0.18, 0.37 - t * 0.28, 1)
		else:
			$Turret/BarrelHousing.color = Color(0.32, 0.32, 0.37, 1)
	
	# Tint muzzle ring
	if has_node("Turret/MuzzleRing"):
		if overheated:
			var pulse = 0.5 + sin(Time.get_ticks_msec() * 0.01) * 0.3
			$Turret/MuzzleRing.color = Color(0.7 + pulse * 0.15, 0.15, 0.08, 1)
		elif heat > 0.5:
			var t = (heat - 0.5) / 0.5
			$Turret/MuzzleRing.color = Color(0.28 + t * 0.4, 0.28 - t * 0.15, 0.33 - t * 0.25, 1)
		else:
			$Turret/MuzzleRing.color = Color(0.28, 0.28, 0.33, 1)

func start_firing():
	if not overheated:
		is_firing = true
		fire_timer = 0  # Fire immediately

func stop_firing():
	is_firing = false

func set_selected(selected: bool):
	is_selected = selected
	if not selected:
		stop_firing()
	
	if has_node("SelectionGlow"):
		$SelectionGlow.visible = selected
	if has_node("SelectionGlow2"):
		$SelectionGlow2.visible = selected
	
	if glow_tween:
		glow_tween.kill()
		glow_tween = null
	if selected and has_node("SelectionGlow"):
		glow_tween = create_tween().set_loops()
		glow_tween.tween_property($SelectionGlow, "color:a", 0.5, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		glow_tween.tween_property($SelectionGlow, "color:a", 0.25, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	if get_tree().current_scene.has_method("update_launcher_hud"):
		get_tree().current_scene.update_launcher_hud()

func get_launch_position() -> Vector2:
	if has_node("Turret"):
		var tip_offset = Vector2(0, -58).rotated($Turret.rotation)
		return global_position + tip_offset
	return global_position