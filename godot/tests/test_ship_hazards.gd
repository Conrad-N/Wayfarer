## Real plume raycasts transfer force and cumulative damage into the starter ship.
extends TestCase


## Repeated intercepted ticks damage the correct system and push both physical bodies.
func test_intercepted_fuel_and_coolant_damage_accumulates() -> void:
	for kind: String in ["fuel", "coolant"]:
		var fixture: Dictionary = _fixture(kind, false)
		var ship: PlayerShip = fixture.ship
		var source: WreckBody = fixture.source
		var hazards: SalvageHazards = fixture.hazards
		var affected: String = "power" if kind == "fuel" else "rcs"
		var unaffected: String = "rcs" if kind == "fuel" else "power"
		await _frames(3)
		check(hazards.trigger("tank"), "%s rupture starts" % kind)
		await _frames(12)
		var first: float = float(ship.api.get_telemetry().systems[affected].health)
		check(first < 1.0, "%s plume reaches ship and damages %s" % [kind, affected])
		await _frames(12)
		var data: Dictionary = ship.api.get_telemetry()
		var second: float = float(data.systems[affected].health)
		var force: float = SalvageHazards.FUEL_FORCE_N if kind == "fuel" else SalvageHazards.COOLANT_FORCE_N
		var expected_loss: float = force * 12.0 / float(Engine.physics_ticks_per_second) * 20.0 / PlayerShip.SECTION_DAMAGE_ENERGY_J
		check_near(first - second, expected_loss, 0.000001, "damage integrates each intercepted tick in joules")
		check(second < first, "continued exposure accumulates damage")
		check_eq(data.systems[unaffected].health, 1.0, "other propulsion/power system unaffected")
		check_eq(data.systems.hull.health, 1.0, "plume damage does not masquerade as hull collision damage")
		check(float(data.ship_health) < 1.0, "shared health readout reflects live plume damage")
		check(ship.linear_velocity.z < -0.005, "intercepted plume pushes the ship")
		check(source.linear_velocity.z > 0.05, "vent source recoils oppositely")
		check((ship.linear_velocity * ship.mass + source.linear_velocity * source.mass).length() < 0.01, "interception retains reciprocal momentum")
		check_eq(data.battery_energy_j, ShipApi.BATTERY_CAPACITY_J, "damage does not directly consume battery contents")
		check_eq(data.propellant_kg, ShipApi.PROPELLANT_CAPACITY_KG, "passive impact does not fire ship RCS")
		(fixture.root as Node).free()


## An intervening static wall shields ship health and motion for both plume kinds.
func test_wall_blocks_ship_damage_and_push() -> void:
	for kind: String in ["fuel", "coolant"]:
		var fixture: Dictionary = _fixture(kind, true)
		var ship: PlayerShip = fixture.ship
		var source: WreckBody = fixture.source
		var hazards: SalvageHazards = fixture.hazards
		await _frames(3)
		check(hazards.trigger("tank"), "%s blocked plume starts" % kind)
		await _frames(24)
		var data: Dictionary = ship.api.get_telemetry()
		check_eq(data.ship_health, 1.0, "wall intercepts all ship damage")
		check_eq(data.systems.power.health, 1.0, "power remains healthy behind wall")
		check_eq(data.systems.rcs.health, 1.0, "RCS remains healthy behind wall")
		check_near(ship.linear_velocity.length(), 0.0, 0.00001, "occluded ship receives no plume force")
		check(source.linear_velocity.z > 0.05, "wall does not suppress source recoil")
		check_eq(hazards.active_count(), 1, "blocked reservoir still spends its finite supply")
		(fixture.root as Node).free()


## A final partial supply cannot damage beyond its remaining energy or continue after expiry.
func test_final_plume_supply_caps_damage_and_expiry_stops_it() -> void:
	for kind: String in ["fuel", "coolant"]:
		var fixture: Dictionary = _fixture(kind, false)
		var ship: PlayerShip = fixture.ship
		var hazards: SalvageHazards = fixture.hazards
		var affected: String = "power" if kind == "fuel" else "rcs"
		hazards.set_physics_process(false)
		await _frames(3)
		check(hazards.trigger("tank"), "%s final supply starts" % kind)
		var force: float = SalvageHazards.FUEL_FORCE_N if kind == "fuel" else SalvageHazards.COOLANT_FORCE_N
		var duration: float = SalvageHazards.FUEL_DURATION_S if kind == "fuel" else SalvageHazards.COOLANT_DURATION_S
		hazards._physics_process(10.0)
		var expected: float = 1.0 - force * duration * 20.0 / PlayerShip.SECTION_DAMAGE_ENERGY_J
		check_near(ship.api.get_telemetry().systems[affected].health, expected, 0.000001, "long tick damages only for funded seconds")
		check_eq(hazards.active_count(), 0, "supply expires")
		hazards._physics_process(10.0)
		await _frames(3)
		check_near(ship.api.get_telemetry().systems[affected].health, expected, 0.000001, "expired plume causes no further damage")
		check(not hazards.trigger("tank"), "expired reservoir cannot be refilled by triggering")
		(fixture.root as Node).free()


func _fixture(kind: String, blocked: bool) -> Dictionary:
	var root: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var wreck: SalvageWreck = SalvageWreck.new()
	root.add_child(wreck)
	var graph: ShipGraph = ShipGraph.new()
	var part: ShipPart = ShipPart.new()
	part.id = "tank"
	part.definition = PartDefinition.new()
	part.definition.kind = "tank"
	part.definition.mass_kg = 1000.0
	part.definition.size_m = Vector3.ONE
	part.definition.hazards = [{"kind": kind, "transform": Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.51))}]
	graph.add_part(part)
	wreck.spawn(graph, Transform3D.IDENTITY)
	var ship: PlayerShip = preload("res://scenes/player_ship.tscn").instantiate() as PlayerShip
	# Its closed outer airlock is at global z=-2, directly ahead of the outlet.
	ship.position = Vector3(0, 0, -7.9)
	root.add_child(ship)
	var hazards: SalvageHazards = SalvageHazards.new()
	root.add_child(hazards)
	hazards.configure(wreck)
	if blocked:
		var wall: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(2, 2, 0.2)
		collision.shape = shape
		wall.add_child(collision)
		wall.position = Vector3(0, 0, -1.1)
		root.add_child(wall)
	return {"root": root, "source": wreck.body_for_part("tank"), "ship": ship, "hazards": hazards}


func _frames(count: int) -> void:
	for index: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
