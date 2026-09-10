## Exercises suit grappling, battery accounting, and reciprocal forces in headless Jolt.
extends TestCase


## Camera casting ignores the suit, stops at the closest surface, and charges once.
func test_camera_ray_hits_nearest_surface_and_excludes_suit() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	var near_body: StaticBody3D = _static_body(rig, Vector3(0.0, 0.0, -5.0))
	_static_body(rig, Vector3(0.0, 0.0, -10.0))
	await _physics_steps(3)
	grapple.request_attach()
	await _physics_steps(3)
	check(grapple.is_attached(), "ray passes through owning suit to attach")
	check_near(grapple.get_anchor_position().z, near_body.position.z + 1.0, 0.01,
		"nearest front face receives the cable")
	check_near(grapple.cable_length_m, 4.0, 0.01, "cable starts at harness-to-hit distance")
	check_near(_stores(rig).battery_energy_j, SuitResources.BATTERY_CAPACITY_J - grapple.attach_energy_j,
		0.001, "one successful shot spends one attachment charge")
	rig.free()


## A miss and surfaces beyond the cable's reach consume no power.
func test_camera_miss_and_out_of_range_do_not_charge() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	await _physics_steps(3)
	grapple.request_attach()
	await _physics_steps(3)
	check(not grapple.is_attached(), "empty-space shot misses")
	_static_body(rig, Vector3(0.0, 0.0, -32.0))
	await _physics_steps(3)
	grapple.request_attach()
	await _physics_steps(3)
	check(not grapple.is_attached(), "31 m surface cannot be reached")
	check_eq(_stores(rig).battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "misses cost nothing")
	rig.free()


## Invalid targets and insufficient full attachment energy cannot create a tether.
func test_attachment_validation_preserves_resources() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	var target: StaticBody3D = _static_body(rig, Vector3(0.0, 0.0, -10.0))
	check(not grapple.attach_to(null, Vector3.ZERO), "missing body rejected")
	check(not grapple.attach_to(_source(rig), Vector3.ZERO), "self attachment rejected")
	check(not grapple.attach_to(target, Vector3(0.0, 0.0, -31.0)), "overlength anchor rejected")
	check(not grapple.attach_to(target, Vector3(NAN, 0.0, 0.0)), "nonfinite anchor rejected")
	check_eq(_stores(rig).battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "invalid shots consume nothing")
	_stores(rig).battery_energy_j = grapple.attach_energy_j * 0.5
	check(not grapple.attach_to(target, target.position), "partial attachment energy is insufficient")
	check_near(_stores(rig).battery_energy_j, grapple.attach_energy_j * 0.5, 0.0001,
		"failed low-power shot retains remaining energy")
	check(not grapple.is_attached(), "failed shots leave no tether")
	rig.free()


## A replacement attaches at its own surface and only the newest object receives force.
func test_one_tether_replaces_previous_target() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	var first: RigidBody3D = _body(rig, Vector3(8.0, 0.0, 0.0), 20.0)
	var second: RigidBody3D = _body(rig, Vector3(0.0, 0.0, -10.0), 20.0)
	await _physics_steps(3)
	check(grapple.attach_to(first, first.position), "first target attaches")
	check(grapple.attach_to(second, second.position), "second target replaces first")
	_check_vector(grapple.get_anchor_position(), second.position, 0.0001, "new anchor is active")
	grapple.set_reel_input(1.0)
	await _physics_steps(30)
	check(second.linear_velocity.z > 0.1, "new target is pulled toward suit")
	_check_vector(first.linear_velocity, Vector3.ZERO, 0.0001, "old target is no longer pulled")
	rig.free()


## A surface anchor stays on the same local point while its owner turns and moves.
func test_anchor_follows_target_rotation_and_translation() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	var target: StaticBody3D = _static_body(rig, Vector3(0.0, 0.0, -10.0))
	var local_anchor: Vector3 = Vector3(1.0, 0.25, 0.0)
	check(grapple.attach_to(target, target.to_global(local_anchor)), "off-center anchor attaches")
	target.rotation = Vector3(0.0, PI * 0.5, 0.0)
	target.position += Vector3(2.0, 1.0, 0.0)
	_check_vector(grapple.get_anchor_position(), target.to_global(local_anchor), 0.0001,
		"anchor moves with target transform")
	rig.free()


