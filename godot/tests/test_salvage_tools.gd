## Powered EVA tools obey reach, visibility, battery, reaction, and scan stability rules.
extends TestCase


## A stationary two-second pulse reveals only parts within 20 metres and then stops drawing.
func test_scanner_time_range_reveal_and_completion_budget() -> void:
	var graph: ShipGraph = ShipGraph.new()
	graph.add_part(_part("near", Vector3(0.0, 0.55, -4.0)))
	graph.add_part(_part("side", Vector3(10.0, 0.55, -5.0)))
	graph.add_part(_part("far", Vector3(0.0, 0.55, -21.0)))
	var fixture: Dictionary = _fixture(graph)
	var tools: SalvageTools = fixture.tools
	var player: Player = fixture.player
	tools.select_tool(SalvageTools.Tool.SCANNER)
	tools.set_triggers(true, false)
	tools._physics_process(1.0)
	check_near(tools.scan_progress, 0.5, 0.000001, "one second gives half a scan")
	check(not graph.get_part("near").scanned, "partial pulse reveals nothing")
	tools._physics_process(1.0)
	check_eq(tools.scan_progress, 1.0, "two seconds completes scan")
	check(graph.get_part("near").scanned, "nearby part revealed")
	check(graph.get_part("side").scanned, "pulse reaches nearby parts away from aim ray")
	check(not graph.get_part("far").scanned, "part beyond 20 m remains unknown")
	check_eq(player.suit.battery_energy_j, 719700.0, "complete scan costs 300 J")
	tools._physics_process(5.0)
	check_eq(player.suit.battery_energy_j, 719700.0, "holding completed scan does not keep consuming power")
	check_eq(player.suit.propellant_kg, 8.0, "scan uses no RCS propellant")
	fixture.root.free()


## Drift, spin, and changed aim each discard partial scan progress without drawing power.
func test_scanner_motion_release_and_switch_cancel() -> void:
	var fixture: Dictionary = _fixture(_joint_graph())
	var tools: SalvageTools = fixture.tools
	var player: Player = fixture.player
	tools.select_tool(SalvageTools.Tool.SCANNER)
	tools.set_triggers(true, false)
	tools._physics_process(0.5)
	check_near(tools.scan_progress, 0.25, 0.000001, "stationary scan starts")
	var energy: float = player.suit.battery_energy_j
	player.linear_velocity = Vector3.RIGHT * 0.21
	tools._physics_process(0.5)
	check_eq(tools.scan_progress, 0.0, "drift cancels progress")
	check_eq(player.suit.battery_energy_j, energy, "unstable scan uses no power")
	player.linear_velocity = Vector3.ZERO
	tools._physics_process(0.5)
	player.angular_velocity = Vector3.UP * 0.11
	energy = player.suit.battery_energy_j
	tools._physics_process(0.5)
	check_eq(tools.scan_progress, 0.0, "spin cancels progress")
	check_eq(player.suit.battery_energy_j, energy, "spinning scan uses no power")
	player.angular_velocity = Vector3.ZERO
	tools._physics_process(0.5)
	player.get_node("Camera3D").rotate_y(0.1)
	tools._physics_process(0.5)
	check_eq(tools.scan_progress, 0.0, "mouse aim change cancels progress")
	tools._physics_process(0.5)
	check(tools.scan_progress > 0.0, "steady new aim starts a fresh pulse")
	tools.set_triggers(false, false)
	tools._physics_process(0.1)
	check_eq(tools.scan_progress, 0.0, "release cancels pulse")
	tools.set_triggers(true, false)
	tools._physics_process(0.5)
	tools.select_tool(SalvageTools.Tool.WINCH)
	check_eq(tools.scan_progress, 0.0, "tool switch cancels pulse")
	energy = player.suit.battery_energy_j
	tools._physics_process(0.1)
	check_eq(player.suit.battery_energy_j, energy, "switch does not carry held trigger into the winch")
	fixture.root.free()


## Selecting the winch slot uses a device kit on left click instead of grabbing.
func test_winch_slot_places_a_device_and_does_not_grab() -> void:
	var fixture: Dictionary = _fixture(_joint_graph())
	var tools: SalvageTools = fixture.tools
	var player: Player = fixture.player
	var grip: PhysicalGrip = PhysicalGrip.new()
	player.add_child(grip)
	grip.configure(player, player.get_node("Camera3D") as Camera3D)
	_wall(fixture.root, Vector3(0.0, 0.55, -1.5))
	await _frames(3)
	tools.select_tool(SalvageTools.Tool.WINCH)
	var kits_before: int = tools._winch.kits_available
	tools.set_triggers(true, false)
	tools._physics_process(0.1)
	check_eq(tools._winch.kits_available, kits_before - 1, "left click on slot 3 spends a winch kit")
	check(not grip.is_attached(), "left click on slot 3 no longer grabs the aimed surface")
	fixture.root.free()


