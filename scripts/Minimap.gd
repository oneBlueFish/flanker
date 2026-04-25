extends Control

const MAP_RADIUS    := 100.0  # half of 200×200 world
const MINIMAP_SIZE  := 150.0  # pixels

# Colors
const COL_BG          := Color(0.0, 0.0, 0.0, 0.55)
const COL_BORDER      := Color(0.8, 0.8, 0.8, 0.6)
const COL_LANE        := Color(0.55, 0.45, 0.25, 0.7)
const COL_BLUE_BASE   := Color(0.2, 0.4, 1.0, 0.9)
const COL_RED_BASE    := Color(1.0, 0.2, 0.2, 0.9)
const COL_BLUE_MINION := Color(0.3, 0.55, 1.0, 1.0)
const COL_RED_MINION  := Color(1.0, 0.35, 0.35, 1.0)
const COL_PLAYER      := Color(1.0, 1.0, 1.0, 1.0)

# Pre-baked lane pixel arrays — computed once in _ready()
var _lane_pixels: Array = []

# Base pixel positions
var _blue_base_px: Vector2
var _red_base_px: Vector2

@onready var _fps_player: CharacterBody3D = get_node("/root/Main/FPSPlayer")

const COL_BLUE_TOWER := Color(0.1, 0.6, 1.0, 1.0)
const COL_RED_TOWER  := Color(1.0, 0.4, 0.1, 1.0)

const REDRAW_INTERVAL := 0.05  # 20 fps is fine for minimap

var _redraw_timer: float = 0.0
var _rts_cam: Camera3D = null
var _main: Node = null


func _ready() -> void:
	custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	mouse_filter = MOUSE_FILTER_IGNORE
	
	var main_root = get_tree().root.get_node("Main")
	if main_root:
		var players = main_root.get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_fps_player = players[0]

	# Pre-bake lane polylines
	for i in range(3):
		var pts: Array = LaneData.get_lane_points(i)
		var px_arr: Array[Vector2] = []
		for p in pts:
			px_arr.append(_world_to_map(Vector2(p.x, p.y)))
		_lane_pixels.append(px_arr)

	# Base positions: blue z=+84, red z=-84 (both x=0)
	_blue_base_px = _world_to_map(Vector2(0.0, 84.0))
	_red_base_px  = _world_to_map(Vector2(0.0, -84.0))

	_rts_cam = get_node_or_null("/root/Main/RTSCamera")
	_main    = get_node_or_null("/root/Main")


func _process(delta: float) -> void:
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		queue_redraw()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE))

	# Background
	draw_rect(r, COL_BG)

	# Lane lines
	for lane_px in _lane_pixels:
		if lane_px.size() >= 2:
			draw_polyline(lane_px, COL_LANE, 1.5)

	# Base markers (5×5 squares, centered)
	var base_half := Vector2(5.0, 5.0)
	draw_rect(Rect2(_blue_base_px - base_half, base_half * 2.0), COL_BLUE_BASE)
	draw_rect(Rect2(_red_base_px  - base_half, base_half * 2.0), COL_RED_BASE)

	# Minion dots
	for minion in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(minion):
			continue
		var gp: Vector3 = minion.global_position
		var team: int = minion.get("team") if minion.get("team") != null else 0
		if _is_fogged(gp, team):
			continue
		var px: Vector2 = _world_to_map(Vector2(gp.x, gp.z))
		if _in_bounds(px):
			var col: Color = COL_BLUE_MINION if team == 0 else COL_RED_MINION
			draw_circle(px, 2.5, col)

	# Player dot
	if is_instance_valid(_fps_player):
		var pp: Vector3 = _fps_player.global_position
		var px: Vector2 = _world_to_map(Vector2(pp.x, pp.z))
		if _in_bounds(px):
			draw_circle(px, 4.0, COL_PLAYER)

# Tower dots
	for tower in get_tree().get_nodes_in_group("towers"):
		if not is_instance_valid(tower):
			continue
		var tower_team: int = tower.get("team") if tower.get("team") != null else 0
		var tp: Vector3 = (tower as Node3D).global_position
		if _is_fogged(tp, tower_team):
			continue
		var px: Vector2 = _world_to_map(Vector2(tp.x, tp.z))
		if _in_bounds(px):
			var tower_col: Color = COL_BLUE_TOWER if tower_team == 0 else COL_RED_TOWER
			draw_circle(px, 2.5, tower_col)

	# Border
	draw_rect(r, COL_BORDER, false, 1.5)


# Convert world XZ (as Vector2(x, z)) to minimap pixel coords.
# World: x right, z+ = blue side (bottom of minimap).
func _world_to_map(xz: Vector2) -> Vector2:
	var nx: float = (xz.x / MAP_RADIUS) * 0.5 + 0.5    # 0..1, left→right
	var nz: float = (xz.y / MAP_RADIUS) * 0.5 + 0.5    # 0..1, top=red(z-), bottom=blue(z+)
	return Vector2(nx * MINIMAP_SIZE, nz * MINIMAP_SIZE)


func _in_bounds(px: Vector2) -> bool:
	return px.x >= 0.0 and px.x <= MINIMAP_SIZE and px.y >= 0.0 and px.y <= MINIMAP_SIZE

# Returns true if the position should be hidden by fog (enemy + outside vision + RTS mode active).
func _is_fogged(world_pos: Vector3, node_team: int) -> bool:
	if _rts_cam == null or not _rts_cam.current:
		return false  # FPS mode — no fog
	if _main == null:
		return false
	var player_team: int = _main.get("player_start_team") if _main.get("player_start_team") != null else 0
	if node_team == player_team:
		return false  # friendly — always visible
	# Check player vision
	if _main.get("fps_player") != null and is_instance_valid(_main.fps_player):
		if world_pos.distance_squared_to(_main.fps_player.global_position) <= 35.0 * 35.0:
			return false
	# Check friendly minion vision
	for minion in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(minion):
			continue
		if minion.get("team") != player_team:
			continue
		if world_pos.distance_squared_to(minion.global_position) <= 25.0 * 25.0:
			return false
	return true