## Equal opposing pull conserves momentum; the lighter member of each pair moves faster.
func test_reeling_light_and_heavy_bodies_conserves_total_momentum() -> void:
	for target_mass in [20.0, 1000.0]:
		var rig: Node3D = _rig()
		var source: RigidBody3D = _source(rig)
		var grapple: Grapple = _grapple(rig)
		var target: RigidBody3D = _body(rig, Vector3(0.0, 0.0, -10.0), target_mass)
		await _physics_steps(3)
		check(grapple.attach_to(target, target.position), "pair attaches")
		grapple.set_reel_input(1.0)
		await _physics_steps(30)
		check(source.linear_velocity.z < -0.05, "suit receives reaction toward target")
		check(target.linear_velocity.z > 0.005, "target receives force toward suit")
		_check_vector(source.linear_velocity * source.mass + target.linear_velocity * target.mass,
			Vector3.ZERO, 0.03, "internal cable force conserves total momentum")
		check_close(target.linear_velocity.length() / source.linear_velocity.length(),
			source.mass / target.mass, 0.01, "speed ratio is inverse mass ratio")
		check(source.position.distance_to(target.position) < 10.0, "reeling closes separation")
		check_near(_stores(rig).propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, 0.0001,
			"grapple uses battery without spending thruster propellant")
		rig.free()


## Even a heavily shortened cable cannot exceed the tool's rated tension.
func test_stretched_cable_respects_tension_limit() -> void:
	var rig: Node3D = _rig()
	_source(rig).freeze = true
	var grapple: Grapple = _grapple(rig)
	var target: RigidBody3D = _body(rig, Vector3(0.0, 0.0, -10.0), 1000.0)
	await _physics_steps(3)
	check(grapple.attach_to(target, target.position), "force limit fixture attaches")
	grapple.reel_speed_mps = 1000.0
	grapple.set_reel_input(1.0)
	await _physics_steps(5)
	grapple.set_reel_input(0.0)
	var before: float = target.linear_velocity.z
	await _physics_steps(30)
	var seconds: float = 30.0 / float(Engine.physics_ticks_per_second)
	check_near(target.linear_velocity.z - before, grapple.max_tension_n * seconds / target.mass,
		0.005, "saturated cable acceleration equals rated force divided by mass")
	rig.free()


## A fixed wall hauls the suit, and detaching preserves its resulting drift.
func test_static_anchor_pulls_suit_and_detach_returns_to_coasting() -> void:
	var rig: Node3D = _rig()
	var source: RigidBody3D = _source(rig)
	var grapple: Grapple = _grapple(rig)
	var wall: StaticBody3D = _static_body(rig, Vector3(0.0, 0.0, -10.0))
	await _physics_steps(3)
	check(grapple.attach_to(wall, Vector3(0.0, 0.0, -9.0)), "wall attaches")
	grapple.set_reel_input(1.0)
	await _physics_steps(30)
	check(source.linear_velocity.z < -0.1, "wall pull accelerates suit")
	grapple.detach()
	await _physics_steps(3)
	var velocity: Vector3 = source.linear_velocity
	var charge: float = _stores(rig).battery_energy_j
	await _physics_steps(30)
	check(not grapple.is_attached(), "detach removes tether")
	_check_vector(source.linear_velocity, velocity, 0.0001, "detached suit coasts")
	check_eq(_stores(rig).battery_energy_j, charge, "held reel costs nothing after detach")
	rig.free()


## The cable acts at the selected surface point, allowing an off-center pull to spin debris.
func test_off_center_pull_applies_target_torque() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	var target: RigidBody3D = _body(rig, Vector3(0.0, 0.0, -10.0), 100.0)
	await _physics_steps(3)
	check(grapple.attach_to(target, target.position + Vector3(0.8, 0.0, 1.0)), "surface corner attaches")
	grapple.set_reel_input(1.0)
	await _physics_steps(20)
	check(target.angular_velocity.y < -0.01, "off-center pull turns target about expected axis")
	_check_vector(_source(rig).angular_velocity, Vector3.ZERO, 0.0001, "central suit harness creates no suit torque")
	rig.free()


