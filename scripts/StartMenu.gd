extends Control

signal start_game
signal quit_game

const LobbyScene    := preload("res://scenes/Lobby.tscn")
const TerrainScript := preload("res://scripts/TerrainGenerator.gd")
const LaneVizScript := preload("res://scripts/LaneVisualizer.gd")
const TreeScript    := preload("res://scripts/TreePlacer.gd")

var _lobby: Node
var _player_name := ""
var _join_dialog: AcceptDialog
var _host_dialog: AcceptDialog

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_dialogs()
	_spawn_menu_world()

func _build_dialogs() -> void:
	# Build JoinDialog entirely in code
	_join_dialog = AcceptDialog.new()
	_join_dialog.title = "Join Game"
	_join_dialog.size = Vector2i(400, 220)
	_join_dialog.unresizable = true
	_join_dialog.ok_button_text = "Join"
	_join_dialog.dialog_hide_on_ok = true
	_join_dialog.confirmed.connect(_on_join_confirmed)
	add_child(_join_dialog)
	var join_vbox := VBoxContainer.new()
	_join_dialog.add_child(join_vbox)
	var addr_lbl := Label.new(); addr_lbl.text = "Host IP Address:"; addr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; join_vbox.add_child(addr_lbl)
	var addr_edit := LineEdit.new(); addr_edit.name = "AddressEdit"; addr_edit.placeholder_text = "192.168.1.100"; join_vbox.add_child(addr_edit)
	var jport_lbl := Label.new(); jport_lbl.text = "Port:"; jport_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; join_vbox.add_child(jport_lbl)
	var jport_edit := LineEdit.new(); jport_edit.name = "PortEdit"; jport_edit.text = "8910"; join_vbox.add_child(jport_edit)
	var jname_lbl := Label.new(); jname_lbl.text = "Your Name:"; jname_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; join_vbox.add_child(jname_lbl)
	var jname_edit := LineEdit.new(); jname_edit.name = "NameEdit"; jname_edit.placeholder_text = "Player"; join_vbox.add_child(jname_edit)

	# Build HostDialog entirely in code
	_host_dialog = AcceptDialog.new()
	_host_dialog.title = "Host Game"
	_host_dialog.size = Vector2i(400, 180)
	_host_dialog.unresizable = true
	_host_dialog.ok_button_text = "Host"
	_host_dialog.dialog_hide_on_ok = true
	_host_dialog.confirmed.connect(_on_host_confirmed)
	add_child(_host_dialog)
	var host_vbox := VBoxContainer.new()
	_host_dialog.add_child(host_vbox)
	var hport_lbl := Label.new(); hport_lbl.text = "Port:"; hport_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; host_vbox.add_child(hport_lbl)
	var hport_edit := LineEdit.new(); hport_edit.name = "PortEdit"; hport_edit.text = "8910"; host_vbox.add_child(hport_edit)
	var hname_lbl := Label.new(); hname_lbl.text = "Your Name:"; hname_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; host_vbox.add_child(hname_lbl)
	var hname_edit := LineEdit.new(); hname_edit.name = "NameEdit"; hname_edit.placeholder_text = "Host"; host_vbox.add_child(hname_edit)

func _spawn_menu_world() -> void:
	# Random seed each launch — different view every time
	GameSync.game_seed = randi_range(1, 2147483647)

	var world: Node3D = $World3D

	# Terrain (StaticBody3D, builds HeightMapShape3D + mesh in _ready)
	var terrain := StaticBody3D.new()
	terrain.set_script(TerrainScript)
	terrain.name = "Terrain"
	world.add_child(terrain)

	# Lane ribbon visuals
	var lane_viz := Node3D.new()
	lane_viz.set_script(LaneVizScript)
	lane_viz.name = "LaneVisualizer"
	world.add_child(lane_viz)

	# Trees — low density for menu background performance
	var trees := Node3D.new()
	trees.set_script(TreeScript)
	trees.name = "TreePlacer"
	# Must set before add_child so _ready() sees the override
	trees.set("menu_density", 0.1)
	world.add_child(trees)

	# Reset seed to 0 so multiplayer seed guard works correctly if RPC is missed
	GameSync.game_seed = 0

func _on_host_pressed() -> void:
	_host_dialog.popup_centered()

func _on_join_pressed() -> void:
	_join_dialog.popup_centered()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_local_pressed() -> void:
	print("[StartMenu] Local Play - switching to Main...")
	LaneData.regenerate_for_new_game()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_host_confirmed() -> void:
	var port_edit: LineEdit = _find_child_by_name(_host_dialog, "PortEdit")
	var name_edit: LineEdit = _find_child_by_name(_host_dialog, "NameEdit")

	var port_text: String = port_edit.text.strip_edges()
	var name_text: String = name_edit.text.strip_edges()

	var port: int = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT
	_player_name = name_text if name_text.length() > 0 else "Host"

	var err: int = NetworkManager.start_host(port)
	if err != OK:
		_show_connection_status("Failed to host: port may be in use")
		return

	# Host registers itself directly — no RPC needed, peer id 1 is always the server
	LobbyManager.register_player_local(1, _player_name)
	_show_lobby()

func _on_join_confirmed() -> void:
	var address_edit: LineEdit = _find_child_by_name(_join_dialog, "AddressEdit")
	var port_edit: LineEdit = _find_child_by_name(_join_dialog, "PortEdit")
	var name_edit: LineEdit = _find_child_by_name(_join_dialog, "NameEdit")

	var address: String = address_edit.text.strip_edges()
	var port_text: String = port_edit.text.strip_edges()
	var name_text: String = name_edit.text.strip_edges()

	if address.is_empty():
		_show_connection_status("Enter host IP address")
		return

	var port: int = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT
	_player_name = name_text if name_text.length() > 0 else "Player"

	_show_connection_status("Connecting...")
	var err: int = NetworkManager.join_game(address, port)
	if err != OK:
		_show_connection_status("Failed to connect")
		return

	NetworkManager.connected_to_server.connect(_on_connected_to_lobby, CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)

func _on_connected_to_lobby() -> void:
	# Send our name to the server — server uses get_remote_sender_id() to know who we are
	LobbyManager.register_player.rpc_id(1, _player_name)
	_show_lobby()

func _on_connection_failed() -> void:
	_show_connection_status("Connection failed")

func _show_lobby() -> void:
	visible = false
	_lobby = LobbyScene.instantiate()
	get_tree().root.add_child(_lobby)

func _show_connection_status(msg: String) -> void:
	var status: Label = $ConnectionStatus
	status.text = msg
	status.visible = true
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(status, "visible", false, 0.0)

func _find_child_by_name(parent: Node, child_name: String) -> LineEdit:
	for child in parent.get_children():
		var found: Node = child.find_child(child_name, true, false)
		if found:
			return found as LineEdit
	return null
