## Physical handholds exchange momentum, carry mass, survive cutting, and release safely.
extends TestCase


## Catching a spinning body slows its spin and carries the suit without creating momentum.
func test_spinning_catch_conserves_momentum_and_dissipates_energy() -> void:
	var fixture: Node3D = _fixture()
	var suit: RigidBody3D = _body(fixture, Vector3(2.0, 0.0, 0.0), 100.0)
	var wreck: RigidBody3D = _body(fixture, Vector3.ZERO, 1000.0)
	wreck.angular_velocity = Vector3(0.0, 0.3, 0.0)
	var grip: PhysicalGrip = _grip(fixture, suit)
	await _frames(3)
	var before: Dictionary = _totals(suit, wreck)
	var suit_pose: Transform3D = suit.global_transform
	var wreck_pose: Transform3D = wreck.global_transform
	check(grip.grab_body(wreck, wreck.global_position + Vector3.RIGHT * 0.5), "nearby spinning wreck can be caught")
	check_eq(suit.global_transform, suit_pose, "catch does not teleport suit")
	check_eq(wreck.global_transform, wreck_pose, "catch does not teleport wreck")
	await _frames(24)
	var after: Dictionary = _totals(suit, wreck)
	check(grip.is_attached(), "ordinary spin does not overload hands")
	_vector(after.linear, before.linear, 0.02, "catch conserves linear momentum")
	_vector(after.angular, before.angular, 0.15, "catch conserves angular momentum")
	check(float(after.energy) <= float(before.energy) + 0.01, "catch dissipates energy instead of creating it")
	check(wreck.angular_velocity.y < 0.3 and wreck.angular_velocity.y > 0.0, "added suit inertia slows spinning wreck")
	_vector(suit.angular_velocity, wreck.angular_velocity, 0.001, "suit spins with wreck")
	var radial: Vector3 = suit.global_position - wreck.global_position
	_vector(suit.linear_velocity - wreck.linear_velocity, wreck.angular_velocity.cross(radial), 0.001, "suit travels around the rotating wreck")
	check(suit.global_position.distance_to(suit_pose.origin) > 0.005, "suit actually moves around the wreck")
	fixture.free()


## Thrust accelerates the combined load and releasing retains the actual velocity field.
func test_carrying_mass_and_release_preserve_motion() -> void:
	var fixture: Node3D = _fixture()
	var suit: RigidBody3D = _body(fixture, Vector3(1.5, 0.0, 0.0), 100.0)
	var cargo: RigidBody3D = _body(fixture, Vector3.ZERO, 100.0)
	var grip: PhysicalGrip = _grip(fixture, suit)
	await _frames(3)
	check(grip.grab_body(cargo, Vector3(0.5, 0.0, 0.0)), "loose cargo is grippable")
	await _frames(3)
	suit.constant_force = Vector3.RIGHT * 180.0
	await _frames(2)
	var before: Vector3 = _totals(suit, cargo).linear
	await _frames(30)
	var delta_v: Vector3 = (_totals(suit, cargo).linear - before) / 200.0
	check_near(delta_v.x, 180.0 / 200.0 * 30.0 / Engine.physics_ticks_per_second, 0.005, "suit thrust moves total mass")
	var combined: Dictionary = grip.brake_state()
	check_near(combined.mass, 200.0, 0.0001, "brake sees carried mass")
	check((combined.inertia as Basis).y.y > 100.0, "brake sees parallel-axis rotational inertia")
	suit.constant_force = Vector3.ZERO
	var suit_velocity: Vector3 = suit.linear_velocity
	var cargo_velocity: Vector3 = cargo.linear_velocity
	var suit_spin: Vector3 = suit.angular_velocity
	grip.release()
	_vector(suit.linear_velocity, suit_velocity, 0.0, "release keeps suit velocity")
	_vector(cargo.linear_velocity, cargo_velocity, 0.0, "release keeps cargo velocity")
	_vector(suit.angular_velocity, suit_spin, 0.0, "release keeps spin")
	check(not grip.is_attached(), "release removes the constraint")
	check(grip.brake_state().is_empty(), "released cargo does not affect brake mass")
	fixture.free()


