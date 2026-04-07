extends Node2D

var missile_scene = preload("res://missile.tscn")
var heat_seeking_missile_scene = preload("res://heat_seeking_missile.tscn")
var sam_launcher_scene = preload("res://sam_launcher.tscn")
var truck_launcher_scene = preload("res://truck_launcher.tscn")
var heat_seeking_launcher_scene = preload("res://heat_seeking_launcher.tscn")
var enemy_missile_scene = preload("res://enemy_missile.tscn")
var super_missile_scene = preload("res://super_missile.tscn")
var vulkan_cannon_scene = preload("res://vulkan_cannon.tscn")
var drone_scene = preload("res://drone.tscn")
var suicide_drone_scene = preload("res://suicide_drone.tscn")
var terrain_scene = preload("res://terrain.tscn")

var selected_launcher = null
var enemy_spawn_timer = 0.0
var enemy_spawn_interval = 3.0  # spawn every 3 seconds
var super_missile_timer = 0.0
var super_missile_interval = 12.0  # spawn super missile every 12 seconds
var drone_timer = 0.0
var drone_interval = 20.0  # spawn drone every 20 seconds
var suicide_drone_timer = 0.0
var suicide_drone_interval = 35.0  # spawn suicide drone every 35 seconds
var score = 0
var crosshair_radius = 50.0  # Detection radius for heat-seeking lock
var game_over = false
var game_started = false
var crosshair_default_cursor = null
var crosshair_cursor = null
var crosshair_locked_cursor = null
var shake_amount = 0.0
var shake_decay = 5.0  # How fast shake fades
var play_button_tween: Tween = null

func _ready():
	# Load cover image at runtime (bypasses import system)
	var img = Image.load_from_file("res://coverfinal.png")
	if img:
		$UI/StartScreen/CoverImage.texture = ImageTexture.create_from_image(img)

	# Create crosshair cursors from code
	crosshair_default_cursor = create_crosshair_texture("default")
	crosshair_cursor = create_crosshair_texture("heat")
	crosshair_locked_cursor = create_crosshair_texture("locked")

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

	if game_over or not game_started:
		return

	# Check if selected launcher was destroyed
	if selected_launcher and not is_instance_valid(selected_launcher):
		selected_launcher = null
		$UI/Info.text = "Launcher destroyed! Select another launcher"
		update_launcher_hud()

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

	# Spawn drones periodically
	drone_timer += delta
	if drone_timer >= drone_interval:
		drone_timer = 0.0
		spawn_drone()

	# Spawn suicide drones periodically
	suicide_drone_timer += delta
	if suicide_drone_timer >= suicide_drone_interval:
		suicide_drone_timer = 0.0
		spawn_suicide_drone()

	# Handle vulkan continuous fire
	if selected_launcher and is_instance_valid(selected_launcher) and selected_launcher.name.begins_with("VulkanCannon"):
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			selected_launcher.start_firing()
		else:
			selected_launcher.stop_firing()
		# Update heat bar
		update_heat_bar()

	# Always update cursor during gameplay
	if selected_launcher and is_instance_valid(selected_launcher) and selected_launcher.name.begins_with("HeatSeekingLauncher"):
		var enemy_near = find_enemy_near_cursor(get_global_mouse_position())
		if enemy_near:
			Input.set_custom_mouse_cursor(crosshair_locked_cursor, Input.CURSOR_ARROW, Vector2(24, 24))
		else:
			Input.set_custom_mouse_cursor(crosshair_cursor, Input.CURSOR_ARROW, Vector2(24, 24))
	else:
		Input.set_custom_mouse_cursor(crosshair_default_cursor, Input.CURSOR_ARROW, Vector2(24, 24))
	queue_redraw()

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

