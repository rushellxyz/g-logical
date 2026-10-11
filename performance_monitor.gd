extends Node

signal fps_changed(fps: int)

var fps := 0
var _elapsed := 0.0

func _ready() -> void:
	set_process(false)

func set_enabled(enabled: bool) -> void:
	set_process(enabled)
	_elapsed = 0.0
	if enabled:
		update_fps()

func update_fps() -> void:
	var current := int(Engine.get_frames_per_second())
	if fps != current:
		fps = current
		fps_changed.emit(fps)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		update_fps()
