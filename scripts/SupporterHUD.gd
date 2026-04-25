extends CanvasLayer
## Supporter HUD — horizontal toolbar for selecting what to place.
## Hotkeys 1-8 or click to select. Slot 6 = weapon sub-row.

signal slot_changed(item_type: String, subtype: String)

const SLOT_DEFS := [
	{ "key": "1", "type": "cannon",      "subtype": "",       "label": "Cannon",    "cost_key": "cannon"      },
	{ "key": "2", "type": "mortar",      "subtype": "",       "label": "Mortar",    "cost_key": "mortar"      },
	{ "key": "3", "type": "slow",        "subtype": "",       "label": "Slow",      "cost_key": "slow"        },
	{ "key": "4", "type": "barrier",     "subtype": "",       "label": "Barrier",   "cost_key": "barrier"     },
	{ "key": "5", "type": "weapon",      "subtype": "rifle",  "label": "Weapon▾",  "cost_key": "weapon"      },
	{ "key": "6", "type": "healthpack",  "subtype": "",       "label": "HealthPack","cost_key": "healthpack"  },
	{ "key": "7", "type": "healstation", "subtype": "",       "label": "HealStation","cost_key": "healstation" },
]

const WEAPON_SUBTYPES := ["pistol", "rifle", "heavy"]
const WEAPON_COSTS    := { "pistol": 10, "rifle": 20, "heavy": 30 }
const PLACEABLE_COSTS := {
	"cannon": 25, "mortar": 35,
	"slow": 30, "barrier": 10, "healthpack": 15, "healstation": 25
}

var selected_type:    String = "cannon"
var selected_subtype: String = ""
var _player_team: int = 0
var _selected_slot:   int = 0

var _slot_buttons:  Array = []
var _cost_labels:   Array = []
var _weapon_subrow: Control = null
var _weapon_sub_btns: Array = []
var _selected_sub: int = 1  # default rifle

func _ready() -> void:
	# Built via code — no scene file needed beyond a single Panel root
	layer = 10
	_build_ui()

func setup(team: int) -> void:
	_player_team = team

func _build_ui() -> void:
	var root := PanelContainer.new()
	root.name = "ToolbarRoot"
	# Anchor to bottom-center
	root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root.anchor_top    = 1.0
	root.anchor_bottom = 1.0
	root.offset_top    = -120.0
	root.offset_bottom = 0.0

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(vbox)

	# Weapon sub-row (hidden until slot 6 selected)
	_weapon_subrow = HBoxContainer.new()
	_weapon_subrow.visible = false
	_weapon_subrow.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_weapon_subrow)

	for i in WEAPON_SUBTYPES.size():
		var sub := i
		var wtype: String = WEAPON_SUBTYPES[i]
		var wcost: int = WEAPON_COSTS[wtype]
		var btn := Button.new()
		btn.text = "%s\n¤%d" % [wtype.capitalize(), wcost]
		btn.custom_minimum_size = Vector2(90, 36)
		btn.pressed.connect(func(): _select_weapon_sub(sub))
		_weapon_subrow.add_child(btn)
		_weapon_sub_btns.append(btn)

	# Main toolbar row
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	for i in SLOT_DEFS.size():
		var def: Dictionary = SLOT_DEFS[i]
		var slot_idx: int = i

		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(90, 60)

		var inner := VBoxContainer.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_child(inner)

		var key_lbl := Label.new()
		key_lbl.text = "[%s]" % def["key"]
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.add_theme_font_size_override("font_size", 10)
		inner.add_child(key_lbl)

		var name_lbl := Label.new()
		name_lbl.text = def["label"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		inner.add_child(name_lbl)

		var cost_lbl := Label.new()
		var cost: int = _get_slot_cost(i)
		cost_lbl.text = "¤%d" % cost
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.add_theme_font_size_override("font_size", 11)
		inner.add_child(cost_lbl)
		_cost_labels.append(cost_lbl)

		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_child(btn)
		btn.pressed.connect(func(): _select_slot(slot_idx))

		hbox.add_child(panel)
		_slot_buttons.append(panel)

	add_child(root)
	_refresh_selection()

func _get_slot_cost(slot_idx: int) -> int:
	var def: Dictionary = SLOT_DEFS[slot_idx]
	if def["type"] == "weapon":
		return WEAPON_COSTS.get(WEAPON_SUBTYPES[_selected_sub], 20)
	return PLACEABLE_COSTS.get(def["cost_key"], 0)

func _select_slot(slot_idx: int) -> void:
	_selected_slot = slot_idx
	var def: Dictionary = SLOT_DEFS[slot_idx]
	selected_type    = def["type"]
	selected_subtype = def["subtype"]
	if selected_type == "weapon":
		selected_subtype = WEAPON_SUBTYPES[_selected_sub]
		_weapon_subrow.visible = true
	else:
		_weapon_subrow.visible = false
	_refresh_selection()
	slot_changed.emit(selected_type, selected_subtype)

func _select_weapon_sub(sub_idx: int) -> void:
	_selected_sub    = sub_idx
	selected_subtype = WEAPON_SUBTYPES[sub_idx]
	_refresh_weapon_sub()
	slot_changed.emit(selected_type, selected_subtype)

func _refresh_selection() -> void:
	for i in _slot_buttons.size():
		var panel: PanelContainer = _slot_buttons[i]
		var style := StyleBoxFlat.new()
		if i == _selected_slot:
			style.bg_color = Color(0.2, 0.7, 0.2, 0.85)
			style.border_width_left   = 2
			style.border_width_right  = 2
			style.border_width_top    = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.4, 1.0, 0.4)
		else:
			style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
		panel.add_theme_stylebox_override("panel", style)
	_refresh_weapon_sub()

func _refresh_weapon_sub() -> void:
	for i in _weapon_sub_btns.size():
		var btn: Button = _weapon_sub_btns[i]
		if i == _selected_sub:
			btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		else:
			btn.remove_theme_color_override("font_color")

func _process(_delta: float) -> void:
	_tick_hotkeys()
	_tick_cost_colors()

func _tick_hotkeys() -> void:
	for i in SLOT_DEFS.size():
		var action: String = "supporter_slot_%d" % (i + 1)
		if Input.is_action_just_pressed(action):
			_select_slot(i)

func _tick_cost_colors() -> void:
	var pts: int = TeamData.get_points(_player_team)
	for i in _cost_labels.size():
		var lbl: Label = _cost_labels[i]
		var cost: int = _get_slot_cost(i)
		if pts < cost:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			lbl.remove_theme_color_override("font_color")
