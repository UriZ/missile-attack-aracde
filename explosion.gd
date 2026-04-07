extends Node2D

# Procedural visual effect state
var is_mega: bool = false
var elapsed: float = 0.0
var total_lifetime: float = 1.5
var fireball_radius: float = 0.0
var fireball_max_radius: float = 40.0
var shockwave_radius: float = 0.0
var shockwave_max_radius: float = 120.0
var glow_alpha: float = 1.0
var heat_shimmer_offset: float = 0.0
var screen_shake_intensity: float = 0.0
var flash_alpha: float = 1.0

# Scorchmark / ground burn
var scorch_rings: Array = []

# === Aftermath debris system ===
var debris_chunks: Array = []   # flying metal/rock pieces with physics
var spark_trails: Array = []    # bright arcing sparks with trails
var cinders: Array = []         # slow-falling glowing ash
var smoke_wisps: Array = []     # curling smoke tendrils from debris
var secondary_pops: Array = []  # delayed mini-flashes

func _ready():
	is_mega = name == "MegaExplosion"

	# Scale effects for mega
	if is_mega:
		fireball_max_radius = 80.0
		shockwave_max_radius = 220.0
		total_lifetime = 2.8
	else:
		total_lifetime = 2.0

	# Generate random scorch ring radii for ground burn effect
	var num_rings = 4 if not is_mega else 6
	for i in range(num_rings):
		scorch_rings.append({
			"radius": randf_range(8.0, fireball_max_radius * 0.8),
			"angle": randf_range(0, TAU),
			"width": randf_range(2.0, 5.0)
		})

	# === Generate aftermath debris ===
	_spawn_debris_chunks()
	_spawn_spark_trails()
	_spawn_cinders()
	_spawn_smoke_wisps()
	_spawn_secondary_pops()

	# Play explosion sound
	play_explosion_sound()

	# Trigger screen shake
	_apply_screen_shake()

	# Auto-delete after all visual effects finish
	await get_tree().create_timer(total_lifetime).timeout
	queue_free()

# --- Debris generation ---
func _spawn_debris_chunks():
	var count = 12 if not is_mega else 22
	for i in range(count):
		var angle = randf_range(0, TAU)
		var speed = randf_range(80.0, 260.0) if not is_mega else randf_range(120.0, 380.0)
		var chunk = {
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * speed + Vector2(0, randf_range(-80, -20)),
			"rot": 0.0,
			"spin": randf_range(-15.0, 15.0),
			"size": randf_range(2.0, 6.0) if not is_mega else randf_range(3.0, 9.0),
			"shape": randi() % 3,  # 0=triangle, 1=rect, 2=irregular
			"color_base": [
				Color(0.5, 0.4, 0.3),   # rock/dirt
				Color(0.65, 0.65, 0.6),  # metal
				Color(0.35, 0.3, 0.25),  # dark debris
				Color(0.7, 0.5, 0.2),    # burnt orange
			].pick_random(),
			"trail": [] as Array,  # previous positions for smoke trail
			"alive": true,
			"drag": randf_range(0.3, 0.8),
			"on_fire": randf() < 0.3,  # some chunks are burning
		}
		debris_chunks.append(chunk)

func _spawn_spark_trails():
	var count = 8 if not is_mega else 16
	for i in range(count):
		var angle = randf_range(0, TAU)
		var speed = randf_range(150.0, 400.0) if not is_mega else randf_range(200.0, 550.0)
		var spark = {
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * speed + Vector2(0, randf_range(-120, -30)),
			"trail_points": [] as Array,
			"max_trail": randi_range(6, 14),
			"lifetime": randf_range(0.4, 1.0),
			"age": 0.0,
			"brightness": randf_range(0.7, 1.0),
			"color": [Color(1, 0.9, 0.4), Color(1, 0.7, 0.2), Color(1, 0.5, 0.1)].pick_random(),
		}
		spark_trails.append(spark)

func _spawn_cinders():
	var count = 15 if not is_mega else 30
	for i in range(count):
		var angle = randf_range(0, TAU)
		var dist = randf_range(5.0, fireball_max_radius * 0.8)
		var cinder = {
			"pos": Vector2(cos(angle), sin(angle)) * dist + Vector2(0, randf_range(-40, -10)),
			"vel": Vector2(randf_range(-15, 15), randf_range(-50, -15)),
			"size": randf_range(0.8, 2.5),
			"glow": randf_range(0.5, 1.0),
			"wobble_phase": randf_range(0, TAU),
			"wobble_freq": randf_range(3.0, 8.0),
			"lifetime": randf_range(0.8, total_lifetime * 0.85),
			"age": 0.0,
		}
		cinders.append(cinder)