## A held part keeps its contact and motion when its original compound is replaced.
func test_hand_stays_on_same_part_across_cut() -> void:
	var fixture: Node3D = _fixture()
	var suit: RigidBody3D = _body(fixture, Vector3(0.0, 0.0, 1.5), 100.0)
	var wreck: SalvageWreck = SalvageWreck.new()
	fixture.add_child(wreck)
	var graph: ShipGraph = ShipGraph.new()
	for index: int in range(2):
		var definition: PartDefinition = PartDefinition.new()
		definition.kind = "mast"
		definition.mass_kg = 50.0
		definition.size_m = Vector3.ONE * 0.5
		definition.sockets = {"left": Transform3D(Basis.IDENTITY, Vector3.LEFT * 0.25), "right": Transform3D(Basis.IDENTITY, Vector3.RIGHT * 0.25)}
		var part: ShipPart = ShipPart.new()
		part.id = "antenna" if index == 0 else "hull"
		part.definition = definition
		part.transform.origin = Vector3.RIGHT * float(index) * 0.6
		graph.add_part(part)
	graph.connect_parts("mount", "antenna", "right", "hull", "left")
	wreck.spawn(graph, Transform3D.IDENTITY, Vector3.ZERO, Vector3.UP * 0.1)
	var grip: PhysicalGrip = _grip(fixture, suit)
	await _frames(3)
	var original: WreckBody = wreck.body_for_part("antenna")
	check(grip.grab_body(original, wreck.part_pose("antenna") * Vector3.BACK * 0.25, "antenna"), "grip the antenna before cutting")
	await _frames(6)
	wreck.structure_changed.emit()
	check_eq(int(original.get_meta("physical_grip_count", 0)), 1, "unrelated cargo refresh cannot duplicate grip")
	check_eq(grip.get_child_count(), 1, "unrelated refresh leaves exactly one constraint")
	var old_id: int = original.get_instance_id()
	check(wreck.cut("mount", 10.0, "antenna"), "cut antenna mount while holding it")
	await wreck.structure_changed
	check(grip.is_attached(), "handhold survives body replacement")
	check_eq(grip.held_part_id, "antenna", "stable part identity preserved")
	check(grip.target_body().get_instance_id() != old_id, "grip moves to replacement body")
	check_eq(grip.target_body(), wreck.body_for_part("antenna"), "hand follows antenna, not hull")
	await _frames(12)
	check(grip.is_attached(), "new physical joint remains stable after cut")
	suit.constant_force = Vector3.BACK * 180.0
	var old_cargo_velocity: Vector3 = grip.target_body().linear_velocity
	await _frames(12)
	check(grip.target_body().linear_velocity.z > old_cargo_velocity.z + 0.1, "suit carries freed antenna after cutting")
	fixture.free()


## Reach, incoming speed and overload prevent an unlimited-strength grab mechanic.
func test_reach_fast_catches_and_overloads_are_limited() -> void:
	var fixture: Node3D = _fixture()
	var suit: RigidBody3D = _body(fixture, Vector3(1.5, 0.0, 0.0), 100.0)
	var wreck: RigidBody3D = _body(fixture, Vector3.ZERO, 1000.0)
	var grip: PhysicalGrip = _grip(fixture, suit)
	await _frames(3)
	check(not grip.grab_body(suit, suit.global_position), "cannot grab own body")
	check(not grip.grab_body(wreck, Vector3(-5.0, 0.0, 0.0)), "cannot reach a distant point")
	wreck.linear_velocity = Vector3.UP * 10.0
	check(not grip.grab_body(wreck, Vector3(0.5, 0.0, 0.0)), "dangerous high-speed catches rejected")
	wreck.linear_velocity = Vector3.ZERO
	wreck.angular_velocity = Vector3.RIGHT * 10.0
	check(not grip.grab_body(wreck, Vector3.RIGHT * 0.5), "dangerous spin rejected even directly on its axis")
	wreck.angular_velocity = Vector3.ZERO
	check(grip.grab_body(wreck, Vector3(0.5, 0.0, 0.0)), "safe stationary catch succeeds")
	await _frames(20)
	wreck.apply_central_impulse(Vector3.UP * 100000.0)
	await _frames(5)
	check(not grip.is_attached(), "violent acceleration breaks grip")
	check_eq(grip.status, "GRIP LOST: LOAD TOO HIGH", "overload has understandable status")
	fixture.free()


