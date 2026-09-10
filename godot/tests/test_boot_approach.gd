## Held boot assistance uses finite suit actuators to meet ordinary magnetic contact rules.
extends TestCase


## A tilted floating suit aligns physically, approaches gently, and reaches a passive latch.
func test_tilted_suit_approaches_and_latches_with_paid_actuators() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	player.rotation.z = 0.9
	await _frames(3)
	boots.toggle()
	var pose: Transform3D = player.global_transform
	boots.set_approach_held(true)
	check_eq(player.global_transform, pose, "request does not teleport or instantly align suit")
	var peak_speed: float = 0.0
	var peak_spin: float = 0.0
	for index: int in range(420):
		await _frames(1)
		peak_speed = maxf(peak_speed, player.linear_velocity.length())
		peak_spin = maxf(peak_spin, player.angular_velocity.length())
		if boots.is_attached():
			break
	check(boots.is_attached(), "held assistance reaches a real steel sole latch")
	check_eq(boots.target_body(), f.deck, "ordinary latch retains approached steel deck")
	check(player.global_basis.y.dot(Vector3.UP) > 0.9, "feet rotate toward surface normal")
	check(peak_spin > 0.05, "alignment passes through physical angular motion")
	check(peak_speed > 0.05 and peak_speed < 0.4, "approach stays gentle")
	check(player.suit.propellant_kg < 8.0, "closing the gap consumes real jet propellant")
	check(player.suit.battery_energy_j < SuitResources.BATTERY_CAPACITY_J - MagneticBoots.ENGAGE_ENERGY_J, "physical alignment pays wheel energy beyond latch pulse")
	await _frames(30)
	var fuel: float = player.suit.propellant_kg
	var charge: float = player.suit.battery_energy_j
	await _frames(30)
	check(boots.is_attached(), "continuing to hold B keeps passive latch")
	check_eq(player.suit.propellant_kg, fuel, "latched hold does not keep firing approach jets")
	check_near(player.suit.battery_energy_j, charge, 0.001, "latched hold does not keep running approach wheels")
	f.root.free()


## A sideways suit on the floor first creates paid rotation clearance, then stands up.
func test_sideways_contact_backs_off_before_alignment() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	player.position.y = 0.35
	player.rotation.z = PI * 0.5
	await _frames(3)
	boots.toggle()
	boots.set_approach_held(true)
	var height_before_turn: float = 0.0
	for index: int in range(540):
		await _frames(1)
		if player.global_basis.y.dot(Vector3.UP) < 0.1:
			height_before_turn = maxf(height_before_turn, player.position.y)
		if boots.is_attached():
			break
	check(height_before_turn > 0.9, "jets create full capsule clearance before standing up")
	check(boots.is_attached(), "sideways floor contact eventually becomes sole latch: " + str(player.position) + " " + boots.status)
	check(player.global_basis.y.dot(Vector3.UP) > 0.9, "sideways suit finishes upright")
	check(player.suit.propellant_kg < 8.0, "backoff uses physical jet fuel")
	f.root.free()


## A near-deck tilted B press waits safely through the tap-to-hold delay.
func test_near_floor_tilt_waits_for_held_alignment() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	player.position.y = 0.95
	player.rotation.z = deg_to_rad(20.0)
	await _frames(3)
	var contacts: SuitContacts = SuitContacts.new()
	contacts.configure(player, null, boots)
	contacts.set_boot_input(true)
	contacts._advance_boot_hold(0.0)
	await _frames(20)
	check(boots.is_armed() and not boots.is_attached(), "tilted tap waits instead of latching into an overload")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "unsafe tilted catch does not spend repeated engagement pulses")
	contacts._advance_boot_hold(0.35)
	for index: int in range(300):
		await _frames(1)
		if boots.is_attached():
			break
	check(boots.is_attached(), "same sustained B press aligns and safely latches")
	await _frames(30)
	check(boots.is_attached(), "assisted catch remains stable after settling")
	contacts.set_boot_input(false)
	contacts.free()
	f.root.free()


## Closest eligible material wins over nearer nonmagnetic and farther steel surfaces.
func test_selects_nearest_eligible_steel_surface() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	_surface(f.root, Vector3(-1.2, 1.6, 0), Vector3(0.2, 6, 6), false)
	_surface(f.root, Vector3(2.5, 1.6, 0), Vector3(0.2, 6, 6), true)
	await _frames(3)
	boots.toggle()
	boots.set_approach_held(true)
	await _frames(60)
	check(player.linear_velocity.y < -0.1, "nearest eligible floor attracts approach command")
	check(absf(player.linear_velocity.x) < 0.02, "nearer unsuitable wall and farther steel wall are ignored")
	check(player.global_basis.y.dot(Vector3.UP) > 0.99, "nearest floor selects upward normal")
	f.root.free()


## Releasing the held command stops assistance without cancelling existing momentum.
func test_release_stops_assistance_and_preserves_drift() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	await _frames(3)
	boots.toggle()
	boots.set_approach_held(true)
	await _frames(30)
	check(player.linear_velocity.y < -0.05, "assistance creates approach drift")
	var velocity: Vector3 = player.linear_velocity
	boots.set_approach_held(false)
	check_eq(player.linear_velocity, velocity, "release never zeros existing velocity")
	await _frames(2)
	var settled_velocity: Vector3 = player.linear_velocity
	var fuel: float = player.suit.propellant_kg
	var charge: float = player.suit.battery_energy_j
	await _frames(12)
	check(not boots.is_approaching(), "released command ends approach mode")
	check(boots.is_armed(), "release retains ordinary contact arming")
	check(player.linear_velocity.distance_to(settled_velocity) < 0.001, "released suit coasts instead of secretly braking")
	check_eq(player.suit.propellant_kg, fuel, "release stops jet expense")
	check_eq(player.suit.battery_energy_j, charge, "release stops wheel expense")
	f.root.free()