## Paying out cable leaves both bodies stationary; a slack cable never pushes them apart.
func test_slack_cable_never_pushes_and_idle_tether_draws_no_power() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	var target: RigidBody3D = _body(rig, Vector3(0.0, 0.0, -10.0), 20.0)
	await _physics_steps(3)
	check(grapple.attach_to(target, target.position), "slack test attaches")
	grapple.set_reel_input(-1.0)
	await _physics_steps(30)
	check(grapple.cable_length_m > 10.5, "reel out pays out cable")
	grapple.set_reel_input(0.0)
	var energy: float = _stores(rig).battery_energy_j
	await _physics_steps(30)
	_check_vector(_source(rig).linear_velocity, Vector3.ZERO, 0.0001, "slack cable does not push suit")
	_check_vector(target.linear_velocity, Vector3.ZERO, 0.0001, "slack cable does not push target")
	check_eq(_stores(rig).battery_energy_j, energy, "idle physical tether draws no power")
	rig.free()


## Motor energy tracks actual cable travel and neither end stop can waste battery.
func test_reel_limits_charge_only_for_actual_travel() -> void:
	var rig: Node3D = _rig()
	_source(rig).freeze = true
	var grapple: Grapple = _grapple(rig)
	var target: StaticBody3D = _static_body(rig, Vector3(0.0, 0.0, -10.0))
	await _physics_steps(3)
	check(grapple.attach_to(target, target.position), "reel fixture attaches")
	grapple.reel_speed_mps = 1000.0
	var before: float = _stores(rig).battery_energy_j
	grapple.set_reel_input(1.0)
	await _physics_steps(5)
	check_near(grapple.cable_length_m, Grapple.MIN_LENGTH_M, 0.0001, "reel in stops at minimum")
	check_near(before - _stores(rig).battery_energy_j,
		(10.0 - Grapple.MIN_LENGTH_M) * grapple.reel_power_w / grapple.reel_speed_mps, 0.0001,
		"only actual reel-in travel is billed")
	before = _stores(rig).battery_energy_j
	await _physics_steps(5)
	check_eq(_stores(rig).battery_energy_j, before, "holding reel at minimum costs nothing")
	grapple.set_reel_input(-1.0)
	await _physics_steps(5)
	check_near(grapple.cable_length_m, Grapple.MAX_LENGTH_M, 0.0001, "reel out stops at maximum")
	check_near(before - _stores(rig).battery_energy_j,
		(Grapple.MAX_LENGTH_M - Grapple.MIN_LENGTH_M) * grapple.reel_power_w / grapple.reel_speed_mps,
		0.0001, "only actual reel-out travel is billed")
	before = _stores(rig).battery_energy_j
	await _physics_steps(5)
	check_eq(_stores(rig).battery_energy_j, before, "holding reel at maximum costs nothing")
	rig.free()


## The final few joules buy proportional reel travel, then a dead battery leaves the cable intact.
func test_partial_battery_scales_travel_and_passive_tether_survives_depletion() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	var target: StaticBody3D = _static_body(rig, Vector3(0.0, 0.0, -10.0))
	await _physics_steps(3)
	check(grapple.attach_to(target, target.position), "depletion fixture attaches")
	_stores(rig).battery_energy_j = 7.5
	grapple.set_reel_input(1.0)
	await _physics_steps(5)
	var expected_travel: float = 7.5 * grapple.reel_speed_mps / grapple.reel_power_w
	check_near(grapple.cable_length_m, 10.0 - expected_travel, 0.00001, "last energy buys proportional travel")
	check_eq(_stores(rig).battery_energy_j, 0.0, "battery stops at zero")
	check(grapple.is_attached(), "battery depletion retains physical tether")
	check(_source(rig).linear_velocity.z < -0.001, "passive tension still pulls without electricity")
	var cable_length: float = grapple.cable_length_m
	grapple.set_reel_input(-1.0)
	await _physics_steps(5)
	check_eq(grapple.cable_length_m, cable_length, "empty battery cannot pay out cable")
	check(not grapple.attach_to(target, target.position), "empty battery cannot fire another attachment")
	rig.free()


