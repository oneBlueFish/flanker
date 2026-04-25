extends Node

var _file: FileAccess = null
var _role: String = ""
var _frame: int = 0

func _ready() -> void:
	pass  # log opened lazily on first write — peer is not set yet at _ready() time

func _process(_delta: float) -> void:
	_frame += 1

func _open_log() -> void:
	if multiplayer.is_server():
		_role = "host"
	else:
		_role = "client"
	var path: String = "/tmp/flankers_%s.log" % _role
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("MinionDebug: cannot open %s (err=%d)" % [path, FileAccess.get_open_error()])
		return
	_w("=== MINION DEBUG LOG [%s] started ===" % _role.to_upper())
	_w("peer_id=%d  is_server=%s" % [multiplayer.get_unique_id(), str(multiplayer.is_server())])

func _w(msg: String) -> void:
	if _file == null:
		_open_log()
	if _file == null:
		return
	_file.store_line("[f%06d] %s" % [_frame, msg])
	_file.flush()

# ── Public API ────────────────────────────────────────────────────────────────

func log_spawn(minion_id: int, team: int, pos: Vector3, is_puppet: bool) -> void:
	_w("SPAWN  id=%-4d team=%d puppet=%-5s pos=%s" % [minion_id, team, str(is_puppet), _v(pos)])

func log_puppet_set(minion_id: int, pos: Vector3) -> void:
	_w("PUPPET_SET id=%-4d pos=%s" % [minion_id, _v(pos)])

func log_broadcast(count: int) -> void:
	_w("BROADCAST minions=%d" % count)

func log_state_recv(minion_id: int, pos: Vector3, hp: float, found: bool) -> void:
	_w("STATE_RECV id=%-4d hp=%-6.1f found=%-5s pos=%s" % [minion_id, hp, str(found), _v(pos)])

func log_puppet_move(minion_id: int, cur: Vector3, target: Vector3, dist: float) -> void:
	_w("PUPPET_MOVE id=%-4d dist=%-6.3f cur=%s tgt=%s" % [minion_id, dist, _v(cur), _v(target)])

func log_die(minion_id: int, is_puppet: bool, source: String) -> void:
	_w("DIE    id=%-4d puppet=%-5s source=%s" % [minion_id, str(is_puppet), source])

func log_take_damage(minion_id: int, amount: float, hp_after: float, blocked: bool) -> void:
	_w("DAMAGE id=%-4d amt=%-5.1f hp_after=%-6.1f blocked=%s" % [minion_id, amount, hp_after, str(blocked)])

func log_wave(wave_num: int, count: int) -> void:
	_w("WAVE   num=%d  minions_launched=%d" % [wave_num, count])

func log_rpc(name: String, detail: String) -> void:
	_w("RPC    %s  %s" % [name, detail])

func _v(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]
