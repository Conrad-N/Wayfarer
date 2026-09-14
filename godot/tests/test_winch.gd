## The winch cable pulls any two anchored bodies together with stable, momentum-
## honest physics, and the suit kit/placement rules gate where it can be used.
extends TestCase


## Two free equal bodies close toward each other at the reel rate, the cable
## reels down to its minimum length, and total momentum never changes.
func test_two_free_bodies_close_and_conserve_momentum() -> void:
	var fixture: Node3D = _fixture()
	var a: RigidBody3D = _body(fixture, Vector3(-2.15, 0.0, 0.0), 50.0)
	var b: RigidBody3D = _body(fixture, Vector3(2.15, 0.0, 0.0), 50.0)
	var link: WinchLink = _link_at(fixture, a, a.global_position, b, b.global_position)
	await _frames(3)
	var before: Vector3 = a.mass * a.linear_velocity + b.mass * b.linear_velocity
	var start_distance: float = a.global_position.distance_to(b.global_position)
	var previous_distance: float = start_distance
	var max_closing_speed: float = 0.0
	for step: int in range(600):
		await _frames(1)
		var distance: float = a.global_position.distance_to(b.global_position)
		max_closing_speed = maxf(max_closing_speed, (previous_distance - distance) * Engine.physics_ticks_per_second)
		previous_distance = distance
	var closed: float = start_distance - a.global_position.distance_to(b.global_position)
	check(closed > 0.75 * WinchLink.REEL_SPEED_MPS * 10.0, "bodies follow the reel rate, closed %.2f m in 10 s" % closed)
	check(max_closing_speed <= WinchLink.REEL_SPEED_MPS * 1.25, "closing speed %.3f m/s stays near the 0.2 m/s reel rate" % max_closing_speed)
	var after: Vector3 = a.mass * a.linear_velocity + b.mass * b.linear_velocity
	_vector(after, before, 0.1, "pulling two free bodies together conserves total linear momentum")
	# A slack cable cannot brake, so the bodies may coast past; the reel itself stops at its minimum.
	for step: int in range(1200):
		if link.cable_length_m <= WinchLink.MIN_LENGTH_M:
			break
		await _frames(1)
	check_near(link.cable_length_m, WinchLink.MIN_LENGTH_M, 0.001, "cable reels in to its minimum length")
	fixture.free()


## An anchor off a body's centre of mass turns pulling into real torque.
func test_off_centre_anchor_spins_the_body() -> void:
	var fixture: Node3D = _fixture()
	var free_body: RigidBody3D = _body(fixture, Vector3(-2.0, 0.0, 0.0), 20.0)
	var anchor: StaticBody3D = _static(fixture, Vector3(2.0, 0.0, 0.0))
	_link_at(fixture, free_body, free_body.global_position + Vector3(0.0, 0.4, 0.0), anchor, anchor.global_position)
	await _frames(90)
	check(free_body.angular_velocity.length() > 0.01, "an off-centre pull spins the free body")
	fixture.free()


## A 1 kg scrap winched to a 5,000 kg hull stays bounded; the huge body barely moves.
func test_extreme_mass_ratio_stays_stable() -> void:
	var fixture: Node3D = _fixture()
	var light: RigidBody3D = _body(fixture, Vector3(-3.0, 0.0, 0.0), 1.0)
	var heavy: RigidBody3D = _body(fixture, Vector3(3.0, 0.0, 0.0), 5000.0)
	heavy.inertia = Vector3.ONE * 5000.0 * 0.5
	_link_at(fixture, light, light.global_position, heavy, heavy.global_position)
	var max_speed: float = 0.0
	for step: int in range(180):
		await _frames(1)
		max_speed = maxf(max_speed, maxf(light.linear_velocity.length(), heavy.linear_velocity.length()))
	check(is_finite(max_speed) and max_speed < 5.0, "an extreme mass ratio stays bounded, peak speed %.3f m/s" % max_speed)
	check(heavy.linear_velocity.length() < 0.05, "the 5,000 kg body barely moves")
	fixture.free()


## A StaticBody3D or a frozen RigidBody3D never moves; only the free end is pulled.
func test_static_and_frozen_ends_only_move_the_free_body() -> void:
	var fixture: Node3D = _fixture()
	var free_a: RigidBody3D = _body(fixture, Vector3(-1.0, 0.0, 0.0), 10.0)
	var static_anchor: StaticBody3D = _static(fixture, Vector3(1.0, 0.0, 0.0))
	_link_at(fixture, free_a, free_a.global_position, static_anchor, static_anchor.global_position)
	var free_b: RigidBody3D = _body(fixture, Vector3(-1.0, 3.0, 0.0), 10.0)
	var frozen_anchor: RigidBody3D = _body(fixture, Vector3(1.0, 3.0, 0.0), 10.0)
	frozen_anchor.freeze = true
	_link_at(fixture, free_b, free_b.global_position, frozen_anchor, frozen_anchor.global_position)
	var static_start: Vector3 = static_anchor.global_position
	var frozen_start: Vector3 = frozen_anchor.global_position
	await _frames(90)
	check(free_a.global_position.x > -1.0 + 0.05, "the free body is pulled toward the static anchor")
	check_eq(static_anchor.global_position, static_start, "a static anchor never moves")
	check(free_b.global_position.x > -1.0 + 0.05, "the free body is pulled toward the frozen anchor")
	check_eq(frozen_anchor.global_position, frozen_start, "a frozen body never moves")
	fixture.free()


