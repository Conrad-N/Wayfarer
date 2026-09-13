## Physical pilot restraints and freely drifting terminal/tablet input.
class_name ShipInteraction
extends Node

const STRAP_REACH_M: float = 2.0
const STRAP_MAX_SPEED_MPS: float = 1.0
const SEAT_READY_HINT: String = "F strap into pilot seat | Tab tablet"
const SEAT_APPROACH_HINT: String = "Move within 2 m of the pilot seat and slow below 1 m/s to strap in | Tab tablet"

var player: Player
var ship: PlayerShip
var tablet: WorldScreen
var active_screen: WorldScreen
var hint: String = "Tab tablet | F use terminal"
var _camera: Camera3D
var _standing_camera_position: Vector3
var _seat_restraint: PhysicalGrip
var _seat_pose_active: bool = false



## Connect the suit to its ship; the tablet uses the same ShipApi as both terminals.
func configure(suit_player: Player, owner_ship: PlayerShip) -> void:
	player = suit_player
	ship = owner_ship
	_camera = player.get_node("Camera3D") as Camera3D
	_seat_restraint = PhysicalGrip.new()
	_seat_restraint.name = "SeatRestraint"
	add_child(_seat_restraint)
	_seat_restraint.configure(player, _camera)
	_seat_restraint.max_reach_m = 2.5
	_seat_restraint.max_catch_speed_mps = STRAP_MAX_SPEED_MPS
	_seat_restraint.max_grip_force_n = 200000.0
	_seat_restraint.max_grip_torque_nm = 50000.0
	tablet = preload("res://ui/world_screen.tscn").instantiate() as WorldScreen
	tablet.name = "Tablet"
	tablet.render_on_top = true
	tablet.configure(ship.api, "SHIP", false)
	_camera.add_child(tablet)
	tablet.position = Vector3(0, -0.06, -1.0)
	tablet.scale = Vector3.ONE
	tablet.visible = false
	(tablet.get_node("InteractionArea") as Area3D).collision_layer = 0


## Return whether a panel owns the cursor and suit controls.
func is_open() -> bool:
	return is_instance_valid(active_screen)


## Open the handheld apps without stopping the suit's existing drift.
func open_tablet() -> void:
	if is_open():
		close_screen()
	_begin_input(tablet)
	tablet.visible = true


