## Finite vent forces, occlusion, and continuity while a volatile part splits free.
extends TestCase


## Each volatile supply applies its rated total impulse, then leaves the part coasting.
func test_finite_coolant_and_fuel_impulse() -> void:
	for kind: String in ["coolant", "fuel"]:
		var wreck: SalvageWreck = _wreck(kind)
		var hazards: SalvageHazards = _hazards(wreck)
		var source: WreckBody = wreck.body_for_part("tank")
		await _physics_steps(3)
		check(hazards.trigger("tank"), "%s reservoir ruptures" % kind)
		var duration: float = SalvageHazards.COOLANT_DURATION_S if kind == "coolant" else SalvageHazards.FUEL_DURATION_S
		var force: float = SalvageHazards.COOLANT_FORCE_N if kind == "coolant" else SalvageHazards.FUEL_FORCE_N
		await _physics_steps(int(ceil(duration * Engine.physics_ticks_per_second)) + 4)
		check_eq(hazards.active_count(), 0, "%s supply expires" % kind)
		check_near(source.linear_velocity.z * source.mass, force * duration, 0.1,
			"%s rated force integrates to finite impulse" % kind)
		check_near(source.linear_velocity.x, 0.0, 0.0001, "centred outlet introduces no sideways motion")
		check_near(source.angular_velocity.length(), 0.0, 0.0001, "centred outlet introduces no torque")
		var drift: Vector3 = source.linear_velocity
		await _physics_steps(5)
		check(source.linear_velocity.is_equal_approx(drift), "exhausted tank keeps coasting")
		check_eq(wreck.graph.get_part("tank").definition.mass_kg, 100.0, "rated wet-mass approximation leaves definition intact")
		check_eq(hazards.get_child_count(), 0, "expired plume visual is released")
		wreck.free()


## Repeated triggering and duplicate same-kind markers never refill or multiply a vent.
func test_single_supply_condition_and_invalid_targets() -> void:
	var wreck: SalvageWreck = _wreck("coolant")
	var hazards: SalvageHazards = _hazards(wreck)
	var tank: ShipPart = wreck.graph.get_part("tank")
	tank.definition.hazards.append(tank.definition.hazards[0].duplicate())
	check(not hazards.trigger("missing"), "unknown part cannot rupture")
	check(not hazards.was_triggered("missing"), "invalid id does not enter history")
	check(hazards.trigger("tank"), "first coolant trigger succeeds")
	check(hazards.was_triggered("tank"), "rupture history persists")
	check_eq(hazards.active_count(), 1, "duplicate marker uses the same kind reservoir")
	check_near(tank.condition, 0.85, 0.00001, "coolant rupture damages once")
	check(not hazards.trigger("tank"), "active reservoir cannot be restarted")
	hazards.configure(wreck)
	check(not hazards.trigger("tank"), "rebinding same wreck does not replenish supply")
	check_near(tank.condition, 0.85, 0.00001, "failed repeats cause no extra condition loss")
	hazards.set_physics_process(false)
	hazards._physics_process(10.0)
	check_eq(hazards.active_count(), 0, "long final tick exhausts remaining supply")
	check(not hazards.trigger("tank"), "empty reservoir cannot restart either")
	wreck.free()
	var inert: SalvageWreck = _wreck("")
	check(not _hazards(inert).trigger("tank"), "ordinary part has no volatile supply")
	inert.free()


## A tick longer than the remaining duration scales force to the funded fraction.
func test_final_partial_tick_is_scaled_and_invalid_delta_ignored() -> void:
	var wreck: SalvageWreck = _wreck("coolant")
	var hazards: SalvageHazards = _hazards(wreck)
	hazards.set_physics_process(false)
	var source: WreckBody = wreck.body_for_part("tank")
	await _physics_steps(3)
	check(hazards.trigger("tank"), "partial tick fixture starts")
	hazards._physics_process(NAN)
	hazards._physics_process(-1.0)
	check_eq(hazards.active_count(), 1, "invalid time cannot drain reservoir")
	hazards._physics_process(10.0)
	await _physics_steps(3)
	var expected: float = SalvageHazards.COOLANT_FORCE_N * SalvageHazards.COOLANT_DURATION_S / 10.0
	expected /= source.mass * Engine.physics_ticks_per_second
	check_near(source.linear_velocity.z, expected, 0.00001, "fractional final tick applies only remaining impulse rate")
	check_eq(hazards.active_count(), 0, "partial final tick closes plume")
	wreck.free()


