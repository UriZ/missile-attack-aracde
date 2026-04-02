extends Area2D

signal launcher_clicked(launcher)

var is_selected = false

func _ready():
	add_to_group("launchers")
	input_event.connect(_on_input_event)

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Launcher clicked!")
		launcher_clicked.emit(self)
		get_viewport().set_input_as_handled()

func set_selected(selected: bool):
	is_selected = selected
	if has_node("SelectionRing"):
		$SelectionRing.visible = selected

func get_launch_position() -> Vector2:
	return global_position