## Focus cancellation and a stopped controller cannot leave a persistent suit motor request.
func test_cancel_and_stopped_controller_clear_actuators() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	await _frames(3)
	boots.toggle()
	boots.set_approach_held(true)
	await _frames(12)
	boots.cancel_input()
	check(not boots.is_approaching(), "input cancellation immediately stops assistance")
	await _frames(2)
	var fuel: float = player.suit.propellant_kg
	await _frames(6)
	check_eq(player.suit.propellant_kg, fuel, "cancelled approach consumes no stale motor fuel")
	boots.set_approach_held(true)
	await _frames(6)
	boots.set_physics_process(false)
	await _frames(2)
	fuel = player.suit.propellant_kg
	await _frames(6)
	check_eq(player.suit.propellant_kg, fuel, "a stopped controller cannot keep its last actuator request alive")
	f.root.free()


## Assistance has a local reach and never supplies force through unsuitable material.
func test_no_eligible_surface_or_outside_reach_costs_nothing() -> void:
	for unsuitable: bool in [true, false]:
		var f: Dictionary = _fixture()
		var player: Player = f.player
		var boots: MagneticBoots = f.boots
		if unsuitable:
			(f.deck as PhysicsBody3D).remove_from_group("magnetic_surface")
		else:
			player.position.y = 4.0
		await _frames(3)
		boots.toggle()
		boots.set_approach_held(true)
		await _frames(12)
		check(player.linear_velocity.length() < 0.001, "no reachable steel means no approach force")
		check(player.angular_velocity.length() < 0.001, "no reachable steel means no alignment torque")
		check_eq(player.suit.propellant_kg, 8.0, "failed search costs no fuel")
		check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "failed search costs no battery")
		f.root.free()


## A depleted suit cannot obtain free orientation or translation from magnetic assistance.
func test_empty_resources_cannot_actuate() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	player.rotation.z = 0.6
	player.suit.propellant_kg = 0.0
	player.suit.battery_energy_j = 0.0
	await _frames(3)
	var pose: Transform3D = player.global_transform
	boots.toggle()
	boots.set_approach_held(true)
	await _frames(30)
	check(player.global_position.distance_to(pose.origin) < 0.001, "empty fuel cannot close the gap")
	check(player.global_basis.y.distance_to(pose.basis.y) < 0.001, "empty battery cannot align suit")
	check(not boots.is_attached(), "unpowered approach cannot invent a latch")
	check_eq(player.suit.propellant_kg, 0.0, "approach cannot overdraw fuel")
	check_eq(player.suit.battery_energy_j, 0.0, "approach cannot overdraw battery")
	f.root.free()


## A restraint taking ownership cancels assistance and prevents later unexpected thrust.
func test_seated_suit_cancels_assistance() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	await _frames(3)
	boots.toggle()
	boots.set_approach_held(true)
	player.set_meta("seated", true)
	await _frames(12)
	check(not boots.is_armed() and not boots.is_approaching(), "seat cancels waiting and approach")
	check_eq(player.suit.propellant_kg, 8.0, "seat cannot fire assistance jets")
	player.set_meta("seated", false)
	await _frames(12)
	check(player.linear_velocity.length() < 0.001, "leaving seat does not restore stale approach")
	f.root.free()


## Hand contact remains exclusive with a held boot assistance request.
func test_hand_grip_prevents_approach() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	var grip: PhysicalGrip = PhysicalGrip.new()
	grip.name = "PhysicalGrip"
	player.add_child(grip)
	grip.configure(player)
	var cargo: RigidBody3D = DebrisField.create_box(Vector3.ONE * 0.2, 100.0, Color.WHITE)
	cargo.position = Vector3(1.0, 1.6, 0)
	f.root.add_child(cargo)
	await _frames(3)
	check(grip.grab_body(cargo, cargo.global_position), "fixture establishes actual hand restraint")
	boots.toggle()
	boots.set_approach_held(true)
	await _frames(12)
	check(not boots.is_armed() and not boots.is_approaching(), "hand restraint rejects boot assistance")
	check_eq(player.suit.propellant_kg, 8.0, "hand restraint cannot trigger approach jets")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "hand restraint cannot trigger alignment wheels")
	f.root.free()


func _fixture() -> Dictionary:
	var holder: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var deck: StaticBody3D = _surface(holder, Vector3(0, -0.1, 0), Vector3(8, 0.2, 8), true)
	var player: Player = preload("res://scenes/player.tscn").instantiate() as Player
	player.input_enabled = false
	player.position.y = 1.6
	holder.add_child(player)
	var boots: MagneticBoots = MagneticBoots.new()
	player.add_child(boots)
	boots.configure(player)
	return {"root": holder, "player": player, "deck": deck, "boots": boots}


func _surface(parent: Node3D, position: Vector3, size: Vector3, magnetic: bool) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = position
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	parent.add_child(body)
	if magnetic:
		body.add_to_group("magnetic_surface")
	return body


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame
