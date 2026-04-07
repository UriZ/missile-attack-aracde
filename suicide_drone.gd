extends Area2D

enum State { WANDER, LOCK, DIVE }

var state = State.WANDER
var speed = 140.0
var dive_speed = 380.0
var velocity = Vector2.ZERO

# Wander
var wander_angle = 0.0
var target_angle = 0.0
var wander_turn_timer = 0.0
var lock_timer = 0.0
var lock_delay = randf_range(3.0, 5.0)

# Dive
var target_launcher = null

var destroyed = false

var explosion_scene = preload("res://explosion.tscn")
var mega_explosion_scene = preload("res://mega_explosion.tscn")
var crater_scene = preload("res://crater.tscn")

func _ready():
	add_to_group("enemy_missiles")
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func init(spawn_pos: Vector2):
	position = spawn_pos
	lock_delay = randf_range(3.0, 5.0)
	lock_timer = 0.0
	# Head toward center of playfield initially
	var to_center = (Vector2(1280.0, 500.0) - spawn_pos).normalized()
	wander_angle = to_center.angle()
	target_angle = wander_angle
	velocity = Vector2(cos(wander_angle), sin(wander_angle)) * speed

func _process(delta):
	if destroyed:
		return

	match state:
		State.WANDER:
			_process_wander(delta)
		State.LOCK:
			_find_target()
		State.DIVE:
			_process_dive(delta)

	position += velocity * delta

	# Off-screen: reflect or cleanup if too far
	if position.x < -300 or position.x > 2860 or position.y < -300 or position.y > 1600:
		queue_free()

func _process_wander(delta):
	lock_timer += delta

	# Periodically pick a new heading
	wander_turn_timer -= delta
	if wander_turn_timer <= 0:
		wander_turn_timer = randf_range(1.2, 2.5)
		target_angle = randf_range(-PI * 0.45, PI * 0.45)

	# Nudge away from screen edges
	if position.x < 150:
		target_angle = lerp_angle(target_angle, 0.0, 0.3)
	elif position.x > 2410:
		target_angle = lerp_angle(target_angle, PI, 0.3)
	if position.y < 120:
		target_angle = lerp_angle(target_angle, PI * 0.1, 0.3)
	elif position.y > 820:
		target_angle = lerp_angle(target_angle, -PI * 0.1, 0.3)

	wander_angle = lerp_angle(wander_angle, target_angle, 2.5 * delta)
	velocity = Vector2(cos(wander_angle), sin(wander_angle)) * speed
	$Visual.rotation = wander_angle

	# Wander glow pulse
	$Visual/EngineGlow.modulate.a = 0.5 + sin(Time.get_ticks_msec() * 0.007) * 0.35

	if lock_timer >= lock_delay:
		state = State.LOCK
		_flash_lock()

func _find_target():
	var launchers = get_tree().get_nodes_in_group("launchers")
	var closest: Node2D = null
	var closest_dist = INF
	for launcher in launchers:
		if is_instance_valid(launcher):
			var d = global_position.distance_to(launcher.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = launcher

	if closest:
		target_launcher = closest
		state = State.DIVE
	else:
		queue_free()  # No launchers left

func _process_dive(delta):
	if not is_instance_valid(target_launcher):
		# Target gone — re-lock on another launcher quickly
		state = State.WANDER
		lock_timer = lock_delay
		return

	var to_target = (target_launcher.global_position - global_position).normalized()
	velocity = velocity.lerp(to_target * dive_speed, 6.0 * delta)
	$Visual.rotation = velocity.angle()

	# Rapidly pulsing red glow during dive
	var pulse = 0.5 + sin(Time.get_ticks_msec() * 0.025) * 0.5
	$Visual/EngineGlow.modulate.a = pulse
	$Visual/Body.modulate = Color(1.0 + pulse * 0.4, 1.0, 1.0, 1.0)

func _flash_lock():
	# Brief flash to signal acquiring target
	var tween = create_tween()
	tween.tween_property($Visual, "modulate", Color(2.0, 0.6, 0.3, 1.0), 0.12)
	tween.tween_property($Visual, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
	tween.tween_property($Visual, "modulate", Color(2.0, 0.6, 0.3, 1.0), 0.10)
	tween.tween_property($Visual, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.10)

func _on_area_entered(area):
	if destroyed:
		return
	if area.is_in_group("launchers"):
		destroyed = true
		var terrain_nodes = get_tree().get_nodes_in_group("terrain")
		for terrain in terrain_nodes:
			if terrain.has_method("damage"):
				terrain.damage(area.global_position, 110.0, 80.0)

		var main = get_tree().current_scene
		if main.has_method("shake_screen"):
			main.shake_screen(28.0)

		var mega = mega_explosion_scene.instantiate()
		mega.position = area.global_position
		get_parent().add_child(mega)

		var crater = crater_scene.instantiate()
		crater.position = area.global_position
		crater.scale = Vector2(3.0, 3.0)
		crater.z_index = -1
		get_parent().add_child(crater)

		area.queue_free()
		queue_free()

func _on_body_entered(body):
	if destroyed:
		return
	if body.is_in_group("terrain"):
		destroyed = true
		var explosion = explosion_scene.instantiate()
		explosion.position = position
		get_parent().add_child(explosion)
		if body.has_method("damage"):
			body.damage(global_position, 60.0, 40.0)
		queue_free()
