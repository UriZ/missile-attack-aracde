extends Node2D

var missile_scene = preload("res://missile.tscn")
var heat_seeking_missile_scene = preload("res://heat_seeking_missile.tscn")
var sam_launcher_scene = preload("res://sam_launcher.tscn")
var truck_launcher_scene = preload("res://truck_launcher.tscn")
var heat_seeking_launcher_scene = preload("res://heat_seeking_launcher.tscn")
var enemy_missile_scene = preload("res://enemy_missile.tscn")
var super_missile_scene = preload("res://super_missile.tscn")
var terrain_scene = preload("res://terrain.tscn")

var selected_launcher = null
var enemy_spawn_timer = 0.0
var enemy_spawn_interval = 3.0  # spawn every 3 seconds
var super_missile_timer = 0.0
var super_missile_interval = 12.0  # spawn super missile every 12 seconds
var score = 0
var crosshair_radius = 50.0  # Detection radius for heat-seeking lock
var game_over = false
var game_started = false
var crosshair_cursor = null
var crosshair_locked_cursor = null
var shake_amount = 0.0
var shake_decay = 5.0  # How fast shake fades
var play_button_tween: Tween = null
var bg_missile_timer = 0.0

func _ready():
	# Create crosshair cursors from code
	crosshair_cursor = create_crosshair_texture(false)
	crosshair_locked_cursor = create_crosshair_texture(true)

	# Hide game over screen initially
	$UI/GameOver.visible = false

	# Show start screen
	$UI/StartScreen.visible = true
	$UI/StartScreen/PlayButton.pressed.connect(_on_play_pressed)
	$UI/GameOver/PlayAgainButton.pressed.connect(_on_play_again_pressed)

	animate_start_screen()
	update_score_display()

func _process(delta):
	# Always process screen shake even during game over
	apply_screen_shake(delta)

	# Animate background missiles on start screen
	if not game_started and not game_over and $UI/StartScreen.visible:
		bg_missile_timer += delta
		if bg_missile_timer >= 0.4:
			bg_missile_timer = 0.0
			spawn_bg_missile()

	if game_over or not game_started:
		return

	# Check if selected launcher was destroyed
	if selected_launcher and not is_instance_valid(selected_launcher):
		selected_launcher = null
		Input.set_custom_mouse_cursor(null)  # Reset cursor
		$UI/Info.text = "Launcher destroyed! Select another launcher"

	# Check for game over (all launchers destroyed)
	var launchers = get_tree().get_nodes_in_group("launchers")
	if launchers.size() == 0:
		trigger_game_over()
		return

	# Spawn enemy missiles periodically
	enemy_spawn_timer += delta
	if enemy_spawn_timer >= enemy_spawn_interval:
		enemy_spawn_timer = 0.0
		spawn_enemy_missile()

	# Spawn super missiles periodically
	super_missile_timer += delta
	if super_missile_timer >= super_missile_interval:
		super_missile_timer = 0.0
		spawn_super_missile()

	# Redraw crosshair if heat-seeking launcher selected
	if selected_launcher and is_instance_valid(selected_launcher) and selected_launcher.name.begins_with("HeatSeekingLauncher"):
		# Swap cursor based on lock
		var enemy_near = find_enemy_near_cursor(get_global_mouse_position())
		if enemy_near:
			Input.set_custom_mouse_cursor(crosshair_locked_cursor, Input.CURSOR_ARROW, Vector2(16, 16))
		else:
			Input.set_custom_mouse_cursor(crosshair_cursor, Input.CURSOR_ARROW, Vector2(16, 16))
		queue_redraw()
	else:
		queue_redraw()  # Clear crosshair

func apply_screen_shake(delta):
	if shake_amount > 0.01:
		var offset = Vector2(
			randf_range(-shake_amount, shake_amount),
			randf_range(-shake_amount, shake_amount)
		)
		$Camera2D.offset = offset
		shake_amount = lerp(shake_amount, 0.0, shake_decay * delta)
	else:
		shake_amount = 0.0
		$Camera2D.offset = Vector2.ZERO

func shake_screen(intensity: float = 15.0):
	shake_amount = max(shake_amount, intensity)

