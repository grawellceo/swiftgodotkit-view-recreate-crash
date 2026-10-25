extends Node2D

func _process(delta: float) -> void:
	$Square.rotation += delta * 2.0
	$Label.text = "frame %d" % Engine.get_frames_drawn()