func _spawn_smoke_wisps():
	var count = 5 if not is_mega else 9
	for i in range(count):
		var angle = randf_range(0, TAU)
		var dist = randf_range(10, fireball_max_radius * 0.5)
		var wisp = {
			"base_pos": Vector2(cos(angle), sin(angle)) * dist,
			"offset_y": 0.0,
			"drift_x": randf_range(-12, 12),
			"rise_speed": randf_range(20.0, 50.0),
			"size": randf_range(4.0, 10.0) if not is_mega else randf_range(6.0, 16.0),
			"alpha": randf_range(0.15, 0.35),
			"wobble_phase": randf_range(0, TAU),
			"delay": randf_range(0.1, 0.6),  # delayed start
		}
		smoke_wisps.append(wisp)

func _spawn_secondary_pops():
	var count = 4 if not is_mega else 8
	for i in range(count):
		var angle = randf_range(0, TAU)
		var dist = randf_range(15.0, fireball_max_radius * 1.2)
		secondary_pops.append({
			"pos": Vector2(cos(angle), sin(angle)) * dist,
			"time": randf_range(0.15, 0.7),  # when it pops
			"radius": randf_range(5.0, 14.0) if not is_mega else randf_range(8.0, 22.0),
			"current_radius": 0.0,
			"alpha": 0.0,
			"fired": false,
		})

func _process(delta: float) -> void:
	elapsed += delta
	var progress = clamp(elapsed / total_lifetime, 0.0, 1.0)
	var gravity = Vector2(0, 320.0)

	# Phase 1: Flash (0-0.08s)
	if elapsed < 0.08:
		flash_alpha = 1.0 - (elapsed / 0.08)
	else:
		flash_alpha = 0.0

	# Phase 2: Fireball expansion and fade
	var fireball_duration = 0.4 if not is_mega else 0.6
	if elapsed < fireball_duration:
		var fb_progress = elapsed / fireball_duration
		fireball_radius = fireball_max_radius * (1.0 - pow(1.0 - fb_progress, 3.0))
		glow_alpha = 1.0 - pow(fb_progress, 2.0)
	else:
		glow_alpha = 0.0

	# Phase 3: Shockwave ring expansion
	var shock_start = 0.02
	var shock_duration = 0.5 if not is_mega else 0.8
	if elapsed > shock_start and elapsed < shock_start + shock_duration:
		var shock_progress = (elapsed - shock_start) / shock_duration
		shockwave_radius = shockwave_max_radius * shock_progress
	else:
		shockwave_radius = 0.0

	# Heat shimmer wobble
	heat_shimmer_offset = sin(elapsed * 25.0) * 3.0 * max(0.0, 1.0 - progress * 1.5)

	# Screen shake decay
	screen_shake_intensity = max(0.0, screen_shake_intensity - delta * 40.0)

	# === Physics-step debris chunks ===
	for chunk in debris_chunks:
		if not chunk["alive"]:
			continue
		chunk["vel"] += gravity * delta
		chunk["vel"] *= (1.0 - chunk["drag"] * delta)
		chunk["pos"] += chunk["vel"] * delta
		chunk["rot"] += chunk["spin"] * delta
		# Store trail point every few frames for smoke trail
		if chunk["trail"].size() == 0 or chunk["pos"].distance_to(chunk["trail"][-1]) > 8.0:
			chunk["trail"].append(chunk["pos"])
			if chunk["trail"].size() > 8:
				chunk["trail"].pop_front()
		# Kill if off-screen or too old
		if chunk["pos"].y > 300 or elapsed > total_lifetime * 0.9:
			chunk["alive"] = false

	# === Physics-step spark trails ===
	for spark in spark_trails:
		spark["age"] += delta
		if spark["age"] > spark["lifetime"]:
			continue
		spark["vel"] += gravity * 1.5 * delta  # sparks fall faster
		spark["vel"] *= 0.97  # air drag
		spark["pos"] += spark["vel"] * delta
		spark["trail_points"].append(spark["pos"])
		if spark["trail_points"].size() > spark["max_trail"]:
			spark["trail_points"].pop_front()

	# === Update cinders ===
	for cinder in cinders:
		cinder["age"] += delta
		if cinder["age"] > cinder["lifetime"]:
			continue
		# Gentle sideways wobble as they fall
		var wobble = sin(cinder["age"] * cinder["wobble_freq"] + cinder["wobble_phase"]) * 20.0
		cinder["vel"].x = wobble
		cinder["vel"].y += 15.0 * delta  # slow gravity
		cinder["pos"] += cinder["vel"] * delta
		# Glow flickers
		cinder["glow"] = 0.4 + 0.6 * abs(sin(cinder["age"] * 8.0 + cinder["wobble_phase"]))

	# === Update secondary pops ===
	for pop in secondary_pops:
		if not pop["fired"] and elapsed >= pop["time"]:
			pop["fired"] = true
			pop["alpha"] = 1.0
			pop["current_radius"] = pop["radius"] * 0.3
		if pop["fired"] and pop["alpha"] > 0.0:
			pop["current_radius"] = move_toward(pop["current_radius"], pop["radius"], delta * pop["radius"] * 6.0)
			pop["alpha"] = move_toward(pop["alpha"], 0.0, delta * 4.0)

	queue_redraw()

