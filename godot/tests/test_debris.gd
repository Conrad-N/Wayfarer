## Exercises the debris room and real suit collisions through headless Jolt physics.
extends TestCase

const FIELD_SCENE: String = "res://scenes/debris_field.tscn"
const PLAYER_SCENE: String = "res://scenes/player.tscn"


## The practice room contains a dozen loose objects spanning suit and ship masses.
func test_field_has_twelve_free_bodies_with_varied_masses() -> void:
	var field: Node3D = _spawn_field()
	if field == null:
		return
	var bodies: Array[RigidBody3D] = _bodies(field)
	check_eq(bodies.size(), 12, "dozen debris bodies")
	var masses: Array[float] = []
	var free_bodies: bool = true
	var initially_still: bool = true
	for body in bodies:
		if not masses.has(body.mass):
			masses.append(body.mass)
		free_bodies = free_bodies and not body.freeze and not body.lock_rotation
		free_bodies = free_bodies and body.gravity_scale == 0.0
		free_bodies = free_bodies and body.linear_damp_mode == RigidBody3D.DAMP_MODE_REPLACE
		free_bodies = free_bodies and body.angular_damp_mode == RigidBody3D.DAMP_MODE_REPLACE
		free_bodies = free_bodies and body.linear_damp == 0.0 and body.angular_damp == 0.0
		for axis in [PhysicsServer3D.BODY_AXIS_LINEAR_X, PhysicsServer3D.BODY_AXIS_LINEAR_Y,
			PhysicsServer3D.BODY_AXIS_LINEAR_Z, PhysicsServer3D.BODY_AXIS_ANGULAR_X,
			PhysicsServer3D.BODY_AXIS_ANGULAR_Y, PhysicsServer3D.BODY_AXIS_ANGULAR_Z]:
			free_bodies = free_bodies and not body.get_axis_lock(axis)
		initially_still = initially_still and body.linear_velocity == Vector3.ZERO
		initially_still = initially_still and body.angular_velocity == Vector3.ZERO
	check(free_bodies, "all debris can translate and rotate freely without gravity or damping")
	check(initially_still, "debris starts at rest")
	check(masses.size() >= 6, "several distinct mass responses to practice")
	if not masses.is_empty():
		check(float(masses.min()) < 100.0, "some objects weigh less than the suit")
		check(float(masses.max()) >= 4000.0, "some objects weigh much more than the suit")
	field.free()


## No object starts inside a wall, another object, or the player's starting capsule.
func test_initial_placement_is_clear_of_room_player_and_other_debris() -> void:
	var field: Node3D = _spawn_field()
	if field == null:
		return
	var room: AABB = AABB(Vector3(-12.0, -7.0, -15.0), Vector3(24.0, 14.0, 30.0))
	var player_bounds: AABB = AABB(Vector3(-0.35, -0.9, 7.65), Vector3(0.7, 1.8, 0.7))
	var bounds: Array[AABB] = []
	for body in _bodies(field):
		var box: AABB = _body_bounds(body)
		check(box.has_volume(), "%s has solid collision geometry" % body.name)
		check(room.encloses(box), "%s fits inside the room" % body.name)
		check(not box.intersects(player_bounds), "%s clears the player spawn" % body.name)
		bounds.append(box)
	var overlapping: bool = false
	for i in bounds.size():
		for j in range(i + 1, bounds.size()):
			overlapping = overlapping or bounds[i].intersects(bounds[j])
	check(not overlapping, "debris collision bounds do not overlap at spawn")
	await _physics_steps(15)
	var still: bool = true
	for body in _bodies(field):
		still = still and body.linear_velocity.length() < 0.0001
		still = still and body.angular_velocity.length() < 0.0001
	check(still, "registration creates no collision impulses between initially separate objects")
	field.free()


## The imported hull's physical mass and convex extent match the Blender asset.
func test_hull_uses_imported_mass_and_matching_convex_collision() -> void:
	var hull: RigidBody3D = DebrisField.create_hull()
	check(hull != null, "hull fixture builds")
	if hull == null:
		return
	_tree().root.add_child(hull)
	var mesh: MeshInstance3D = _find_type(hull, "MeshInstance3D") as MeshInstance3D
	var collision: CollisionShape3D = _find_type(hull, "CollisionShape3D") as CollisionShape3D
	check(mesh != null and mesh.mesh != null, "original hull mesh is present")
	check(collision != null and collision.shape is ConvexPolygonShape3D, "hull has a convex collision shape")
	if mesh != null and mesh.mesh != null:
		var extras: Dictionary = mesh.get_meta("extras", {})
		check_eq(str(extras.get("part_kind", "")), "hull", "hull metadata is preserved")
		check_near(hull.mass, float(extras.get("mass_kg", 0.0)), 0.001, "physics uses imported kilograms")
		check_near(hull.mass, 4200.0, 0.001, "sample hull mass")
		var visible: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		var physical: AABB = _body_bounds(hull)
		_check_vector(physical.position, visible.position, 0.01, "collision starts at visible hull bounds")
		_check_vector(physical.size, visible.size, 0.01, "collision covers the visible hull")
	hull.free()