## An incomplete final scan draws the remaining charge without revealing partial data.
func test_scanner_partial_battery_cannot_finish_unpaid_work() -> void:
	var fixture: Dictionary = _fixture(_joint_graph())
	var tools: SalvageTools = fixture.tools
	var player: Player = fixture.player
	player.suit.battery_energy_j = 75.0
	tools.select_tool(SalvageTools.Tool.SCANNER)
	tools.set_triggers(true, false)
	tools._physics_process(1.0)
	check_near(tools.scan_progress, 0.25, 0.000001, "partial battery buys half a second")
	check_eq(player.suit.battery_energy_j, 0.0, "scanner drains final charge exactly")
	tools._physics_process(10.0)
	check_near(tools.scan_progress, 0.25, 0.000001, "empty scanner gains no progress")
	check(not fixture.wreck.graph.get_part("a").scanned, "unpaid scan cannot reveal a part")
	fixture.root.free()


## A visible gold joint receives powered cutting time from the finite suit battery.
func test_cutter_visible_joint_and_partial_energy() -> void:
	var fixture: Dictionary = _fixture(_joint_graph())
	var tools: SalvageTools = fixture.tools
	var player: Player = fixture.player
	var wreck: SalvageWreck = fixture.wreck
	await _frames(3)
	tools.select_tool(SalvageTools.Tool.CUTTER)
	tools.set_triggers(true, false)
	player.suit.battery_energy_j = 120.0
	tools._physics_process(0.25)
	check_eq(player.suit.battery_energy_j, 0.0, "cutter cannot draw beyond final charge")
	check_near(float(wreck.cut_progress.get("joint", 0.0)), 0.0004, 0.000001, "120 J buys 0.1 seconds against 1000 mm joint")
	check_near(tools.heat, 0.024, 0.000001, "only powered cutting time adds heat")
	tools._physics_process(0.25)
	check_near(float(wreck.cut_progress.get("joint", 0.0)), 0.0004, 0.000001, "empty cutter makes no further progress")
	check_eq(player.suit.propellant_kg, 8.0, "cutting does not consume propellant")
	fixture.root.free()


## Intervening material and joints beyond eight metres cannot be cut or billed.
func test_cutter_range_and_intervening_material() -> void:
	var fixture: Dictionary = _fixture(_joint_graph())
	var tools: SalvageTools = fixture.tools
	var player: Player = fixture.player
	var blocker: StaticBody3D = _wall(fixture.root, Vector3(0.0, 0.55, -2.0))
	await _frames(3)
	tools.select_tool(SalvageTools.Tool.CUTTER)
	tools.set_triggers(true, false)
	tools._physics_process(0.5)
	check_eq(player.suit.battery_energy_j, 720000.0, "wall blocks cut and power draw")
	check_eq(fixture.wreck.cut_progress.size(), 0, "blocked cut cannot progress")
	blocker.free()
	fixture.wreck.bodies[0].position.z -= 6.0
	await _frames(2)
	tools._physics_process(0.5)
	check_eq(player.suit.battery_energy_j, 720000.0, "distant joint cannot draw power")
	check_eq(fixture.wreck.cut_progress.size(), 0, "joint beyond 8 m cannot progress")
	fixture.root.free()


## Another wreck part can cover a joint even when the cutter ray finds its marker.
func test_cutter_covering_part_blocks_inner_joint() -> void:
	var graph: ShipGraph = _joint_graph()
	graph.add_part(_part("cover", Vector3(0.0, 0.55, -2.0)))
	var fixture: Dictionary = _fixture(graph)
	var tools: SalvageTools = fixture.tools
	await _frames(3)
	tools.select_tool(SalvageTools.Tool.CUTTER)
	tools.set_triggers(true, false)
	tools._physics_process(0.5)
	check_eq(fixture.player.suit.battery_energy_j, 720000.0, "covering part blocks powered beam")
	check_eq(fixture.wreck.cut_progress.size(), 0, "inner joint cannot progress through covering part")
	fixture.root.free()


