## Suit collision feedback from actual contact impulses, with a brief helmet HUD flash.
class_name SuitImpacts
extends Node

const MIN_IMPULSE_NS: float = 5.0
const FULL_IMPULSE_NS: float = 100.0
const FLASH_SECONDS: float = 0.6
const RETRIGGER_SECONDS: float = 0.12

var player: Player
var _previous_impulses: Dictionary[int, float] = {}
var _remaining_seconds: float = 0.0
var _peak_strength: float = 0.0
var _retrigger_seconds: float = 0.0
var _label: Label


## Observe the suit without changing forces, collision masks, or damage rules.
func configure(owner_player: Player) -> void:
	player = owner_player
	player.max_contacts_reported = maxi(player.max_contacts_reported, 16)
	process_physics_priority = 10


## Current fading impact strength in [0, 1]; zero means there is no recent bump.
func flash_strength() -> float:
	return _peak_strength * clampf(_remaining_seconds / FLASH_SECONDS, 0.0, 1.0)


func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "ImpactHUD"
	add_child(layer)
	_label = Label.new()
	_label.name = "Bump"
	_label.text = "BUMP"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.035, 0.02, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.offset_left = -55.0
	_label.offset_right = 55.0
	_label.offset_top = 34.0
	_label.offset_bottom = 60.0
	_label.visible = false


func _process(_delta: float) -> void:
	var strength: float = flash_strength()
	_label.visible = strength > 0.0
	_label.modulate.a = strength


func _physics_process(delta: float) -> void:
	_remaining_seconds = maxf(0.0, _remaining_seconds - delta)
	_retrigger_seconds = maxf(0.0, _retrigger_seconds - delta)
	if not is_instance_valid(player) or player.freeze:
		_previous_impulses.clear()
		return
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(player.get_rid())
	if state == null:
		return
	var impulses: Dictionary[int, float] = {}
	for index: int in state.get_contact_count():
		var impulse: Vector3 = state.get_contact_impulse(index)
		if not impulse.is_finite():
			continue
		var collider_id: int = state.get_contact_collider_id(index)
		impulses[collider_id] = float(impulses.get(collider_id, 0.0)) + impulse.length()
	var strongest_rise: float = 0.0
	for collider_id: int in impulses:
		strongest_rise = maxf(strongest_rise, impulses[collider_id] - float(_previous_impulses.get(collider_id, 0.0)))
	_previous_impulses = impulses
	if strongest_rise >= MIN_IMPULSE_NS and _retrigger_seconds <= 0.0:
		_peak_strength = maxf(flash_strength(), lerpf(0.6, 1.0, clampf(strongest_rise / FULL_IMPULSE_NS, 0.0, 1.0)))
		_remaining_seconds = FLASH_SECONDS
		_retrigger_seconds = RETRIGGER_SECONDS