func create_crosshair_texture(mode: String = "default") -> ImageTexture:
	var size = 48
	var center = size / 2
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var main_color: Color
	var shadow_color: Color
	var thickness: int
	var gap: int
	var bracket_len: int

	match mode:
		"default":
			main_color = Color(0.88, 0.88, 0.88, 0.55)
			shadow_color = Color(0.1, 0.1, 0.1, 0.3)
			thickness = 1
			gap = 5
			bracket_len = 5
		"heat":
			main_color = Color(0.9, 0.15, 0.1, 0.9)
			shadow_color = Color(0.3, 0.05, 0.02, 0.6)
			thickness = 2
			gap = 5
			bracket_len = 6
		"locked":
			main_color = Color(1, 0.2, 0.1, 1)
			shadow_color = Color(1, 1, 0, 0.9)
			thickness = 2
			gap = 5
			bracket_len = 7

	# Crosshair lines
	for x in range(4, size - 4):
		if abs(x - center) > gap:
			for t in range(thickness):
				img.set_pixel(x, center + t, main_color)
				img.set_pixel(x, center - 1 - t, shadow_color)
	for y in range(4, size - 4):
		if abs(y - center) > gap:
			for t in range(thickness):
				img.set_pixel(center + t, y, main_color)
				img.set_pixel(center - 1 - t, y, shadow_color)

	# Center dot
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var px = center + dx
			var py = center + dy
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, main_color)

	# Corner brackets
	for i in range(bracket_len):
		for t in range(thickness):
			img.set_pixel(3 + i, 3 + t, main_color)
			img.set_pixel(3 + t, 3 + i, main_color)
			img.set_pixel(size - 4 - i, 3 + t, main_color)
			img.set_pixel(size - 4 - t, 3 + i, main_color)
			img.set_pixel(3 + i, size - 4 - t, main_color)
			img.set_pixel(3 + t, size - 4 - i, main_color)
			img.set_pixel(size - 4 - i, size - 4 - t, main_color)
			img.set_pixel(size - 4 - t, size - 4 - i, main_color)

	return ImageTexture.create_from_image(img)

func animate_start_screen():
	var play_btn = $UI/StartScreen/PlayButton

	play_btn.modulate.a = 0.0
	play_btn.scale = Vector2(0.5, 0.5)
	play_btn.pivot_offset = play_btn.size / 2

	# Play button: scale up + fade in with bounce
	var btn_tween = create_tween().set_parallel(true)
	btn_tween.tween_property(play_btn, "modulate:a", 1.0, 0.5).set_delay(0.3).set_ease(Tween.EASE_OUT)
	btn_tween.tween_property(play_btn, "scale", Vector2(1.0, 1.0), 0.6).set_delay(0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(1.2).timeout
	if $UI/StartScreen.visible:
		start_play_button_pulse()

func start_play_button_pulse():
	var play_btn = $UI/StartScreen/PlayButton
	if play_button_tween:
		play_button_tween.kill()
	play_button_tween = create_tween().set_loops()
	play_button_tween.tween_property(play_btn, "scale", Vector2(1.08, 1.08), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	play_button_tween.tween_property(play_btn, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

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
			# Vulkan cannon handles its own firing
			if selected_launcher.name.begins_with("VulkanCannon"):
				return
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

	# Spawn vulkan cannon
	var vulkan = vulkan_cannon_scene.instantiate()
	vulkan.position = Vector2(1900, 1220)
	add_child(vulkan)
	vulkan.launcher_clicked.connect(_on_launcher_selected)

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

func spawn_drone():
	var drone = drone_scene.instantiate()
	add_child(drone)
	var from_left = randi() % 2 == 0
	var y_pos = randf_range(450.0, 750.0)
	drone.init(from_left, y_pos)

func spawn_suicide_drone():
	var drone = suicide_drone_scene.instantiate()
	add_child(drone)
	var side = randi() % 3
	var spawn_pos: Vector2
	if side == 0:  # Top
		spawn_pos = Vector2(randf_range(300.0, 2260.0), -60.0)
	elif side == 1:  # Left
		spawn_pos = Vector2(-80.0, randf_range(150.0, 650.0))
	else:  # Right
		spawn_pos = Vector2(2640.0, randf_range(150.0, 650.0))
	drone.init(spawn_pos)

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
	update_launcher_hud()

	if launcher.name.begins_with("HeatSeekingLauncher"):
		$UI/Info.text = "Heat-Seeking Launcher - aim at enemy missiles"
	elif launcher.name.begins_with("VulkanCannon"):
		$UI/Info.text = "VULKAN CANNON - Hold to fire! Watch the heat!"
	else:
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

func build_launcher_hud():
	# Clear old HUD items
	for child in $UI/LauncherHUD.get_children():
		child.queue_free()
	
	var launchers = get_tree().get_nodes_in_group("launchers")
	for i in range(launchers.size()):
		var launcher = launchers[i]
		var panel = PanelContainer.new()
		panel.name = "LP_" + str(i)
		
		# Style the panel
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
		style.border_color = Color(0.3, 0.3, 0.4, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(6)
		panel.add_theme_stylebox_override("panel", style)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		panel.add_child(hbox)
		
		# Launcher icon (colored square)
		var icon = ColorRect.new()
		icon.custom_minimum_size = Vector2(12, 12)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		# Color by type
		var launcher_name = launcher.name
		if launcher_name.begins_with("SAM"):
			icon.color = Color(0.2, 0.4, 0.8, 1)  # Blue
		elif launcher_name.begins_with("Truck"):
			icon.color = Color(0.3, 0.5, 0.3, 1)  # Green
		elif launcher_name.begins_with("HeatSeeking"):
			icon.color = Color(0.8, 0.5, 0.1, 1)  # Orange
		elif launcher_name.begins_with("Vulkan"):
			icon.color = Color(0.8, 0.2, 0.2, 1)  # Red
		hbox.add_child(icon)
		
		# Label with type + key hint
		var label = Label.new()
		var type_text = ""
		if launcher_name.begins_with("SAM"):
			type_text = "SAM"
		elif launcher_name.begins_with("Truck"):
			type_text = "TRUCK"
		elif launcher_name.begins_with("HeatSeeking"):
			type_text = "SEEKER"
		elif launcher_name.begins_with("Vulkan"):
			type_text = "VULKAN"
		label.text = str(i + 1) + " " + type_text
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		hbox.add_child(label)
		
		# Store ref
		panel.set_meta("launcher_ref", launcher)
		panel.set_meta("label_ref", label)
		panel.set_meta("style_ref", style)
		
		$UI/LauncherHUD.add_child(panel)
	
	update_launcher_hud()

func update_launcher_hud():
	if not has_node("UI/LauncherHUD"):
		return
	for panel in $UI/LauncherHUD.get_children():
		if not panel.has_meta("launcher_ref"):
			continue
		var launcher = panel.get_meta("launcher_ref")
		var style: StyleBoxFlat = panel.get_meta("style_ref")
		var label: Label = panel.get_meta("label_ref")
		
		if not is_instance_valid(launcher):
			# Destroyed - dim it
			style.bg_color = Color(0.3, 0.05, 0.05, 0.6)
			style.border_color = Color(0.5, 0.1, 0.1, 0.4)
			label.add_theme_color_override("font_color", Color(0.5, 0.2, 0.2, 0.6))
			label.text = label.text.split(" ")[0] + " " + label.text.split(" ")[1] if label.text.split(" ").size() > 1 else label.text
			if not label.text.ends_with(" ✕"):
				label.text += " ✕"
		elif launcher == selected_launcher:
			# Selected - bright highlight
			style.bg_color = Color(0.1, 0.25, 0.5, 0.9)
			style.border_color = Color(0.3, 0.6, 1.0, 0.9)
			style.set_border_width_all(2)
			label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0, 1))
		else:
			# Not selected - dim
			style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
			style.border_color = Color(0.3, 0.3, 0.4, 0.6)
			style.set_border_width_all(1)
			label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))