## Destroyed targets, exceeded reach, and an intervening obstacle release the cable safely.
func test_target_loss_range_and_new_obstacle_release_tether() -> void:
	for reason in ["freed", "range", "blocked"]:
		var rig: Node3D = _rig()
		var grapple: Grapple = _grapple(rig)
		var target: StaticBody3D = _static_body(rig, Vector3(0.0, 0.0, -10.0))
		await _physics_steps(3)
		check(grapple.attach_to(target, target.position), "%s fixture attaches" % reason)
		if reason == "freed":
			target.free()
		elif reason == "range":
			target.position.z = -31.0
		else:
			_static_body(rig, Vector3(0.0, 0.0, -5.0))
		await _physics_steps(5)
		check(not grapple.is_attached(), "%s releases cable" % reason)
		rig.free()


## Releasing control cancels queued shots and reel input while retaining an existing tether.
func test_cancel_input_stops_motor_and_discards_queued_shot() -> void:
	var rig: Node3D = _rig()
	var grapple: Grapple = _grapple(rig)
	var target: StaticBody3D = _static_body(rig, Vector3(0.0, 0.0, -10.0))
	await _physics_steps(3)
	grapple.request_attach()
	grapple.cancel_input()
	await _physics_steps(3)
	check(not grapple.is_attached(), "cancel drops queued shot")
	check(grapple.attach_to(target, target.position), "existing tether attaches")
	var energy: float = _stores(rig).battery_energy_j
	var length_before: float = grapple.cable_length_m
	grapple.set_reel_input(1.0)
	grapple.cancel_input()
	await _physics_steps(5)
	check(grapple.is_attached(), "cancel keeps existing tether")
	check_eq(grapple.cable_length_m, length_before, "cancel stops reel motion")
	check_eq(_stores(rig).battery_energy_j, energy, "cancel stops motor energy use")
	rig.free()


## The reusable player owns a configured grapple sharing its suit's actual battery.
func test_player_scene_owns_configured_grapple() -> void:
	var packed: PackedScene = load("res://scenes/player.tscn")
	var player: Player = packed.instantiate() as Player
	player.input_enabled = false
	_tree().root.add_child(player)
	var target: StaticBody3D = _static_body(_tree().root, Vector3(0.0, 0.0, -10.0))
	check(player.grapple != null, "player exposes its grapple")
	if player.grapple != null:
		check(player.grapple.attach_to(target, target.position), "player grapple is configured")
		check_near(player.suit.battery_energy_j,
			SuitResources.BATTERY_CAPACITY_J - player.grapple.attach_energy_j, 0.001,
			"grapple spends owning player's battery")
	player.free()
	target.free()


func _rig() -> Node3D:
	var rig: Node3D = Node3D.new()
	_tree().root.add_child(rig)
	var source: RigidBody3D = _body(rig, Vector3.ZERO, 100.0)
	source.name = "Source"
	var camera: Camera3D = Camera3D.new()
	source.add_child(camera)
	var stores: SuitResources = SuitResources.new()
	rig.set_meta("stores", stores)
	var grapple: Grapple = Grapple.new()
	grapple.name = "Grapple"
	source.add_child(grapple)
	grapple.configure(source, stores, camera)
	return rig


func _body(parent: Node, at: Vector3, mass_kg: float) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = mass_kg
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.can_sleep = false
	_add_shape(body)
	body.position = at
	parent.add_child(body)
	return body


func _static_body(parent: Node, at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	_add_shape(body)
	body.position = at
	parent.add_child(body)
	return body


func _add_shape(body: PhysicsBody3D) -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 2.0)
	collision.shape = shape
	body.add_child(collision)


func _source(rig: Node3D) -> RigidBody3D:
	return rig.get_node("Source") as RigidBody3D


func _grapple(rig: Node3D) -> Grapple:
	return rig.get_node("Source/Grapple") as Grapple


func _stores(rig: Node3D) -> SuitResources:
	return rig.get_meta("stores") as SuitResources


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _physics_steps(count: int) -> void:
	for i in count:
		await _tree().physics_frame


func _check_vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s expected %s, got %s" % [message, expected, actual])