## Exhaust imparts opposite forces to its source and the first body in its path.
func test_plume_pushes_nearest_body_and_reacts_on_source() -> void:
	var wreck: SalvageWreck = _wreck("coolant")
	var hazards: SalvageHazards = _hazards(wreck)
	var source: WreckBody = wreck.body_for_part("tank")
	var target: RigidBody3D = _target(wreck, Vector3(0.0, 0.0, -2.0))
	var farther: RigidBody3D = _target(wreck, Vector3(0.0, 0.0, -3.5))
	await _physics_steps(3)
	check(hazards.trigger("tank"), "push fixture starts")
	await _physics_steps(15)
	check(source.linear_velocity.z > 0.5, "source recoils away from exhaust")
	check(target.linear_velocity.z < -0.5, "nearest body is pushed along plume")
	check_near(farther.linear_velocity.length(), 0.0, 0.0001, "near body shields farther body")
	check_near((source.linear_velocity * source.mass + target.linear_velocity * target.mass).length(),
		0.0, 0.01, "fully intercepted plume conserves two-body momentum")
	wreck.free()


## Static obstacles stop plume transfer; targets past the exhaust reach stay still.
func test_static_obstacle_and_range_block_target_push() -> void:
	for blocked: bool in [true, false]:
		var wreck: SalvageWreck = _wreck("coolant")
		var target: RigidBody3D = _target(wreck, Vector3(0.0, 0.0, -3.0 if blocked else -6.0))
		if blocked:
			var wall: StaticBody3D = StaticBody3D.new()
			_add_shape(wall)
			wall.position = Vector3(0.0, 0.0, -1.5)
			wreck.add_child(wall)
		await _physics_steps(3)
		check(_hazards(wreck).trigger("tank"), "blocked/range fixture starts")
		await _physics_steps(12)
		check_near(target.linear_velocity.length(), 0.0, 0.0001,
			"wall blocks plume" if blocked else "plume cannot push beyond four metres")
		check(wreck.body_for_part("tank").linear_velocity.z > 0.1,
			"escaping or blocked exhaust still recoils on source")
		wreck.free()


## A severed active tank keeps the outlet and force on its newly created owner.
func test_plume_follows_part_after_split_and_applies_offcenter_torque() -> void:
	var wreck: SalvageWreck = _wreck("fuel", true)
	var hazards: SalvageHazards = _hazards(wreck)
	var tank: ShipPart = wreck.graph.get_part("tank")
	tank.definition.hazards[0]["transform"] = Transform3D(Basis.IDENTITY, Vector3(0.25, 0.0, -0.51))
	await _physics_steps(3)
	check(hazards.trigger("tank"), "fuel outlet ruptures")
	check_near(tank.condition, 0.75, 0.00001, "fuel rupture damages tank once")
	var old_id: int = wreck.body_for_part("tank").get_instance_id()
	check(wreck.cut("joint", 10.0, "tank"), "joint cut queues split")
	await _physics_steps(5)
	var new_body: WreckBody = wreck.body_for_part("tank")
	var hull: WreckBody = wreck.body_for_part("hull")
	check(new_body.get_instance_id() != old_id, "tank has a new body after split")
	check(new_body != hull, "tank separates from hull")
	check_eq(hazards.active_count(), 1, "vent survives replacement of old owner")
	var before: Vector3 = new_body.linear_velocity
	var hull_before: Vector3 = hull.linear_velocity
	await _physics_steps(8)
	check(new_body.linear_velocity.distance_to(before) > 0.2, "new tank owner continues receiving vent force")
	check(hull.linear_velocity.distance_to(hull_before) < 0.001, "old connected hull no longer receives tank force")
	check(new_body.angular_velocity.length() > 0.01, "offcentre outlet spins its new owner")
	hazards._process(0.0)
	var visual: MeshInstance3D = hazards.get_child(0) as MeshInstance3D
	var marker: Transform3D = wreck.part_pose("tank") * Transform3D(tank.definition.hazards[0]["transform"])
	var expected: Vector3 = marker.origin - marker.basis.z * SalvageHazards.PLUME_RANGE_M * 0.5
	check(visual.global_position.distance_to(expected) < 0.0001, "plume visual follows moving rotated outlet")
	wreck.free()