func update_heat_bar():
	# Show/update heat bar for vulkan cannon
	if not has_node("UI/HeatBar"):
		_create_heat_bar()
	
	var heat_bar = $UI/HeatBar
	if selected_launcher and is_instance_valid(selected_launcher) and selected_launcher.name.begins_with("VulkanCannon"):
		heat_bar.visible = true
		var h = selected_launcher.heat
		var fill = $UI/HeatBar/Fill
		var glow = $UI/HeatBar/BarGlow
		fill.size.x = h * 250.0
		
		# Color transitions: blue → green → yellow → orange → red
		if selected_launcher.overheated:
			# Pulsing red when overheated
			var pulse = 0.7 + sin(Time.get_ticks_msec() * 0.012) * 0.3
			fill.color = Color(1, 0.08, 0.02, pulse)
			glow.color = Color(1, 0.1, 0.0, 0.25 + sin(Time.get_ticks_msec() * 0.015) * 0.15)
			glow.visible = true
			$UI/HeatBar/OverheatLabel.visible = true
			$UI/HeatBar/HeatLabel.add_theme_color_override("font_color", Color(1, 0.3, 0.1, 1))
		elif h > 0.7:
			fill.color = Color(1.0, 0.25, 0.05, 0.95)
			glow.color = Color(1, 0.2, 0.0, h * 0.15)
			glow.visible = true
			$UI/HeatBar/OverheatLabel.visible = false
			$UI/HeatBar/HeatLabel.add_theme_color_override("font_color", Color(1, 0.5, 0.3, 1))
		elif h > 0.4:
			fill.color = Color(1.0, 0.65, 0.1, 0.9)
			glow.visible = false
			$UI/HeatBar/OverheatLabel.visible = false
			$UI/HeatBar/HeatLabel.add_theme_color_override("font_color", Color(1, 0.8, 0.4, 0.9))
		else:
			fill.color = Color(0.2, 0.85, 0.4, 0.85)
			glow.visible = false
			$UI/HeatBar/OverheatLabel.visible = false
			$UI/HeatBar/HeatLabel.add_theme_color_override("font_color", Color(0.6, 0.8, 0.7, 0.9))
		
		# Update segment markers opacity based on heat
		for i in range(10):
			var seg_name = "Seg" + str(i)
			if $UI/HeatBar.has_node(seg_name):
				var seg = $UI/HeatBar.get_node(seg_name)
				var seg_threshold = (i + 1) * 0.1
				if h >= seg_threshold:
					seg.color.a = 0.6
				else:
					seg.color.a = 0.15
	else:
		heat_bar.visible = false