func create_crosshair_texture(locked: bool = false) -> ImageTexture:
	var size = 32
	var center = size / 2
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # Transparent

	var main_color: Color
	var shadow_color: Color
	if locked:
		main_color = Color(1, 0.2, 0.1, 1)  # Bright red
		shadow_color = Color(1, 1, 0, 0.9)  # Yellow glow
	else:
		main_color = Color(0.9, 0.15, 0.1, 0.85)  # Red
		shadow_color = Color(0.3, 0.05, 0.02, 0.6)  # Dark red

	var thickness = 2 if locked else 1

	# Draw crosshair lines (horizontal)
	for x in range(3, size - 3):
		if abs(x - center) > 3:  # Gap in center
			for t in range(thickness):
				img.set_pixel(x, center + t, main_color)
				img.set_pixel(x, center - 1 - t, shadow_color)

	# Draw crosshair lines (vertical)
	for y in range(3, size - 3):
		if abs(y - center) > 3:  # Gap in center
			for t in range(thickness):
				img.set_pixel(center + t, y, main_color)
				img.set_pixel(center - 1 - t, y, shadow_color)

	# Draw center dot (bigger when locked)
	var dot_size = 2 if locked else 1
	for dx in range(-dot_size, dot_size + 1):
		for dy in range(-dot_size, dot_size + 1):
			var px = center + dx
			var py = center + dy
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, main_color)

	# Draw corner brackets (thicker when locked)
	var bracket_len = 5 if locked else 4
	for i in range(bracket_len):
		for t in range(thickness):
			# Top-left
			img.set_pixel(2 + i, 2 + t, main_color)
			img.set_pixel(2 + t, 2 + i, main_color)
			# Top-right
			img.set_pixel(size - 3 - i, 2 + t, main_color)
			img.set_pixel(size - 3 - t, 2 + i, main_color)
			# Bottom-left
			img.set_pixel(2 + i, size - 3 - t, main_color)
			img.set_pixel(2 + t, size - 3 - i, main_color)
			# Bottom-right
			img.set_pixel(size - 3 - i, size - 3 - t, main_color)
			img.set_pixel(size - 3 - t, size - 3 - i, main_color)

	return ImageTexture.create_from_image(img)