## Cutting during an intercepted vent cannot discard force queued on the old body.
func test_split_during_active_plume_preserves_reciprocal_momentum() -> void:
	var wreck: SalvageWreck = _wreck("coolant", true)
	var target: RigidBody3D = _target(wreck, Vector3(0.0, 0.0, -2.0))
	await _physics_steps(3)
	check(_hazards(wreck).trigger("tank"), "intercepted split fixture starts")
	await _physics_steps(3)
	check(wreck.cut("joint", 10.0, "tank"), "cut starts while vent is applying both forces")
	await wreck.structure_changed
	await _physics_steps(3)
	var momentum: Vector3 = target.mass * target.linear_velocity
	for body: WreckBody in wreck.bodies:
		momentum += body.mass * body.linear_velocity
	check(momentum.length() < 0.001, "replacement preserves vent impulse already applied to target")
	check_eq(wreck.bodies.size(), 2, "momentum check includes both new fragments")
	wreck.free()


## Losing a source or the entire wreck retires its plume without invalid node access.
func test_missing_source_and_wreck_stop_plumes() -> void:
	var wreck: SalvageWreck = _wreck("fuel")
	var hazards: SalvageHazards = _hazards(wreck)
	check(hazards.trigger("tank"), "target loss fixture starts")
	var body: WreckBody = wreck.body_for_part("tank")
	wreck.bodies.erase(body)
	body.free()
	await _physics_steps(3)
	check_eq(hazards.active_count(), 0, "removed source retires plume")
	check(hazards.was_triggered("tank"), "removed source does not refill history")
	wreck.remove_child(hazards)
	_tree().root.add_child(hazards)
	wreck.free()
	await _physics_steps(3)
	check(not hazards.trigger("tank"), "freed wreck cannot be triggered")
	hazards.free()


func _wreck(kind: String, connected: bool = false) -> SalvageWreck:
	var wreck: SalvageWreck = SalvageWreck.new()
	_tree().root.add_child(wreck)
	var graph: ShipGraph = ShipGraph.new()
	var tank: ShipPart = _part("tank", Vector3.ZERO)
	if kind != "":
		tank.definition.hazards = [{"kind": kind,
			"transform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.51))}]
	graph.add_part(tank)
	if connected:
		graph.add_part(_part("hull", Vector3(2.0, 0.0, 0.0)))
		graph.connect_parts("joint", "tank", "mount", "hull", "mount")
	wreck.spawn(graph, Transform3D.IDENTITY)
	var hazards: SalvageHazards = SalvageHazards.new()
	hazards.name = "HazardsFixture"
	wreck.add_child(hazards)
	hazards.configure(wreck)
	return wreck


func _part(id: String, at: Vector3) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.id = id
	part.definition = PartDefinition.new()
	part.definition.kind = "tank"
	part.definition.mass_kg = 100.0
	part.definition.size_m = Vector3.ONE
	part.definition.sockets = {"mount": Transform3D.IDENTITY}
	part.transform.origin = at
	return part


func _hazards(wreck: SalvageWreck) -> SalvageHazards:
	return wreck.get_node("HazardsFixture") as SalvageHazards


func _target(wreck: SalvageWreck, at: Vector3) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = 100.0
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.can_sleep = false
	body.position = at
	_add_shape(body)
	wreck.add_child(body)
	return body


func _add_shape(body: PhysicsBody3D) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3.ONE * 0.5
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _physics_steps(count: int) -> void:
	for index: int in range(count):
		await _tree().physics_frame