## Reeling under load spends the device's own battery; an empty battery stops
## shortening the cable but the tension it already holds does not release.
func test_battery_drains_and_empty_battery_still_holds_tension() -> void:
	var fixture: Node3D = _fixture()
	var a: RigidBody3D = _body(fixture, Vector3(-0.6, 0.0, 0.0), 50.0)
	var b: RigidBody3D = _body(fixture, Vector3(0.6, 0.0, 0.0), 50.0)
	var link: WinchLink = _link_at(fixture, a, a.global_position, b, b.global_position)
	await _frames(30)
	check(link.device_battery_j < WinchLink.DEVICE_BATTERY_J, "reeling under load drains the device battery")
	check(link.cable_length_m < 1.2, "the cable has reeled in while powered")
	link.device_battery_j = 0.0
	var length_before: float = link.cable_length_m
	await _frames(15)
	check_near(link.cable_length_m, length_before, 0.001, "an empty battery stops the reel from shortening further")
	a.apply_central_impulse(Vector3.LEFT * 20.0)
	await _frames(30)
	check(a.global_position.distance_to(b.global_position) < link.cable_length_m + 1.0, "tension still resists separation with an empty battery")
	fixture.free()


## A winch anchored on a wreck part keeps its exact surface point when that
## part is cut free onto a brand new body, and detaches if a body is freed outright.
func test_winch_survives_a_cut_and_detaches_if_a_body_is_freed() -> void:
	var fixture: Node3D = _fixture()
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
	wreck.spawn(graph, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	var anchor: StaticBody3D = _static(fixture, Vector3(3.0, 0.0, 0.0))
	await _frames(3)
	var antenna_body: WreckBody = wreck.body_for_part("antenna")
	var world_point: Vector3 = wreck.part_pose("antenna") * (Vector3.LEFT * 0.25)
	var part_anchor: Vector3 = wreck.part_pose("antenna").affine_inverse() * world_point
	var link: WinchLink = WinchLink.new()
	fixture.add_child(link)
	link.attach_a(antenna_body, antenna_body.to_local(world_point), Vector3.UP, "antenna", wreck, part_anchor, Vector3.UP)
	link.attach_b(anchor, anchor.to_local(anchor.global_position), Vector3.UP, "", null, Vector3.ZERO, Vector3.UP)
	link.finish_setup()
	await _frames(6)
	var old_id: int = antenna_body.get_instance_id()
	check(wreck.cut("mount", 10.0, "antenna"), "cut the antenna free while the winch holds it")
	await wreck.structure_changed
	check(is_instance_valid(link) and not link.is_queued_for_deletion(), "the winch link survives the cut")
	var new_body: WreckBody = wreck.body_for_part("antenna")
	check(is_instance_valid(new_body) and new_body.get_instance_id() != old_id, "the antenna moved to a fresh body")
	check_near(link.anchor_a_position().distance_to(world_point), 0.0, 0.05, "the anchor stays on the same physical point across the cut")
	# A body vanishing outright (not through a tracked wreck cut) detaches cleanly.
	var loose_a: RigidBody3D = _body(fixture, Vector3(-1.0, 5.0, 0.0), 10.0)
	var loose_b: RigidBody3D = _body(fixture, Vector3(1.0, 5.0, 0.0), 10.0)
	var loose_link: WinchLink = _link_at(fixture, loose_a, loose_a.global_position, loose_b, loose_b.global_position)
	var reasons: Array[String] = []
	loose_link.detached.connect(func(reason: String) -> void: reasons.append(reason))
	await _frames(3)
	loose_b.queue_free()
	await _frames(3)
	check_eq(reasons, ["WINCH DETACHED"], "freeing either body detaches the link cleanly")
	check(not is_instance_valid(loose_link), "the link frees itself once detached")
	fixture.free()


## Placement is refused out of reach, on the same body twice, or past 30 m of cable.
func test_placement_requires_reach_a_different_object_and_cable_within_30_m() -> void:
	var fixture: Dictionary = _tool_fixture()
	var holder: Node3D = fixture.root
	var player: Player = fixture.player
	var winch: SuitWinch = fixture.winch
	var far_wall: StaticBody3D = _static(holder, Vector3(0.0, 0.55, -5.0))
	await _frames(3)
	winch.place()
	check_eq(winch.kits_available, 4, "a surface beyond 2 m reach cannot start placement")
	far_wall.free()
	_static(holder, Vector3(0.0, 0.55, -1.0))
	await _frames(3)
	winch.place()
	check_eq(winch.kits_available, 3, "placing device A spends one kit")
	winch.place()
	check_eq(winch.status, "PICK A DIFFERENT OBJECT", "aiming the second click at the same body is refused")
	check_eq(winch.kits_available, 3, "a refused second click spends no extra kit")
	_static(holder, Vector3(40.0, 0.55, -1.0))
	player.global_position = Vector3(40.0, 0.0, 0.0)
	await _frames(3)
	winch.place()
	check_eq(winch.status, "CABLE TOO SHORT: 30 m", "a second device more than 30 m from the first is refused")
	check_eq(winch.kits_available, 3, "a refused cable-length click spends no extra kit")
	_static(holder, Vector3(25.0, 0.55, -1.0))
	player.global_position = Vector3(25.0, 0.0, 0.0)
	await _frames(3)
	winch.place()
	check_eq(winch.status, "WINCH LINKED", "a valid second device within reach and cable completes the link")
	check_eq(winch.kits_available, 3, "a completed link keeps the one kit it spent")
	fixture.root.free()


## The suit only carries four kits; a fifth device cannot be placed until one frees up.
func test_kit_limit_caps_concurrent_winches() -> void:
	var fixture: Dictionary = _tool_fixture()
	var holder: Node3D = fixture.root
	var player: Player = fixture.player
	var winch: SuitWinch = fixture.winch
	for index: int in range(4):
		var base_x: float = float(index) * 10.0
		_static(holder, Vector3(base_x, 0.55, -1.0))
		_static(holder, Vector3(base_x + 1.0, 0.55, -1.0))
		player.global_position = Vector3(base_x, 0.0, 0.0)
		await _frames(3)
		winch.place()
		player.global_position = Vector3(base_x + 1.0, 0.0, 0.0)
		await _frames(3)
		winch.place()
		check_eq(winch.status, "WINCH LINKED", "link %d completes" % (index + 1))
	check_eq(winch.kits_available, 0, "all four kits are committed to live winches")
	_static(holder, Vector3(100.0, 0.55, -1.0))
	player.global_position = Vector3(100.0, 0.0, 0.0)
	await _frames(3)
	winch.place()
	check_eq(winch.status, "WINCH | No kits remaining", "a fifth device cannot be placed without a kit")
	fixture.root.free()


## Right click either takes a pending device back or removes the aimed winch, in both
## cases returning its kit.
func test_right_click_picks_up_pending_or_removes_a_link() -> void:
	var fixture: Dictionary = _tool_fixture()
	var holder: Node3D = fixture.root
	var player: Player = fixture.player
	var winch: SuitWinch = fixture.winch
	_static(holder, Vector3(0.0, 0.55, -1.0))
	await _frames(3)
	winch.place()
	check_eq(winch.kits_available, 3, "device A reserves a kit")
	winch.remove()
	check_eq(winch.kits_available, 4, "picking the pending device back up returns its kit")
	_static(holder, Vector3(0.0, 0.55, -1.0))
	_static(holder, Vector3(1.0, 0.55, -1.0))
	await _frames(3)
	winch.place()
	player.global_position = Vector3(1.0, 0.0, 0.0)
	await _frames(3)
	winch.place()
	check_eq(winch.status, "WINCH LINKED", "a valid pair completes a link")
	check_eq(winch.kits_available, 3, "the completed link still holds its kit")
	winch.remove()
	check_eq(winch.kits_available, 4, "removing the winch aimed at returns its kit")
	fixture.root.free()


func _fixture() -> Node3D:
	var node: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	return node


func _tool_fixture() -> Dictionary:
	var holder: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var packed: PackedScene = load("res://scenes/player.tscn")
	var player: Player = packed.instantiate() as Player
	player.input_enabled = false
	player.freeze = true
	player.collision_layer = 0
	player.collision_mask = 0
	holder.add_child(player)
	var winch: SuitWinch = SuitWinch.new()
	winch.configure(player, player.get_node("Camera3D") as Camera3D, holder)
	return {"root": holder, "player": player, "winch": winch}


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
	shape.radius = 0.05
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _static(parent: Node3D, at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = at
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _link_at(parent: Node3D, body_a: PhysicsBody3D, point_a: Vector3, body_b: PhysicsBody3D, point_b: Vector3) -> WinchLink:
	var link: WinchLink = WinchLink.new()
	parent.add_child(link)
	link.attach_a(body_a, body_a.to_local(point_a), Vector3.UP, "", null, Vector3.ZERO, Vector3.UP)
	link.attach_b(body_b, body_b.to_local(point_b), Vector3.UP, "", null, Vector3.ZERO, Vector3.UP)
	link.finish_setup()
	return link


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame


func _vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s expected %s got %s" % [message, expected, actual])