## Sustained cutting overheats; the stopped beam cools before cutting can resume.
func test_cutter_overheat_cooldown_and_aim_miss_cooling() -> void:
	var fixture: Dictionary = _fixture(_joint_graph())
	var tools: SalvageTools = fixture.tools
	var player: Player = fixture.player
	await _frames(3)
	tools.select_tool(SalvageTools.Tool.CUTTER)
	tools.set_triggers(true, false)
	tools._physics_process(5.0)
	check_eq(tools.heat, 1.0, "sustained powered beam reaches heat cap")
	var energy: float = player.suit.battery_energy_j
	tools._physics_process(1.0)
	check_near(tools.heat, 0.82, 0.000001, "overheated beam cools at 0.18 per second")
	check_eq(player.suit.battery_energy_j, energy, "overheated cutter does no powered work")
	tools.set_triggers(false, false)
	tools._physics_process(4.0)
	check(tools.heat <= 0.25, "release cools below restart threshold")
	tools.set_triggers(true, false)
	tools._physics_process(0.5)
	check(player.suit.battery_energy_j < energy, "cooled cutter can work again")
	player.get_node("Camera3D").rotate_y(PI * 0.5)
	var heat: float = tools.heat
	energy = player.suit.battery_energy_j
	tools._physics_process(0.1)
	check(tools.heat < heat, "held trigger with no beam still cools")
	check_eq(player.suit.battery_energy_j, energy, "aim miss consumes no battery")
	fixture.root.free()


## Cutting a safe hull endpoint leaves a connected reservoir intact; its own mount ruptures it.
func test_cutter_hazard_depends_on_aimed_endpoint() -> void:
	var graph: ShipGraph = _joint_graph()
	graph.get_part("b").definition.hazards = [{"kind": "coolant", "transform": Transform3D.IDENTITY}]
	var fixture: Dictionary = _fixture(graph)
	var tools: SalvageTools = fixture.tools
	var player: Player = fixture.player
	var hazards: SalvageHazards = fixture.hazards
	await _frames(3)
	tools.select_tool(SalvageTools.Tool.CUTTER)
	tools.set_triggers(true, false)
	tools._physics_process(0.1)
	check(not hazards.was_triggered("b"), "safe hull side does not rupture connected tank")
	check_near(graph.get_part("b").condition, 1.0, 0.000001, "safe cut leaves hazardous part condition intact")
	player.position.x = 3.0
	await _frames(2)
	tools._physics_process(0.1)
	check(hazards.was_triggered("b"), "direct cutting of reservoir mount triggers coolant")
	check_eq(hazards.active_count(), 1, "one reservoir produces one plume")
	check_near(graph.get_part("b").condition, 0.85, 0.000001, "rupture reduces hazardous part value")
	fixture.root.free()


func _fixture(graph: ShipGraph) -> Dictionary:
	var holder: Node3D = Node3D.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(holder)
	var packed: PackedScene = load("res://scenes/player.tscn")
	var player: Player = packed.instantiate() as Player
	player.input_enabled = false
	holder.add_child(player)
	var wreck: SalvageWreck = SalvageWreck.new()
	holder.add_child(wreck)
	wreck.spawn(graph, Transform3D.IDENTITY)
	for body: WreckBody in wreck.bodies:
		body.freeze = true
	var hazards: SalvageHazards = SalvageHazards.new()
	holder.add_child(hazards)
	hazards.configure(wreck)
	hazards.set_physics_process(false)
	var tools: SalvageTools = SalvageTools.new()
	player.add_child(tools)
	tools.configure(player, wreck, hazards)
	tools.set_physics_process(false)
	return {"root": holder, "player": player, "wreck": wreck, "hazards": hazards, "tools": tools}


func _part(id: String, position: Vector3) -> ShipPart:
	var definition: PartDefinition = PartDefinition.new()
	definition.kind = "hull"
	definition.mass_kg = 100.0
	definition.thickness_mm = 1000.0
	definition.sockets = {"front": Transform3D(Basis.IDENTITY, Vector3.BACK * 0.5)}
	var part: ShipPart = ShipPart.new()
	part.id = id
	part.definition = definition
	part.transform.origin = position
	return part


func _joint_graph() -> ShipGraph:
	var graph: ShipGraph = ShipGraph.new()
	graph.add_part(_part("a", Vector3(0.0, 0.55, -4.0)))
	graph.add_part(_part("b", Vector3(3.0, 0.55, -4.0)))
	graph.connect_parts("joint", "a", "front", "b", "front")
	return graph


func _box(holder: Node3D, position: Vector3, mass: float) -> RigidBody3D:
	var body: RigidBody3D = DebrisField.create_box(Vector3.ONE, mass, Color.WHITE)
	body.position = position
	holder.add_child(body)
	return body


func _wall(holder: Node3D, position: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = position
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 0.2)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	holder.add_child(body)
	return body


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame


func _check_vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s expected %s, got %s" % [message, expected, actual])


func _angular_momentum(body: RigidBody3D) -> Vector3:
	return body.get_inverse_inertia_tensor().inverse() * body.angular_velocity + body.global_position.cross(body.mass * body.linear_velocity)