func _create_heat_bar():
	var container = Control.new()
	container.name = "HeatBar"
	container.visible = false
	
	var bar_x = 10.0
	var bar_y = 120.0
	var bar_w = 254.0
	var bar_h = 22.0
	
	# Outer frame (dark border)
	var frame = ColorRect.new()
	frame.name = "Frame"
	frame.position = Vector2(bar_x - 2, bar_y - 2)
	frame.size = Vector2(bar_w + 4, bar_h + 4)
	frame.color = Color(0.5, 0.5, 0.55, 0.7)
	container.add_child(frame)
	
	# Background
	var bg = ColorRect.new()
	bg.name = "BG"
	bg.position = Vector2(bar_x, bar_y)
	bg.size = Vector2(bar_w, bar_h)
	bg.color = Color(0.06, 0.06, 0.08, 0.9)
	container.add_child(bg)
	
	# Fill bar
	var fill = ColorRect.new()
	fill.name = "Fill"
	fill.position = Vector2(bar_x + 2, bar_y + 2)
	fill.size = Vector2(0, bar_h - 4)
	fill.color = Color(0.2, 0.85, 0.4, 0.85)
	container.add_child(fill)
	
	# Segment markers (10 divisions)
	for i in range(10):
		var seg = ColorRect.new()
		seg.name = "Seg" + str(i)
		seg.position = Vector2(bar_x + (i + 1) * 25.0, bar_y)
		seg.size = Vector2(2, bar_h)
		seg.color = Color(1, 1, 1, 0.15)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(seg)
	
	# Glow effect behind bar (visible at high heat)
	var glow = ColorRect.new()
	glow.name = "BarGlow"
	glow.position = Vector2(bar_x - 6, bar_y - 6)
	glow.size = Vector2(bar_w + 12, bar_h + 12)
	glow.color = Color(1, 0.2, 0.0, 0)
	glow.z_index = -1
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false
	container.add_child(glow)
	
	# "HEAT" label
	var label = Label.new()
	label.name = "HeatLabel"
	label.position = Vector2(bar_x + bar_w + 8, bar_y - 1)
	label.text = "🔥 HEAT"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.7, 0.9))
	container.add_child(label)
	
	# Overheat warning — centered flashing text
	var overheat = Label.new()
	overheat.name = "OverheatLabel"
	overheat.position = Vector2(bar_x, bar_y + bar_h + 4)
	overheat.text = "⚠ OVERHEATED — COOLING DOWN ⚠"
	overheat.add_theme_font_size_override("font_size", 16)
	overheat.add_theme_color_override("font_color", Color(1, 0.3, 0.1, 1))
	overheat.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	overheat.add_theme_constant_override("outline_size", 3)
	overheat.visible = false
	container.add_child(overheat)
	
	$UI.add_child(container)

func trigger_game_over():
	game_over = true
	$UI/GameOver.visible = true
	Input.set_custom_mouse_cursor(null)

	# Stop vulkan cannon if active
	if selected_launcher and is_instance_valid(selected_launcher) and selected_launcher.has_method("stop_firing"):
		selected_launcher.stop_firing()
	if has_node("UI/HeatBar"):
		$UI/HeatBar.visible = false

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
	drone_timer = 0.0
	suicide_drone_timer = 0.0
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
	build_launcher_hud()
	$UI/Info.text = "Click to fire from selected launcher"
	Input.set_custom_mouse_cursor(crosshair_default_cursor, Input.CURSOR_ARROW, Vector2(24, 24))

func clear_game():
	# Clear launcher HUD
	if has_node("UI/LauncherHUD"):
		for child in $UI/LauncherHUD.get_children():
			child.queue_free()
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
	start_game()

func _on_play_again_pressed():
	Input.set_custom_mouse_cursor(null)
	clear_game()
	start_game()
