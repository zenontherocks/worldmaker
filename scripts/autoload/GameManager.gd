extends Node
## Thin coordination point shared by systems that don't otherwise know about
## each other (BuildModeController, SaveLoadManager, UI). It intentionally
## holds almost no logic of its own -- it just tracks "where does placed
## geometry live" and hands out stable object ids for save files.

signal world_root_registered(root: Node3D)
signal world_cleared

var world_root: Node3D = null

var _next_id: int = 1


func register_world(root: Node3D) -> void:
	world_root = root
	world_root_registered.emit(root)


func get_next_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func reset_id_counter(start_at: int = 1) -> void:
	_next_id = start_at


func notify_world_cleared() -> void:
	world_cleared.emit()