func animate_start_screen():
	var title = $UI/StartScreen/Title
	var subtitle = $UI/StartScreen/Subtitle
	var play_btn = $UI/StartScreen/PlayButton

	# Hide everything initially
	title.modulate.a = 0.0
	title.position.y -= 60
	subtitle.modulate.a = 0.0
	play_btn.modulate.a = 0.0
	play_btn.scale = Vector2(0.5, 0.5)
	play_btn.pivot_offset = play_btn.size / 2

	# Title: slide down + fade in
	var title_tween = create_tween().set_parallel(true)
	title_tween.tween_property(title, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_OUT)
	title_tween.tween_property(title, "position:y", title.position.y + 60, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Title scale punch
	var title_scale_tween = create_tween()
	title.pivot_offset = title.size / 2
	title_scale_tween.tween_property(title, "scale", Vector2(1.05, 1.05), 0.5).from(Vector2(0.8, 0.8)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3)
	title_scale_tween.tween_property(title, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_SINE)

	# Subtitle: fade in after title
	var sub_tween = create_tween()
	sub_tween.tween_property(subtitle, "modulate:a", 1.0, 0.6).set_delay(0.7).set_ease(Tween.EASE_OUT)

	# Play button: scale up + fade in with bounce
	var btn_tween = create_tween().set_parallel(true)
	btn_tween.tween_property(play_btn, "modulate:a", 1.0, 0.5).set_delay(1.2).set_ease(Tween.EASE_OUT)
	btn_tween.tween_property(play_btn, "scale", Vector2(1.0, 1.0), 0.6).set_delay(1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# Play button: continuous pulse after appearing
	await get_tree().create_timer(2.0).timeout
	if $UI/StartScreen.visible:
		start_play_button_pulse()

func start_play_button_pulse():
	var play_btn = $UI/StartScreen/PlayButton
	if play_button_tween:
		play_button_tween.kill()
	play_button_tween = create_tween().set_loops()
	play_button_tween.tween_property(play_btn, "scale", Vector2(1.08, 1.08), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	play_button_tween.tween_property(play_btn, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func spawn_bg_missile():
	# Decorative missiles falling in the background behind the start screen
	var bg = $UI/StartScreen/Overlay
	var missile_label = Label.new()
	missile_label.text = ["🚀", "💥", "☄️"].pick_random()
	missile_label.add_theme_font_size_override("font_size", randi_range(18, 36))
	missile_label.modulate = Color(1, 1, 1, randf_range(0.15, 0.35))
	missile_label.position = Vector2(randf_range(50, 2500), -40)
	missile_label.rotation = randf_range(0.3, 1.2)
	bg.add_child(missile_label)

	var duration = randf_range(2.5, 5.0)
	var end_x = missile_label.position.x + randf_range(-200, 200)
	var fall_tween = create_tween().set_parallel(true)
	fall_tween.tween_property(missile_label, "position:y", 1500.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall_tween.tween_property(missile_label, "position:x", end_x, duration)
	fall_tween.tween_property(missile_label, "rotation", missile_label.rotation + randf_range(1.0, 3.0), duration)

	# Cleanup after animation
	get_tree().create_timer(duration + 0.5).timeout.connect(func():
		if is_instance_valid(missile_label):
			missile_label.queue_free()
	)

func _draw():
	# Draw crosshair overlay for heat-seeking launcher
	if selected_launcher and is_instance_valid(selected_launcher) and selected_launcher.name.begins_with("HeatSeekingLauncher"):
		var mouse_pos = get_global_mouse_position()

		# Check if enemy in range
		var locked_enemy = find_enemy_near_cursor(mouse_pos)
		var color = Color(1, 0.2, 0.1, 1) if locked_enemy else Color(0.9, 0.15, 0.1, 0.5)

		# Draw lock circle
		var ring_width = 3.0 if locked_enemy else 1.5
		draw_arc(mouse_pos, crosshair_radius, 0, TAU, 32, color, ring_width)

		# Draw lock indicator if locked
		if locked_enemy and is_instance_valid(locked_enemy):
			draw_circle(locked_enemy.global_position, 12, Color(1, 0, 0, 0.2))
			draw_arc(locked_enemy.global_position, 20, 0, TAU, 16, Color(1, 0.2, 0, 1), 2.5)

			# Draw line from cursor to target
			draw_line(mouse_pos, locked_enemy.global_position, Color(1, 0.3, 0, 0.6), 2.0)

func _unhandled_input(event):
	if game_over or not game_started:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Main received click at: ", get_global_mouse_position())
		if selected_launcher != null:
			var target = get_global_mouse_position()
			print("Firing missile to: ", target)
			spawn_missile(target)

func spawn_random_launchers():
	# Spawn 1 SAM site
	var sam = sam_launcher_scene.instantiate()
	sam.position = Vector2(400, 1220)
	add_child(sam)
	sam.launcher_clicked.connect(_on_launcher_selected)
	selected_launcher = sam
	sam.set_selected(true)

	# Spawn 1 heat-seeking launcher
	var heat_seeker = heat_seeking_launcher_scene.instantiate()
	heat_seeker.position = Vector2(900, 1220)
	add_child(heat_seeker)
	heat_seeker.launcher_clicked.connect(_on_launcher_selected)

	# Spawn 1 truck launcher
	var truck = truck_launcher_scene.instantiate()
	truck.position = Vector2(1400, 1220)
	add_child(truck)
	truck.launcher_clicked.connect(_on_launcher_selected)

	# Spawn another SAM site
	var sam2 = sam_launcher_scene.instantiate()
	sam2.position = Vector2(1900, 1220)
	add_child(sam2)
	sam2.launcher_clicked.connect(_on_launcher_selected)

func spawn_enemy_missile():
	var enemy = enemy_missile_scene.instantiate()

	# Spawn from top or sides
	var spawn_side = randi() % 3
	if spawn_side == 0:  # Top
		enemy.position = Vector2(randf_range(200, 2360), -50)
	elif spawn_side == 1:  # Left
		enemy.position = Vector2(-50, randf_range(100, 400))
	else:  # Right
		enemy.position = Vector2(2610, randf_range(100, 400))

	# Target terrain/launcher area
	var target = Vector2(randf_range(300, 2260), randf_range(1180, 1260))

	add_child(enemy)
	enemy.launch_to(target, randf_range(3.5, 5.5))

func spawn_super_missile():
	var super_m = super_missile_scene.instantiate()

	# Always spawn from the top - high altitude drop
	super_m.position = Vector2(randf_range(300, 2260), -100)

	# Target launcher area
	var target = Vector2(randf_range(300, 2260), randf_range(1180, 1260))

	add_child(super_m)
	super_m.launch_to(target, randf_range(8.0, 11.0))  # Very slow

func _on_launcher_selected(launcher):
	if selected_launcher:
		selected_launcher.set_selected(false)
	selected_launcher = launcher
	selected_launcher.set_selected(true)

	# Change cursor based on launcher type
	if launcher.name.begins_with("HeatSeekingLauncher"):
		if crosshair_cursor:
			Input.set_custom_mouse_cursor(crosshair_cursor, Input.CURSOR_ARROW, Vector2(16, 16))
		$UI/Info.text = "Heat-Seeking Launcher - aim at enemy missiles"
	else:
		Input.set_custom_mouse_cursor(null)  # Default cursor
		$UI/Info.text = "Launcher selected - click to fire"

func spawn_missile(target_pos):
	if selected_launcher == null:
		return

	# Check if this is a heat-seeking launcher
	var is_heat_seeker = selected_launcher.name.begins_with("HeatSeekingLauncher")

	var missile
	var locked_target = null

	if is_heat_seeker:
		# Find enemy missiles near cursor
		locked_target = find_enemy_near_cursor(target_pos)
		missile = heat_seeking_missile_scene.instantiate()
	else:
		missile = missile_scene.instantiate()

	missile.position = selected_launcher.get_launch_position()
	missile.enemy_destroyed.connect(_on_enemy_destroyed)
	add_child(missile)

	if is_heat_seeker:
		missile.launch_to(target_pos, locked_target)
	else:
		missile.launch_to(target_pos)

func find_enemy_near_cursor(cursor_pos: Vector2):
	var enemies = get_tree().get_nodes_in_group("enemy_missiles")
	var closest_enemy = null
	var closest_distance = crosshair_radius

	for enemy in enemies:
		var distance = enemy.global_position.distance_to(cursor_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest_enemy = enemy

	return closest_enemy

func _on_enemy_destroyed():
	score += 1
	update_score_display()

func update_score_display():
	$UI/Score.text = "Score: " + str(score)

func trigger_game_over():
	game_over = true
	$UI/GameOver.visible = true
	Input.set_custom_mouse_cursor(null)

	# Animate game over text
	var tween = create_tween()
	tween.tween_property($UI/GameOver/Label, "modulate:a", 1.0, 1.0).from(0.0)
	tween.tween_property($UI/GameOver/Label, "scale", Vector2(1.2, 1.2), 0.5).set_trans(Tween.TRANS_ELASTIC)

	# Show final score
	$UI/GameOver/FinalScore.text = "Final Score: " + str(score)
	var score_tween = create_tween()
	score_tween.tween_property($UI/GameOver/FinalScore, "modulate:a", 1.0, 1.0).from(0.0).set_delay(0.5)

	# Animate play again button
	$UI/GameOver/PlayAgainButton.modulate.a = 0.0
	var btn_tween = create_tween()
	btn_tween.tween_property($UI/GameOver/PlayAgainButton, "modulate:a", 1.0, 0.5).set_delay(1.0)

func start_game():
	game_started = true
	game_over = false
	score = 0
	enemy_spawn_timer = 0.0
	super_missile_timer = 0.0
	selected_launcher = null

	# Reset screen shake
	shake_amount = 0.0
	if has_node("Camera2D"):
		$Camera2D.offset = Vector2.ZERO

	# Hide screens
	$UI/StartScreen.visible = false
	$UI/GameOver.visible = false

	# Spawn terrain
	var terrain = terrain_scene.instantiate()
	terrain.position = Vector2(0, 1240)
	add_child(terrain)

	# Spawn launchers
	spawn_random_launchers()
	update_score_display()
	$UI/Info.text = "Click to fire from selected launcher"

func clear_game():
	# Remove all game objects
	for node in get_tree().get_nodes_in_group("enemy_missiles"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("launchers"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("terrain"):
		node.queue_free()
	# Remove missiles, explosions, craters
	for child in get_children():
		if child is Area2D or child.name.begins_with("Explosion") or child.name.begins_with("MegaExplosion") or child.name.begins_with("Crater"):
			child.queue_free()

func _on_play_pressed():
	if play_button_tween:
		play_button_tween.kill()
		play_button_tween = null
	# Clean up bg missiles
	for child in $UI/StartScreen/Overlay.get_children():
		if child is Label:
			child.queue_free()
	start_game()

func _on_play_again_pressed():
	Input.set_custom_mouse_cursor(null)
	clear_game()
	start_game()