## A hand-carried load remains solid against a wall and cannot be pulled through it.
func test_carried_cargo_is_blocked_by_walls() -> void:
	var fixture: Node3D = _fixture()
	var suit: RigidBody3D = _body(fixture, Vector3(1.12, 0.0, 0.0), 100.0)
	var cargo: RigidBody3D = _body(fixture, Vector3(-0.38, 0.0, 0.0), 100.0)
	var wall: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.2, 10.0, 10.0)
	collision.shape = box
	wall.position = Vector3(-1.0, 0.0, 0.0)
	wall.add_child(collision)
	fixture.add_child(wall)
	var grip: PhysicalGrip = _grip(fixture, suit)
	await _frames(3)
	check(grip.grab_body(cargo, Vector3.RIGHT * 0.12), "cargo held before approaching obstacle")
	suit.constant_force = Vector3.LEFT * 180.0
	await _frames(120)
	check(cargo.global_position.x > -0.45, "cargo surface remains outside solid wall")
	check(suit.global_position.x > 0.9, "carrier cannot pass through held cargo either")
	check(grip.is_attached(), "ordinary pushing against wall does not destroy handhold")
	fixture.free()


## Alt spends suit propellant to stop a captured spinning assembly, including carried mass.
func test_real_suit_brake_stops_both_bodies_and_spends_propellant() -> void:
	var fixture: Node3D = _fixture()
	var packed: PackedScene = load("res://scenes/player.tscn")
	var suit: Player = packed.instantiate() as Player
	suit.input_enabled = false
	suit.position = Vector3(1.5, 0.0, 0.0)
	fixture.add_child(suit)
	var wreck: RigidBody3D = _body(fixture, Vector3.ZERO, 200.0)
	wreck.angular_velocity = Vector3.UP * 0.3
	var grip: PhysicalGrip = _grip(fixture, suit)
	suit.brake_reference = grip.brake_state
	await _frames(3)
	check(grip.grab_body(wreck, Vector3.RIGHT * 0.5), "actual suit catches spinning cargo")
	await _frames(20)
	check(suit.angular_velocity.length() > 0.01, "suit has inherited cargo spin")
	var before: float = suit.suit.propellant_kg
	suit.set_braking(true)
	await _frames(180)
	check(grip.is_attached(), "braking retains the grip")
	check(suit.suit.propellant_kg < before, "combined braking consumes real suit propellant")
	check(wreck.angular_velocity.length() < 0.002, "brake stops carried object's rotation")
	check(suit.angular_velocity.length() < 0.002, "brake stops suit rotation")
	check(wreck.linear_velocity.length() < 0.003, "brake stops carried object's translation")
	check(suit.linear_velocity.length() < 0.003, "brake stops suit translation")
	suit.set_braking(false)
	fixture.free()


