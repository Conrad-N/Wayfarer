## Magnetic contact is local, resource limited, and exchanges momentum with its deck.
extends TestCase


## Latching needs nearby aligned feet on magnetic material and an affordable pulse.
func test_latch_reach_material_speed_and_power() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	await _frames(3)
	f.deck.remove_from_group("magnetic_surface")
	check(not boots.try_latch(), "nonmagnetic surfaces reject soles")
	f.deck.add_to_group("magnetic_surface")
	player.position.y = 2.0
	await _frames(2)
	check(not boots.try_latch(), "boots do not attract across open space")
	player.position.y = 0.92
	player.linear_velocity = Vector3.RIGHT
	await _frames(2)
	check(not boots.try_latch(), "fast catch rejected")
	player.linear_velocity = Vector3.ZERO
	player.suit.battery_energy_j = 49.0
	await _frames(2)
	check(not boots.try_latch(), "cannot buy engagement with partial power")
	check_eq(player.suit.battery_energy_j, 49.0, "refused latch costs nothing")
	player.suit.battery_energy_j = 100.0
	check(boots.try_latch(), "nearby aligned soles latch")
	check_eq(player.suit.battery_energy_j, 50.0, "engage pulse costs fifty joules")
	check(player.surface_motion_active, "boots replace free suit thrust")
	boots.release()
	check(not player.surface_motion_active, "release restores EVA controls")
	f.root.free()


## Passive holding costs no idle energy; steps have real reaction and no jet fuel.
func test_walking_reaction_and_passive_hold() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var deck: RigidBody3D = f.deck
	var boots: MagneticBoots = f.boots
	await _frames(3)
	check(boots.try_latch(), "feet engage")
	var energy: float = player.suit.battery_energy_j
	await _frames(60)
	check(boots.is_attached(), "passive contact stable for a second")
	check_eq(player.suit.battery_energy_j, energy, "latched idle has no continuous draw")
	boots.set_walk_input(Vector2(0, 1))
	await _frames(60)
	check(boots.is_attached(), "walking maintains contact")
	check(player.position.z < -0.5, "suit walks forward along deck")
	check(deck.linear_velocity.z > 0.01, "deck gets opposing momentum")
	check((player.linear_velocity * player.mass + deck.linear_velocity * deck.mass).length() < 0.05, "walking conserves total linear momentum")
	check(_momentum(player).distance_to(-_momentum(deck)) < 1.0, "walking conserves angular momentum with shared contact reactions")
	check(player.suit.battery_energy_j < energy - 1000.0, "powered stepping spends battery")
	check_eq(player.suit.propellant_kg, 8.0, "walking does not spend jet fuel")
	boots.set_walk_input(Vector2.ZERO)
	await _frames(90)
	check(boots.is_attached(), "stopping keeps latch")
	check((player.linear_velocity - deck.linear_velocity).length() < 0.03, "released walking settles relative drift")
	energy = player.suit.battery_energy_j
	player.suit.battery_energy_j = 0.0
	boots.set_walk_input(Vector2(1, 0))
	var position: Vector3 = deck.to_local(player.global_position)
	await _frames(30)
	check(boots.is_attached(), "empty battery retains passive latch")
	check(deck.to_local(player.global_position).distance_to(position) < 0.03, "empty battery prevents powered steps")
	var velocity: Vector3 = player.linear_velocity
	boots.release()
	check(player.linear_velocity.distance_to(velocity) < 0.00001, "mechanical release preserves motion")
	check_eq(player.suit.battery_energy_j, 0.0, "empty battery can release")
	f.root.free()


## A violent acceleration breaks finite adhesion; neither motion nor resource is reset.
func test_overload_and_focus_stop() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	await _frames(3)
	check(boots.try_latch(), "feet engage for load test")
	(f.deck as RigidBody3D).linear_velocity = Vector3.UP * 3.0
	await _frames(2)
	check(not boots.is_attached(), "overload releases instead of unlimited magnetic force")
	check(not player.surface_motion_active, "broken contact restores suit movement")
	check_eq(player.suit.propellant_kg, 8.0, "overload does not automatically fire suit jets")
	f.root.free()


## A passive latch follows a spinning deck without secretly walking against its rotation.
func test_spinning_deck_passive_hold_spends_no_power() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var deck: RigidBody3D = f.deck
	var boots: MagneticBoots = f.boots
	await _frames(3)
	deck.angular_velocity = Vector3.UP * 0.2
	player.angular_velocity = deck.angular_velocity
	check(boots.try_latch(), "co-rotating feet latch safely")
	var energy: float = player.suit.battery_energy_j
	await _frames(180)
	check(boots.is_attached(), "soles remain latched through rotating deck motion")
	check_near(player.suit.battery_energy_j, energy, 0.01, "passive deck rotation needs no motor energy")
	check(player.angular_velocity.distance_to(deck.angular_velocity) < 0.002, "player rotates with deck instead of counter-turning")
	check(absf(player.head_angles_rad.x) < 0.01, "head follows carrier rotation naturally")
	f.root.free()


func _fixture() -> Dictionary:
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


func _momentum(body: RigidBody3D) -> Vector3:
	return body.get_inverse_inertia_tensor().inverse() * body.angular_velocity + body.to_global(body.center_of_mass).cross(body.linear_velocity * body.mass)


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame
