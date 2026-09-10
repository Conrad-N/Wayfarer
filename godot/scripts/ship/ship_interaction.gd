## Terminal docking and handheld input share the same physical screen apps.
class_name ShipInteraction
extends Node

var player: Player
var ship: PlayerShip
var tablet: WorldScreen
var active_screen: WorldScreen
var hint: String = "Tab tablet | F use terminal"
var _camera: Camera3D
var _docked: bool = false
var _dock_elapsed: float = 0.0
var _start_local: Transform3D
var _carrier_collision_exception_added: bool = false


## Connect the suit to its ship; the tablet uses the same ShipApi as both terminals.
func configure(suit_player: Player, owner_ship: PlayerShip) -> void:
	player = suit_player
	ship = owner_ship
	_camera = player.get_node("Camera3D") as Camera3D
	tablet = preload("res://ui/world_screen.tscn").instantiate() as WorldScreen
	tablet.name = "Tablet"
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


## Grip a nearby terminal only at a safe relative approach speed.
func open_terminal(screen: WorldScreen) -> bool:
	if not is_instance_valid(screen) or not screen.is_available() or is_open():
		return false
	var offset: Vector3 = player.global_position - ship.to_global(ship.center_of_mass)
	var carrier_velocity: Vector3 = ship.linear_velocity + ship.angular_velocity.cross(offset)
	if _camera.global_position.distance_to(screen.global_position) > 2.5 or (player.linear_velocity - carrier_velocity).length() > 0.5:
		hint = "Approach within 2.5 m and brake before using the terminal"
		return false
	# The handhold transfers the small relative impulse to the ship on engagement.
	ship.apply_impulse((player.linear_velocity - carrier_velocity) * player.mass, player.global_position - ship.global_position)
	_begin_input(screen)
	_docked = true
	_dock_elapsed = 0.0
	_start_local = ship.global_transform.affine_inverse() * player.global_transform
	# A held suit follows the carrier, so its frozen collider must not obstruct
	# the same hull when a physics step translates or rotates that hull.
	_carrier_collision_exception_added = not player.get_collision_exceptions().has(ship)
	if _carrier_collision_exception_added:
		player.add_collision_exception_with(ship)
	player.freeze = true
	player.grapple.detach()
	return true


## Release the cursor; leaving a terminal inherits ship motion at the handhold.
func close_screen() -> void:
	if not is_open():
		return
	active_screen.panel.cancel_input()
	if _docked:
		player.freeze = false
		player.linear_velocity = ship.linear_velocity + ship.angular_velocity.cross(player.global_position - ship.to_global(ship.center_of_mass))
		player.angular_velocity = ship.angular_velocity
		if _carrier_collision_exception_added and is_instance_valid(ship):
			player.remove_collision_exception_with(ship)
		_carrier_collision_exception_added = false
	_docked = false
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


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if _docked:
		_dock_elapsed = minf(1.0, _dock_elapsed + delta / 0.35)
		var destination: Transform3D = active_screen.global_transform
		destination.origin += destination.basis.z * 1.0 - destination.basis * _camera.position
		var target_local: Transform3D = ship.global_transform.affine_inverse() * destination
		player.global_transform = ship.global_transform * _start_local.interpolate_with(target_local, smoothstep(0.0, 1.0, _dock_elapsed))
	if is_open():
		hint = "Esc / Tab return to flight" if not _docked else "Esc / F leave terminal | Tab tablet"
		if not active_screen.is_available():
			close_screen()
	else:
		var target: WorldScreen = _aimed_screen()
		hint = "F use %s terminal | Tab tablet" % target.panel.current_app if target != null else "Tab tablet | F use terminal"


func _input(event: InputEvent) -> void:
	if not is_instance_valid(player):
		return
	if event.is_action_pressed("tablet") and not event.is_echo():
		if active_screen == tablet:
			close_screen()
		else:
			open_tablet()
		get_viewport().set_input_as_handled()
		return
	if is_open():
		if event.is_action_pressed("ui_cancel") or (event.is_action_pressed("interact") and not event.is_echo() and _docked):
			close_screen()
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
		open_terminal(_aimed_screen())
		get_viewport().set_input_as_handled()


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