## Snap a nearby, slow pilot into the forward-facing seated pose and fasten the harness.
func strap_in() -> bool:
	if is_seated() or not is_instance_valid(ship):
		return false
	var seat_position: Vector3 = ship.to_global(PlayerShip.SEAT_POSITION)
	if not _seat_within_reach():
		hint = SEAT_APPROACH_HINT
		return false
	# The requested seating shortcut changes pose once; the live harness owns motion afterward.
	var approach_pose: Transform3D = player.global_transform
	player.global_transform = ship.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), PlayerShip.SEAT_POSITION)
	if not _seat_restraint.grab_body(ship, seat_position):
		player.global_transform = approach_pose
		return false
	_standing_camera_position = _camera.position
	_seat_pose_active = true
	_camera.position = Vector3(0, 0.35, 0)
	player.centre_head()
	for child_name: String in ["PhysicalGrip", "MagneticBoots"]:
		var attachment: Node = player.get_node_or_null(child_name)
		if attachment != null and attachment.has_method("release"):
			attachment.call("release")
	player.grapple.detach()
	player._release_mouse()
	player.set_meta("seated", true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true


## Whether the harness currently connects the suit to the pilot seat.
func is_seated() -> bool:
	return is_instance_valid(_seat_restraint) and _seat_restraint.is_attached()


## Unbuckle without changing the actual momentum solved by the seat constraint.
## A deliberate release also stands the pilot up beside the seat; a harness that
## simply broke (step_out false) leaves them wherever physics put them.
func unstrap(step_out: bool = true) -> void:
	var was_posed: bool = _seat_pose_active
	if _seat_pose_active:
		close_screen()
		_camera.position = _standing_camera_position
		player.centre_head()
		_seat_pose_active = false
	if is_instance_valid(_seat_restraint):
		_seat_restraint.release()
	if is_instance_valid(player):
		player.set_meta("seated", false)
		if step_out and was_posed and is_instance_valid(ship):
			_step_out_of_seat()


## Use a nearby terminal without providing an implicit physical restraint.
func open_terminal(screen: WorldScreen) -> bool:
	if not is_instance_valid(screen) or not screen.is_available() or is_open():
		return false
	if _camera.global_position.distance_to(screen.global_position) > 2.5:
		hint = "Approach within 2.5 m to use the terminal"
		return false
	_begin_input(screen)
	return true


## Release screen input; the suit's restraint and physical motion remain unchanged.
func close_screen() -> void:
	if not is_open():
		return
	active_screen.panel.cancel_input()
	tablet.visible = false
	active_screen = null
	player.input_enabled = true
	player._capture_click_held = true
	player._secondary_blocked = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _begin_input(screen: WorldScreen) -> void:
	player._release_mouse()
	player.input_enabled = false
	active_screen = screen


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if _seat_pose_active and not is_seated():
		unstrap(false)
	player.set_meta("seated", is_seated())
	if is_open():
		hint = "Esc / F close screen | Tab tablet" + (" | HARNESS SECURED | V unstrap" if is_seated() else " | UNRESTRAINED")
		if not active_screen.is_available():
			close_screen()
	elif is_seated():
		hint = "HARNESS SECURED | Mouse look | V unstrap | F use terminal | Tab tablet"
	else:
		var target: WorldScreen = _aimed_screen()
		if _aimed_seat():
			# Offer F only when strap_in() would actually accept it.
			hint = SEAT_READY_HINT if _seat_within_reach() else SEAT_APPROACH_HINT
		else:
			hint = ("F use %s terminal | Tab tablet" % target.panel.current_app) if target != null else "Tab tablet | F use terminal / pilot seat"


func _input(event: InputEvent) -> void:
	if not is_instance_valid(player):
		return
	if is_seated() and event.is_action("unstrap"):
		if event.is_pressed() and not event.is_echo():
			unstrap()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tablet") and not event.is_echo():
		if active_screen == tablet:
			close_screen()
		else:
			open_tablet()
		get_viewport().set_input_as_handled()
		return
	if is_open():
		if event.is_action_pressed("ui_cancel") or (event.is_action_pressed("interact") and not event.is_echo()):
			close_screen()
		elif event.is_action("wheel_dump"):
			# The terminal's own warp refusal asks the pilot to hold C, so the
			# key has to reach the suit while a screen owns the other input.
			player.set_wheel_dumping(event.is_pressed())
		elif event is InputEventMouse:
			var mouse: InputEventMouse = event as InputEventMouse
			var origin: Vector3 = _camera.project_ray_origin(mouse.position)
			var direction: Vector3 = _camera.project_ray_normal(mouse.position)
			var plane: Plane = Plane(active_screen.global_basis.z.normalized(), active_screen.global_position)
			var hit: Variant = plane.intersects_ray(origin, direction)
			if hit is Vector3:
				active_screen.forward_input(event, hit)
		elif not event.is_action_pressed("debug_screenshot"):
			active_screen.forward_input(event, active_screen.global_position)
		if not event.is_action_pressed("debug_screenshot"):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not event.is_echo():
		if is_seated():
			var screen: WorldScreen = _aimed_screen()
			if screen != null:
				open_terminal(screen)
			else:
				unstrap()
		elif _aimed_seat():
			strap_in()
		else:
			open_terminal(_aimed_screen())
		get_viewport().set_input_as_handled()


## Whether the pilot is close and slow enough for the harness to catch them.
func _seat_within_reach() -> bool:
	var seat_position: Vector3 = ship.to_global(PlayerShip.SEAT_POSITION)
	var carrier_velocity: Vector3 = ship.linear_velocity + ship.angular_velocity.cross(player.global_position - ship.to_global(ship.center_of_mass))
	return player.global_position.distance_to(seat_position) <= STRAP_REACH_M and (player.linear_velocity - carrier_velocity).length() <= STRAP_MAX_SPEED_MPS


## Stand the released pilot in the clear passage beside the seat instead of inside it.
func _step_out_of_seat() -> void:
	var exit_pose: Transform3D = Transform3D(player.global_basis, ship.to_global(PlayerShip.SEAT_EXIT_POSITION))
	if _pose_is_clear(exit_pose):
		player.global_transform = exit_pose


func _pose_is_clear(pose: Transform3D) -> bool:
	var collision: CollisionShape3D = player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		return true
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = pose * collision.transform
	query.exclude = [player.get_rid()]
	query.collision_mask = player.collision_mask
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _aimed_seat() -> bool:
	# Within the seat, the pilot can face NAV while reaching for the harness.
	if player.global_position.distance_to(ship.to_global(PlayerShip.SEAT_POSITION)) <= 0.65:
		return true
	var origin: Vector3 = _camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin - _camera.global_basis.z * 2.5, 5, [player.get_rid()])
	query.collide_with_areas = true
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	if (hit.collider as Node).get_meta("pilot_seat", false):
		return true
	if hit.collider == ship:
		var shape: Object = ship.shape_owner_get_owner(ship.shape_find_owner(int(hit.shape)))
		return shape != null and bool(shape.get_meta("pilot_seat", false))
	return false


func _aimed_screen() -> WorldScreen:
	var origin: Vector3 = _camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin - _camera.global_basis.z * 2.5, 5, [player.get_rid()])
	query.collide_with_areas = true
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Node = hit.collider as Node
	return collider.get_parent() as WorldScreen if collider is Area3D else null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_open():
		active_screen.panel.cancel_input()
		player.set_wheel_dumping(false)