## Equal suit impacts transfer equal total momentum; light debris moves much faster.
func test_suit_bumps_transfer_momentum_according_to_mass() -> void:
	var light: RigidBody3D = DebrisField.create_box(Vector3(2.0, 2.0, 2.0), 20.0, Color.GRAY)
	var heavy: RigidBody3D = DebrisField.create_box(Vector3(2.0, 2.0, 2.0), 1800.0, Color.GRAY)
	var light_player: Player = _spawn_impact(light, Vector3.ZERO, 3.0)
	var heavy_player: Player = _spawn_impact(heavy, Vector3(20.0, 0.0, 0.0), 3.0)
	await _physics_steps(Engine.physics_ticks_per_second * 2)
	_check_impact(light_player, light, "light box")
	_check_impact(heavy_player, heavy, "heavy box")
	check(light.linear_velocity.length() > heavy.linear_velocity.length() * 10.0,
		"same impact moves light debris much faster")
	check(light_player.linear_velocity.length() > heavy_player.linear_velocity.length() * 5.0,
		"heavy debris stops the incoming suit more strongly")
	light_player.free()
	heavy_player.free()
	light.free()
	heavy.free()


## The visible imported hull is an actual movable obstacle to the suit.
func test_suit_bumps_imported_hull_and_conserves_momentum() -> void:
	var hull: RigidBody3D = DebrisField.create_hull()
	check(hull != null, "hull fixture builds")
	if hull == null:
		return
	var player: Player = _spawn_impact(hull, Vector3.ZERO, 5.0)
	await _physics_steps(Engine.physics_ticks_per_second * 2)
	_check_impact(player, hull, "imported hull")
	check(player.linear_velocity.length() < 0.2, "massive hull arrests most of the suit's approach")
	player.free()
	hull.free()


## Debris keeps moving and spinning after an impulse; vacuum has no hidden drag.
func test_isolated_debris_coasts_after_impulse() -> void:
	var body: RigidBody3D = DebrisField.create_box(Vector3(1.0, 2.0, 1.0), 50.0, Color.GRAY)
	_tree().root.add_child(body)
	await _physics_steps(3)
	body.apply_central_impulse(Vector3(50.0, 25.0, -100.0))
	body.apply_torque_impulse(Vector3(0.0, 2.0, 0.0))
	await _physics_steps(3)
	var velocity: Vector3 = body.linear_velocity
	var spin: Vector3 = body.angular_velocity
	var position_before: Vector3 = body.position
	_check_vector(velocity, Vector3(1.0, 0.5, -2.0), 0.001, "impulse divided by mass gives velocity")
	check(spin.length() > 0.01, "torque impulse starts spinning debris")
	var steps: int = Engine.physics_ticks_per_second
	await _physics_steps(steps)
	_check_vector(body.linear_velocity, velocity, 0.0001, "linear momentum persists")
	_check_vector(body.angular_velocity, spin, 0.0001, "spin persists about principal axis")
	_check_vector(body.position - position_before, velocity, 0.01, "one second of coasting follows velocity")
	body.free()


func _spawn_field() -> Node3D:
	var packed: PackedScene = load(FIELD_SCENE)
	check(packed != null, "reusable debris scene loads")
	if packed == null:
		return null
	var field: Node3D = packed.instantiate() as Node3D
	_tree().root.add_child(field)
	return field


func _bodies(field: Node3D) -> Array[RigidBody3D]:
	var bodies: Array[RigidBody3D] = []
	for child in field.get_children():
		if child is RigidBody3D:
			bodies.append(child as RigidBody3D)
	return bodies


func _spawn_impact(body: RigidBody3D, at: Vector3, separation: float) -> Player:
	body.position = at
	_tree().root.add_child(body)
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Player = packed.instantiate() as Player
	player.input_enabled = false
	player.position = at + Vector3(0.0, 0.0, separation)
	player.linear_velocity = Vector3.FORWARD * 2.0
	_tree().root.add_child(player)
	return player


func _check_impact(player: Player, body: RigidBody3D, label: String) -> void:
	check(body.linear_velocity.z < -0.01, "%s gains forward momentum" % label)
	check(player.linear_velocity.z > -1.9, "%s changes suit velocity" % label)
	var momentum: Vector3 = player.linear_velocity * player.mass + body.linear_velocity * body.mass
	_check_vector(momentum, Vector3(0.0, 0.0, -200.0), 0.5, "%s conserves total momentum in kg m/s" % label)
	check_near(player.mass, 100.0, 0.001, "%s coasting impact spends no suit propellant" % label)


func _body_bounds(body: RigidBody3D) -> AABB:
	var collision: CollisionShape3D = _find_type(body, "CollisionShape3D") as CollisionShape3D
	if collision == null:
		return AABB()
	var box: BoxShape3D = collision.shape as BoxShape3D
	if box != null:
		return collision.global_transform * AABB(-box.size * 0.5, box.size)
	var convex: ConvexPolygonShape3D = collision.shape as ConvexPolygonShape3D
	if convex != null and not convex.points.is_empty():
		var bounds: AABB = AABB(convex.points[0], Vector3.ZERO)
		for point in convex.points:
			bounds = bounds.expand(point)
		return collision.global_transform * bounds
	return AABB()


func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find_type(child, type_name)
		if found != null:
			return found
	return null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _physics_steps(count: int) -> void:
	for i in count:
		await _tree().physics_frame


func _check_vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s expected %s, got %s" % [message, expected, actual])
