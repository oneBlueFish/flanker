extends Control

const COLOR_NORMAL := Color(0.12, 0.12, 0.12, 0.9)
const COLOR_HOVER := Color(0.3, 0.9, 0.3, 1.0)
const HOVER_DURATION := 0.1

func _ready() -> void:
	print("[PauseMenu] _ready called")
	visible = false
	$ResumeButton.mouse_entered.connect(_on_resume_hover)
	$ResumeButton.mouse_exited.connect(_on_resume_normal)
	$QuitButton.mouse_entered.connect(_on_quit_hover)
	$QuitButton.mouse_exited.connect(_on_quit_normal)

func _on_resume_hover() -> void:
	var tween := create_tween()
	tween.tween_property($ResumeButton, "modulate", COLOR_HOVER, HOVER_DURATION)

func _on_resume_normal() -> void:
	var tween := create_tween()
	tween.tween_property($ResumeButton, "modulate", COLOR_NORMAL, HOVER_DURATION)

func _on_quit_hover() -> void:
	var tween := create_tween()
	tween.tween_property($QuitButton, "modulate", COLOR_HOVER, HOVER_DURATION)

func _on_quit_normal() -> void:
	var tween := create_tween()
	tween.tween_property($QuitButton, "modulate", COLOR_NORMAL, HOVER_DURATION)

func _on_resume_pressed() -> void:
	var main: Node = get_tree().root.get_node("Main")
	if main:
		main.toggle_pause(false)

func _on_quit_pressed() -> void:
	get_tree().quit()