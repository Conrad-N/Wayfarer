## Ship maneuvers respect restraints instead of carrying every nearby suit for free.
extends TestCase


## A floating pilot stays inertial when the main engine accelerates the surrounding ship.
func test_unrestrained_burn_uses_live_inertial_physics() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player") as Player
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	check(not ship.api.set_warp(10.0), "warp requires the actual seat")
	player.collision_layer = 0
	player.collision_mask = 0 # Isolate pre-impact freefall from the later wall collision.
	var before: Vector3 = ship.to_local(player.global_position)
	check(ship.api.set_throttle(1.0), "unrestrained pilot can command burn")
	await _frames(40)
	check(flight.ship_is_local, "burn activates inertial interior")
	check(ship.to_local(player.global_position).distance_to(before) > 0.5, "ship moves around floating pilot")
	check(player.linear_velocity.length() < 0.01, "unrestrained suit gains no magical drive impulse")
	check(ship.linear_velocity.length() > 1.0, "ship accelerates independently")
	check(not ship.api.set_warp(10.0), "freefall stays at one-times physics")
	main.free()


## The seat keeps its physical pilot through orbital flight and the local handoff.
func test_seated_burn_and_unstrap() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player") as Player
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var interaction: ShipInteraction = main.get_node("ShipInteraction") as ShipInteraction
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	player.global_transform = ship.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), PlayerShip.SEAT_POSITION)
	await _frames(3)
	check(interaction.strap_in(), "pilot straps in close to actual seat")
	await _frames(3)
	check(ship.api.set_warp(10.0), "restraint permits orbital warp")
	var before: Vector3 = ship.to_local(player.global_position)
	ship.api.set_throttle(1.0)
	await _frames(40)
	check(interaction.is_seated(), "restraint survives orbital burn")
	check(ship.to_local(player.global_position).distance_to(before) < 0.08, "seated body remains in chair")
	interaction.unstrap()
	await _frames(30)
	check(flight.ship_is_local, "unstrapping during burn switches to physical freefall")
	check(ship.to_local(player.global_position).distance_to(before) > 0.1, "unbuckled pilot is no longer carried for free")
	main.free()


## Leaving analytic seat flight inherits both the carrier's spin and its point velocity.
func test_unstrap_inherits_rotation_and_retains_hull_collision() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player") as Player
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var interaction: ShipInteraction = main.get_node("ShipInteraction") as ShipInteraction
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	check(flight.ship_is_local and not ship.freeze, "even coasting unrestrained hull exchanges physical momentum")
	player.global_transform = ship.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), PlayerShip.SEAT_POSITION)
	await _frames(3)
	check(interaction.strap_in(), "pilot secures harness")
	await _frames(3)
	check(not flight.ship_is_local and ship.freeze, "seat permits analytic coast")
	check(ship.collision_layer == 1 and ship.collision_mask == 1, "returning aboard retains physical hull geometry")
	flight.enabled = false
	flight.session.world.set_attitude_mode("manual")
	flight.session.world.angular_vel = SimVector.new(0, 0.2, 0)
	flight._advance_orbit(0.1)
	var spin: Vector3 = ship.global_basis * LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(flight.session.world.angular_vel)
	var expected_spin: Vector3 = player.angular_velocity + spin
	interaction.unstrap()
	# Unstrapping stands the pilot up beside the seat, so the tangential
	# velocity they inherit belongs to that point, not the cushion.
	check(player.global_position.is_equal_approx(ship.to_global(PlayerShip.SEAT_EXIT_POSITION)), "unstrap stands the pilot at the seat exit point")
	var expected_velocity: Vector3 = player.linear_velocity + spin.cross(player.global_position - ship.to_global(ship.center_of_mass))
	flight._begin_open_space_eva()
	check(player.angular_velocity.distance_to(expected_spin) < 0.00001, "unstrap inherits actual orbital carrier spin")
	check(player.linear_velocity.distance_to(expected_velocity) < 0.0001, "unstrap inherits tangential velocity where the pilot stands up")
	check(flight.ship_is_local and not player.freeze, "released pilot is physically free")
	main.free()


func _main() -> Node3D:
	var main: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
	(main.get_node("Player") as Player).input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	await _frames(3)
	return main


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame
