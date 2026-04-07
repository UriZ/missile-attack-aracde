extends Area2D

var speed = 130.0
var direction = 1  # 1 = right, -1 = left
var bomb_cooldown = 0.0
var enemy_missile_scene = preload("res://enemy_missile.tscn")

func _ready():
	add_to_group("enemy_missiles")

func init(from_left: bool, y_pos: float):
	if from_left:
		direction = 1
		position = Vector2(-80.0, y_pos)
	else:
		direction = -1
		position = Vector2(2640.0, y_pos)
	$Visual.scale.x = float(direction)
	bomb_cooldown = randf_range(1.5, 3.0)

func _process(delta):
	position.x += speed * direction * delta

	bomb_cooldown -= delta
	if bomb_cooldown <= 0.0:
		_try_drop_bomb()

	# Animate engine glow
	$Visual/EngineGlow.modulate.a = 0.55 + sin(Time.get_ticks_msec() * 0.01) * 0.4

	# Off-screen cleanup
	if position.x < -200.0 or position.x > 2760.0:
		queue_free()

func _try_drop_bomb():
	var launchers = get_tree().get_nodes_in_group("launchers")
	for launcher in launchers:
		if is_instance_valid(launcher) and abs(launcher.global_position.x - global_position.x) < 180.0:
			_drop_bomb()
			bomb_cooldown = randf_range(3.5, 5.5)
			return
	# No launcher below — check again soon
	bomb_cooldown = randf_range(0.4, 1.0)

func _drop_bomb():
	var bomb = enemy_missile_scene.instantiate()
	bomb.position = global_position
	get_parent().add_child(bomb)
	var target_x = global_position.x + randf_range(-20.0, 20.0)
	bomb.launch_to(Vector2(target_x, 1240.0), 1.8)
