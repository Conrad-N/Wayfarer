## RCS approach must leave stopping fuel after a normal main-drive rendezvous.
extends TestCase


## Even 0.75 m/s initially away from a 94 m target can settle using the starter 40 kg RCS reserve.
func test_default_arrival_approach_affordability() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	var session: OrbitalSession = OrbitalSession.new()
	holder.add_child(session)
	var ship: PlayerShip = preload("res://scenes/player_ship.tscn").instantiate() as PlayerShip
	holder.add_child(ship)
	var player: Player = preload("res://scenes/player.tscn").instantiate() as Player
	player.input_enabled = false
	player.freeze = true
	player.collision_layer = 0
	player.collision_mask = 0
	holder.add_child(player)
	player.position = Vector3(0.0, 0.0, 1.0)
	var wreck: SalvageWreck = SalvageWreck.new()
	holder.add_child(wreck)
	var hazards: SalvageHazards = SalvageHazards.new()
	holder.add_child(hazards)
	hazards.configure(wreck)
	var tools: SalvageTools = SalvageTools.new()
	player.add_child(tools)
	tools.configure(player, wreck, hazards)
	player.salvage_tools = tools
	var flight: OrbitalFlight = OrbitalFlight.new()
	flight.enabled = false
	holder.add_child(flight)
	flight.configure(session, ship, player, wreck, hazards)
	var target: Dictionary = session.object_state("kestrel", session.world.time)
	session.world.replace_state(SimVector.add(target.position, SimVector.new(0.0, 0.0, 94.0)), SimVector.add(target.velocity, SimVector.new(0.0, 0.0, 0.75)))
	flight._enter_encounter("kestrel")
	check_near(ship.api.get_telemetry().propellant_kg, 40.0, 1e-9, "starter RCS reserve")
	check_near(ship.mass, 32040.0, 1e-5, "fully fuelled starting mass exercises conservative case")
	check(ship.api.flight_command("approach"), "normal rendezvous speed accepted")
	var old_hz: int = Engine.physics_ticks_per_second
	var old_scale: float = Engine.time_scale
	Engine.physics_ticks_per_second = 480
	Engine.time_scale = 8.0
	flight.enabled = true
	var deadline: float = session.world.time + 300.0
	while flight._approaching and session.world.time < deadline:
		await tree.process_frame
	flight.enabled = false
	Engine.physics_ticks_per_second = old_hz
	Engine.time_scale = old_scale
	flight._refresh_local_snapshot()
	flight._publish()
	var data: Dictionary = ship.api.get_telemetry()
	check(not flight._approaching, "finite RCS approach reaches stopping condition")
	check_near(data.flight.target.range_m, 30.0, 1.1, "thirty metre working stand-off")
	check(ship.linear_velocity.length() < 0.1, "approach brakes relative speed before completion")
	check(float(data.propellant_kg) > 9.0 and float(data.propellant_kg) < 40.0, "RCS stopping budget leaves a useful reserve")
	check(data.braking, "completed approach engages station holding")
	print("RCS APPROACH ACCEPTANCE range=", data.flight.target.range_m, " relative_speed=", ship.linear_velocity.length(), " RCS remaining=", data.propellant_kg)
	holder.free()