func _draw() -> void:
	var progress = clamp(elapsed / total_lifetime, 0.0, 1.0)

	# === White flash overlay ===
	if flash_alpha > 0.01:
		var flash_size = fireball_max_radius * 3.0
		draw_circle(Vector2.ZERO, flash_size, Color(1, 1, 0.95, flash_alpha * 0.7))

	# === Fireball glow (layered circles) ===
	if glow_alpha > 0.01 and fireball_radius > 1.0:
		var outer_r = fireball_radius * 1.3
		draw_circle(Vector2(heat_shimmer_offset * 0.3, 0), outer_r,
			Color(1.0, 0.4, 0.05, glow_alpha * 0.3))
		draw_circle(Vector2(-heat_shimmer_offset * 0.2, heat_shimmer_offset * 0.1),
			fireball_radius, Color(1.0, 0.65, 0.1, glow_alpha * 0.5))
		var inner_r = fireball_radius * 0.5
		draw_circle(Vector2(heat_shimmer_offset * 0.15, -heat_shimmer_offset * 0.1),
			inner_r, Color(1.0, 0.9, 0.5, glow_alpha * 0.8))
		var center_r = fireball_radius * 0.2
		draw_circle(Vector2.ZERO, center_r, Color(1.0, 1.0, 0.9, glow_alpha * 0.9))

	# === Shockwave ring ===
	if shockwave_radius > 5.0:
		var shock_progress = shockwave_radius / shockwave_max_radius
		var ring_alpha = (1.0 - shock_progress) * 0.4
		var ring_width = 3.0 if not is_mega else 5.0
		var segments = 32
		for i in range(segments):
			var a1 = TAU * i / segments
			var a2 = TAU * (i + 1) / segments
			var p1 = Vector2(cos(a1), sin(a1)) * shockwave_radius
			var p2 = Vector2(cos(a2), sin(a2)) * shockwave_radius
			draw_line(p1, p2, Color(1, 0.85, 0.5, ring_alpha), ring_width, true)

	# === Secondary pops (delayed mini-explosions) ===
	for pop in secondary_pops:
		if pop["fired"] and pop["alpha"] > 0.01:
			var r = pop["current_radius"]
			draw_circle(pop["pos"], r, Color(1, 0.7, 0.2, pop["alpha"] * 0.6))
			draw_circle(pop["pos"], r * 0.5, Color(1, 0.9, 0.5, pop["alpha"] * 0.8))
			# Outer ring
			var ring_segs = 16
			for i in range(ring_segs):
				var a1 = TAU * i / ring_segs
				var a2 = TAU * (i + 1) / ring_segs
				var rp1 = pop["pos"] + Vector2(cos(a1), sin(a1)) * r * 1.3
				var rp2 = pop["pos"] + Vector2(cos(a2), sin(a2)) * r * 1.3
				draw_line(rp1, rp2, Color(1, 0.6, 0.15, pop["alpha"] * 0.3), 1.5)

	# === Debris chunk smoke trails ===
	for chunk in debris_chunks:
		var trail: Array = chunk["trail"]
		if trail.size() >= 2:
			for k in range(trail.size() - 1):
				var t_progress = float(k) / trail.size()
				var trail_alpha = t_progress * 0.2 * (1.0 - progress)
				if chunk["on_fire"]:
					draw_line(trail[k], trail[k + 1],
						Color(0.9, 0.4, 0.1, trail_alpha * 1.5), 2.5)
				else:
					draw_line(trail[k], trail[k + 1],
						Color(0.3, 0.3, 0.3, trail_alpha), 2.0)

	# === Debris chunks (polygon shapes) ===
	for chunk in debris_chunks:
		if not chunk["alive"]:
			continue
		var p: Vector2 = chunk["pos"]
		var r: float = chunk["rot"]
		var s: float = chunk["size"]
		var c: Color = chunk["color_base"]
		var age_fade = clamp(1.0 - progress * 1.1, 0.0, 1.0)
		c.a = age_fade

		var points: PackedVector2Array
		match chunk["shape"]:
			0:  # triangle
				points = PackedVector2Array([
					p + Vector2(cos(r), sin(r)) * s,
					p + Vector2(cos(r + 2.2), sin(r + 2.2)) * s * 0.8,
					p + Vector2(cos(r + 4.0), sin(r + 4.0)) * s * 0.6,
				])
			1:  # rectangle
				var hw = s * 0.5
				var hh = s * 0.3
				points = PackedVector2Array([
					p + Vector2(cos(r) * hw - sin(r) * hh, sin(r) * hw + cos(r) * hh),
					p + Vector2(cos(r) * hw + sin(r) * hh, sin(r) * hw - cos(r) * hh),
					p + Vector2(-cos(r) * hw + sin(r) * hh, -sin(r) * hw - cos(r) * hh),
					p + Vector2(-cos(r) * hw - sin(r) * hh, -sin(r) * hw + cos(r) * hh),
				])
			_:  # irregular
				points = PackedVector2Array()
				var nverts = randi_range(4, 6)
				for v in range(nverts):
					var a = r + TAU * v / nverts
					var d = s * randf_range(0.5, 1.0)
					points.append(p + Vector2(cos(a), sin(a)) * d)

		if points.size() >= 3:
			draw_colored_polygon(points, c)
			# Highlight edge on burning chunks
			if chunk["on_fire"]:
				var fire_flicker = 0.6 + 0.4 * sin(elapsed * 15.0 + chunk["spin"])
				draw_circle(p, s * 0.4, Color(1, 0.5, 0.1, 0.4 * fire_flicker * age_fade))

	# === Spark trails ===
	for spark in spark_trails:
		if spark["age"] > spark["lifetime"]:
			continue
		var spark_alpha = 1.0 - spark["age"] / spark["lifetime"]
		var trail: Array = spark["trail_points"]
		var sc: Color = spark["color"]
		# Draw trail as fading line segments
		if trail.size() >= 2:
			for k in range(trail.size() - 1):
				var seg_alpha = float(k) / trail.size() * spark_alpha * spark["brightness"]
				draw_line(trail[k], trail[k + 1],
					Color(sc.r, sc.g, sc.b, seg_alpha), 1.5)
		# Bright head
		if trail.size() > 0:
			var head = trail[-1]
			draw_circle(head, 1.5, Color(sc.r, sc.g, sc.b, spark_alpha * spark["brightness"]))
			# Hot core
			draw_circle(head, 0.8, Color(1, 1, 0.9, spark_alpha * 0.8))

	# === Falling cinders / glowing ash ===
	for cinder in cinders:
		if cinder["age"] > cinder["lifetime"]:
			continue
		var cinder_alpha = (1.0 - cinder["age"] / cinder["lifetime"]) * 0.7
		var g = cinder["glow"]
		var cp = cinder["pos"]
		var cs = cinder["size"]
		# Glowing ember dot
		draw_circle(cp, cs, Color(1.0, 0.4 + g * 0.3, 0.1, cinder_alpha * g))
		# Tiny orange halo
		draw_circle(cp, cs * 2.0, Color(1.0, 0.3, 0.05, cinder_alpha * g * 0.2))

	# === Smoke wisps rising from blast site ===
	for wisp in smoke_wisps:
		if elapsed < wisp["delay"]:
			continue
		var wisp_age = elapsed - wisp["delay"]
		var wisp_alpha = wisp["alpha"] * clamp(1.0 - progress * 1.3, 0.0, 1.0)
		if wisp_alpha < 0.01:
			continue
		var bx = wisp["base_pos"].x + sin(wisp_age * 2.5 + wisp["wobble_phase"]) * wisp["drift_x"]
		var by = wisp["base_pos"].y - wisp_age * wisp["rise_speed"]
		var ws = wisp["size"] + wisp_age * 6.0  # grows as it rises
		# Draw as overlapping translucent circles
		draw_circle(Vector2(bx, by), ws, Color(0.25, 0.22, 0.2, wisp_alpha * 0.5))
		draw_circle(Vector2(bx + ws * 0.3, by - ws * 0.2), ws * 0.7,
			Color(0.3, 0.27, 0.24, wisp_alpha * 0.35))
		draw_circle(Vector2(bx - ws * 0.2, by - ws * 0.4), ws * 0.5,
			Color(0.22, 0.2, 0.18, wisp_alpha * 0.25))

	# === Heat distortion lines (rising wavy lines above explosion) ===
	if progress < 0.7:
		var heat_alpha = (1.0 - progress / 0.7) * 0.25
		var num_lines = 4 if not is_mega else 7
		for i in range(num_lines):
			var x_base = (i - num_lines / 2.0) * 12.0
			var wave_points: PackedVector2Array = PackedVector2Array()
			for j in range(10):
				var y_off = -20.0 - j * 12.0 - elapsed * 45.0
				var x_off = x_base + sin(elapsed * 8.0 + j * 0.7 + i) * 8.0
				wave_points.append(Vector2(x_off, y_off))
			if wave_points.size() >= 2:
				for k in range(wave_points.size() - 1):
					draw_line(wave_points[k], wave_points[k + 1],
						Color(1, 0.6, 0.2, heat_alpha * (1.0 - float(k) / wave_points.size())),
						1.5, true)

	# === Ground scorch / burn mark ===
	if progress > 0.1:
		var scorch_alpha = clamp((progress - 0.1) * 2.0, 0.0, 1.0) * 0.3
		var scorch_r = fireball_max_radius * 0.6
		draw_circle(Vector2(0, 2), scorch_r, Color(0.1, 0.08, 0.05, scorch_alpha))
		for ring_data in scorch_rings:
			var r = ring_data["radius"]
			var a = ring_data["angle"]
			var w = ring_data["width"]
			var pt = Vector2(cos(a), sin(a)) * r * 0.4
			draw_circle(pt + Vector2(0, 2), w, Color(0.15, 0.1, 0.05, scorch_alpha * 0.5))

	# === Lingering embers glow (late phase) ===
	if progress > 0.2 and progress < 0.9:
		var ember_alpha = sin((progress - 0.2) / 0.7 * PI) * 0.2
		var ember_count = 6 if not is_mega else 12
		for i in range(ember_count):
			var seed_angle = (float(i) / ember_count) * TAU + elapsed * 0.5
			var seed_dist = fireball_max_radius * 0.35 * (0.5 + 0.5 * sin(i * 2.3))
			var ember_pos = Vector2(cos(seed_angle), sin(seed_angle)) * seed_dist
			var flicker = 0.5 + 0.5 * sin(elapsed * 12.0 + i * 1.7)
			draw_circle(ember_pos, 2.5 + flicker * 1.5, Color(1.0, 0.5, 0.1, ember_alpha * flicker))
			# Tiny hot center
			draw_circle(ember_pos, 1.0, Color(1, 0.85, 0.4, ember_alpha * flicker * 0.7))

func _apply_screen_shake() -> void:
	var camera = get_viewport().get_camera_2d()
	if camera == null:
		return

	var intensity = 8.0 if not is_mega else 18.0
	var duration = 0.3 if not is_mega else 0.6
	var shakes = 12 if not is_mega else 20

	# Animate shake via tween
	var tween = create_tween()
	var shake_interval = duration / shakes
	for i in range(shakes):
		var strength = intensity * (1.0 - float(i) / shakes)
		var offset = Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
		tween.tween_property(camera, "offset", offset, shake_interval)
	# Return to center
	tween.tween_property(camera, "offset", Vector2.ZERO, shake_interval)

func play_explosion_sound():
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