## Aiming obeys first-surface occlusion, and a removed carrier cannot leave a world pin.
func test_ray_cannot_grab_through_wall_and_removed_target_releases() -> void:
	var fixture: Node3D = _fixture()
	var suit: RigidBody3D = _body(fixture, Vector3(0.0, 0.0, 2.0), 100.0)
	var cargo: RigidBody3D = _body(fixture, Vector3.ZERO, 100.0)
	var camera: Camera3D = Camera3D.new()
	suit.add_child(camera)
	var grip: PhysicalGrip = _grip(fixture, suit)
	grip.configure(suit, camera)
	var wall: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.1)
	collision.shape = box
	wall.add_child(collision)
	wall.position.z = 1.0
	fixture.add_child(wall)
	await _frames(3)
	check(not grip.try_grab(), "intervening wall blocks ray to cargo")
	check(not grip.is_attached(), "occluded cargo receives no hidden attachment")
	wall.free()
	await _frames(3)
	check(grip.try_grab(), "visible nearby cargo can be grabbed by aiming")
	check_eq(grip.target_body(), cargo, "ray selects actual nearest solid body")
	cargo.queue_free()
	await _frames(3)
	check(not grip.is_attached(), "deleted cargo releases handhold")
	check_eq(grip.target_body(), null, "no stale target survives deletion")
	suit.constant_force = Vector3.UP * 180.0
	await _frames(12)
	check(suit.linear_velocity.y > 0.2, "removed target does not leave suit pinned to world")
	fixture.free()


func _fixture() -> Node3D:
	var node: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	return node


func _body(parent: Node3D, at: Vector3, mass_kg: float) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.position = at
	body.mass = mass_kg
	body.inertia = Vector3.ONE * mass_kg * 0.1
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.can_sleep = false
	body.continuous_cd = true
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.5
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _grip(_parent: Node3D, suit: RigidBody3D) -> PhysicalGrip:
	var grip: PhysicalGrip = PhysicalGrip.new()
	suit.add_child(grip)
	grip.configure(suit)
	return grip


func _totals(a: RigidBody3D, b: RigidBody3D) -> Dictionary:
	var linear: Vector3 = Vector3.ZERO
	var angular: Vector3 = Vector3.ZERO
	var energy: float = 0.0
	for body: RigidBody3D in [a, b]:
		var momentum: Vector3 = body.mass * body.linear_velocity
		var spin_momentum: Vector3 = body.get_inverse_inertia_tensor().inverse() * body.angular_velocity
		linear += momentum
		angular += spin_momentum + body.global_position.cross(momentum)
		energy += 0.5 * body.mass * body.linear_velocity.length_squared() + 0.5 * body.angular_velocity.dot(spin_momentum)
	return {"linear": linear, "angular": angular, "energy": energy}


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame


func _vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s expected %s got %s" % [message, expected, actual])


## Normal mouse motion steers a held load through the suit wheels; no modifier key is needed.
func test_mouse_steers_held_hull_without_a_modifier() -> void:
	var main: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
	var player: Player = main.get_node("Player") as Player
	player.input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	await _frames(4)
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var grip: PhysicalGrip = player.get_node("PhysicalGrip") as PhysicalGrip
	ship.api.set_attitude_mode("manual")
	ship.api.set_system_enabled("rcs", false)
	player.global_transform = ship.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.0))
	await _frames(3)
	check(grip.grab_body(ship, ship.to_global(Vector3(1.9, 0, 0))), "handhold catches the hull")
	await _frames(3)
	check(player.body_follow_enabled, "holding on leaves mouse steering enabled")
	player.queue_mouse_look(Vector2(-0.5 / player.mouse_sensitivity, 0.0))
	await _frames(30)
	check(grip.is_attached(), "steering against the hull keeps the grip")
	check(player.attitude.momentum_body.length() > 1.0, "wheels spin up against the held mass")
	var hull_momentum: Vector3 = ship.get_inverse_inertia_tensor().inverse() * ship.angular_velocity
	check(ship.angular_velocity.y > 1e-6, "the whole held load turns, not just the suit")
	check_near(hull_momentum.y, -player.attitude.momentum_body.y, 0.1 * player.attitude.momentum_body.length(), "hull takes the wheels' reaction momentum")
	_vector(player.angular_velocity, ship.angular_velocity, 0.001, "suit and hull turn together")
	main.free()
