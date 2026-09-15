## The debug event trail records real state changes once each, not every frame.
extends TestCase


## Latching and releasing the boots each add exactly one matching entry; idle
## latched frames add none, matching the "only on a change" rule for the trail.
func test_boots_latch_and_release_log_once_each() -> void:
	DebugLog.clear()
	var f: Dictionary = _boots_fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	await _frames(3)
	check(boots.try_latch(), "feet engage")
	check_eq(_count("boots", "latched"), 1, "latch logs exactly one entry")
	await _frames(60)
	check_eq(_count("boots", "latched"), 1, "60 idle latched frames add no further latch entries")
	check_eq(_count("boots", "released"), 0, "still latched: no release entry yet")
	boots.release()
	check_eq(_count("boots", "released"), 1, "release logs exactly one entry")
	f.root.free()


## Toggling a ShipApi system logs once per actual change, not on a repeated
## no-op call with the same enabled state.
func test_ship_system_toggle_logs_once() -> void:
	DebugLog.clear()
	var api: ShipApi = ShipApi.new()
	check(api.set_system_enabled("sensors", false), "disable sensors")
	check_eq(_count("ship", "system sensors disabled"), 1, "disabling logs once")
	check(api.set_system_enabled("sensors", false), "idempotent disable")
	check_eq(_count("ship", "system sensors disabled"), 1, "repeating the same state does not log again")
	check(api.set_system_enabled("sensors", true), "re-enable sensors")
	check_eq(_count("ship", "system sensors enabled"), 1, "enabling logs once")


## Suit battery crossings of 25%, 10%, and empty each log once; staying in a
## band (or staying empty) across further spend does not repeat the entry.
func test_suit_battery_threshold_crossings_log_once() -> void:
	DebugLog.clear()
	var suit: SuitResources = SuitResources.new()
	suit.consume_energy(SuitResources.BATTERY_CAPACITY_J * 0.80)
	check_eq(_count("suit", "battery below 25%"), 1, "crossing 25% logs once")
	suit.consume_energy(1000.0)
	check_eq(_count("suit", "battery below 25%"), 1, "further drain in the same band does not repeat")
	suit.consume_energy(SuitResources.BATTERY_CAPACITY_J)
	check_eq(_count("suit", "battery below 10%"), 1, "crossing 10% logs once")
	check_eq(_count("suit", "battery empty"), 1, "hitting empty logs once")
	suit.consume_energy(500.0)
	check_eq(_count("suit", "battery empty"), 1, "staying empty does not repeat the log")
	suit.charge_energy(SuitResources.BATTERY_CAPACITY_J)
	check_eq(_count("suit", "battery available again"), 1, "recharging past empty logs once")


## A store wobbling around a level (flat-battery braking recharges a little, the
## load spends it) logs the drop once, and recovery only once it clearly clears.
func test_battery_wobbling_at_empty_logs_once() -> void:
	DebugLog.clear()
	var suit: SuitResources = SuitResources.new()
	suit.consume_energy(SuitResources.BATTERY_CAPACITY_J)
	var api: ShipApi = ShipApi.new()
	api.consume_energy(ShipApi.BATTERY_CAPACITY_J)
	for index: int in 100:
		suit.charge_energy(50.0)
		suit.consume_energy(60.0)
		api.store_energy(50.0)
		api.consume_energy(60.0)
	check_eq(_count("suit", "battery empty"), 1, "the suit logs going flat once")
	check_eq(_count("suit", "battery available again"), 0, "tiny regeneration does not count as recovery")
	check_eq(_count("ship", "battery depleted"), 1, "the ship logs going flat once")
	check_eq(_count("ship", "battery restored"), 0, "tiny regeneration does not count as the ship recovering")
	suit.charge_energy(SuitResources.BATTERY_CAPACITY_J * 0.05)
	api.store_energy(ShipApi.BATTERY_CAPACITY_J * 0.05)
	check_eq(_count("suit", "battery available again"), 1, "a real recharge logs once")
	check_eq(_count("ship", "battery restored"), 1, "a real ship recharge logs once")


## A completed cut logs exactly one entry once the deferred split actually runs.
func test_completed_cut_logs_once() -> void:
	DebugLog.clear()
	var wreck: SalvageWreck = _spawn(_chain())
	check(wreck.cut("ab", 100.0, "a"), "enough work queues the cut")
	await wreck.structure_changed
	check_eq(_count("cut", "cut completed: ab"), 1, "a completed cut logs exactly one entry")
	wreck.queue_free()
	await _frames(1)


func _boots_fixture() -> Dictionary:
	var holder: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var deck: RigidBody3D = DebrisField.create_box(Vector3(6, 0.2, 8), 1000.0, Color.WHITE)
	deck.position.y = -0.1
	deck.add_to_group("magnetic_surface")
	holder.add_child(deck)
	var player: Player = preload("res://scenes/player.tscn").instantiate() as Player
	player.input_enabled = false
	player.position.y = 0.92
	holder.add_child(player)
	var boots: MagneticBoots = MagneticBoots.new()
	player.add_child(boots)
	boots.configure(player)
	return {"root": holder, "player": player, "deck": deck, "boots": boots}


func _chain() -> ShipGraph:
	var graph: ShipGraph = ShipGraph.new()
	for index: int in range(3):
		var definition: PartDefinition = PartDefinition.new()
		definition.kind = "hull"
		definition.size_m = Vector3(0.7, 0.8, 0.9)
		definition.mass_kg = 10.0 * (index + 1)
		definition.value_cr = 100.0 * (index + 1)
		definition.thickness_mm = 8.0
		definition.sockets = {"left": Transform3D(Basis.IDENTITY, Vector3.LEFT * 0.35),
			"right": Transform3D(Basis.IDENTITY, Vector3.RIGHT * 0.35),
			"top": Transform3D(Basis.IDENTITY, Vector3.UP * 0.4)}
		var part: ShipPart = ShipPart.new()
		part.id = ["a", "b", "c"][index]
		part.definition = definition
		part.transform.origin = Vector3(float(index - 1) * 3.0, float(index % 2), 0.0)
		graph.add_part(part)
	graph.connect_parts("ab", "a", "right", "b", "left")
	graph.connect_parts("bc", "b", "right", "c", "left")
	return graph


func _spawn(graph: ShipGraph) -> SalvageWreck:
	var wreck: SalvageWreck = SalvageWreck.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(wreck)
	wreck.spawn(graph, Transform3D.IDENTITY)
	return wreck


func _count(source: String, substr: String) -> int:
	var total: int = 0
	for line: String in DebugLog.entries:
		if line.contains("] " + source + ":") and line.contains(substr):
			total += 1
	return total


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame
