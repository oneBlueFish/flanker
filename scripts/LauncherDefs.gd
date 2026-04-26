## LauncherDefs.gd — Central registry for all launcher types.
## Adding a new launcher = add one entry to DEFS + a slot in SupporterHUD.
## All costs/timings/damage read from here; no stats hardcoded elsewhere.

class_name LauncherDefs

# ── Launcher type definitions ─────────────────────────────────────────────────
# Keys:
#   label          String   — display name in HUD
#   build_cost     int      — team points to place the launcher tower
#   fire_cost      int      — team points consumed each time the launcher fires
#   cooldown       float    — seconds before this launcher can fire again
#   health         int      — launcher tower hit points
#   blast_radius   float    — AoE sphere radius at impact
#   blast_damage   float    — damage to all targets inside blast radius
#   flight_time    float    — seconds for missile to reach target (controls arc height)
#   missile_scene  String   — PackedScene path for the projectile
#   icon           Texture2D or null (future use)

const DEFS: Dictionary = {
	"launcher_missile": {
		"label":         "Missile",
		"build_cost":    50,
		"fire_cost":     150,
		"cooldown":      90.0,
		"health":        600,
		"blast_radius":  12.0,
		"blast_damage":  950.0,
		"flight_time":   4.0,
		"missile_scene": "res://scenes/Missile.tscn",
		"icon":          null,
	},
	# ── Future launcher types ─────────────────────────────────────────────────
	# "launcher_cluster": {
	#     "label":         "Cluster",
	#     "build_cost":    80,
	#     "fire_cost":     200,
	#     "cooldown":      120.0,
	#     "health":        500,
	#     "blast_radius":  6.0,
	#     "blast_damage":  200.0,
	#     "flight_time":   3.0,
	#     "missile_scene": "res://scenes/ClusterMissile.tscn",
	#     "icon":          null,
	# },
}

# Returns a list of launcher type keys in insertion order.
static func get_all_types() -> Array:
	return DEFS.keys()

# Returns true if the given type key is a valid launcher type.
static func is_launcher_type(item_type: String) -> bool:
	return DEFS.has(item_type)

# Shorthand accessors — always fall back to safe defaults so callers
# never crash on a missing key.

static func get_build_cost(launcher_type: String) -> int:
	return int(DEFS.get(launcher_type, {}).get("build_cost", 50))

static func get_fire_cost(launcher_type: String) -> int:
	return int(DEFS.get(launcher_type, {}).get("fire_cost", 150))

static func get_cooldown(launcher_type: String) -> float:
	return float(DEFS.get(launcher_type, {}).get("cooldown", 90.0))

static func get_health(launcher_type: String) -> int:
	return int(DEFS.get(launcher_type, {}).get("health", 600))

static func get_blast_radius(launcher_type: String) -> float:
	return float(DEFS.get(launcher_type, {}).get("blast_radius", 12.0))

static func get_blast_damage(launcher_type: String) -> float:
	return float(DEFS.get(launcher_type, {}).get("blast_damage", 400.0))

static func get_flight_time(launcher_type: String) -> float:
	return float(DEFS.get(launcher_type, {}).get("flight_time", 4.0))

static func get_missile_scene(launcher_type: String) -> String:
	return str(DEFS.get(launcher_type, {}).get("missile_scene", "res://scenes/Missile.tscn"))

static func get_label(launcher_type: String) -> String:
	return str(DEFS.get(launcher_type, {}).get("label", launcher_type.capitalize()))
