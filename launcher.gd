extends Area2D

signal launcher_clicked(launcher)

var is_selected = false
var glow_tween: Tween = null

func _ready():
	add_to_group("launchers")
	input_event.connect(_on_input_event)

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Launcher clicked!")
		launcher_clicked.emit(self)
		get_viewport().set_input_as_handled()

func _process(delta):
	if not has_node("Turret"):
		return

	var mouse_pos = get_global_mouse_position()
	var direction = mouse_pos - global_position

	# Calculate target angle (0 = straight up)
	var target_angle = direction.angle() + PI / 2

	# Clamp rotation to ±80 degrees from vertical
	target_angle = clamp(target_angle, deg_to_rad(-80), deg_to_rad(80))

	# Smooth rotation
	$Turret.rotation = lerp_angle($Turret.rotation, target_angle, 10.0 * delta)

	# Spin radar dish independently if present
	if has_node("Turret/RadarMast"):
		$Turret/RadarMast.rotation += 1.8 * delta

func set_selected(selected: bool):
	is_selected = selected
	# Show/hide glow
	if has_node("SelectionGlow"):
		$SelectionGlow.visible = selected
	if has_node("SelectionGlow2"):
		$SelectionGlow2.visible = selected
	
	# Pulse animation
	if glow_tween:
		glow_tween.kill()
		glow_tween = null
	if selected and has_node("SelectionGlow"):
		glow_tween = create_tween().set_loops()
		glow_tween.tween_property($SelectionGlow, "color:a", 0.5, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		glow_tween.tween_property($SelectionGlow, "color:a", 0.25, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Notify main to update HUD
	if get_tree().current_scene.has_method("update_launcher_hud"):
		get_tree().current_scene.update_launcher_hud()

func get_launch_position() -> Vector2:
	if has_node("Turret"):
		var tip_offset = Vector2(0, -62).rotated($Turret.rotation)
		return global_position + tip_offset
	return global_position
