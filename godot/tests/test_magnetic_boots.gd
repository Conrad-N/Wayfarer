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
	check(not boots.is_armed(), "overload disarms automatic catch to avoid repeated reattachment")
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


## Free head look leaves feet still and sets the camera-relative walking direction.
func test_modifier_freelook_does_not_steer_boots() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	await _frames(3)
	check(boots.try_latch(), "feet engage for freelook")
	var energy: float = player.suit.battery_energy_j
	player.set_freelooking(true)
	player.queue_mouse_look(Vector2(-0.8 / player.mouse_sensitivity, -0.3 / player.mouse_sensitivity))
	await _frames(30)
	check_near(player.head_angles_rad.x, 0.8, 0.001, "modifier turns head on deck")
	check(player.angular_velocity.length() < 0.001, "looking aside leaves feet still")
	check_near(player.suit.battery_energy_j, energy, 0.001, "head look uses no boot motor energy")
	boots.set_walk_input(Vector2(0, 1))
	await _frames(40)
	check(player.position.x < -0.1 and player.position.z < -0.2, "walking follows free camera aim")
	player.set_freelooking(false)
	check_near(player.head_angles_rad.x, 0.8, 0.001, "modifier release keeps walking view")
	f.root.free()


## Latched mouse look is free, including pitch and a full half turn.
func test_normal_mouse_looks_freely_without_turning_suit() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	await _frames(3)
	check(boots.try_latch(), "feet engage for free look")
	var energy: float = player.suit.battery_energy_j
	player.queue_mouse_look(Vector2(-PI / player.mouse_sensitivity, -0.4 / player.mouse_sensitivity))
	await _frames(30)
	check(boots.is_attached(), "free half turn retains feet")
	check_near(absf(player.head_angles_rad.x), PI, 0.001, "view can turn behind torso")
	check_near(player.head_angles_rad.y, 0.4, 0.001, "view pitches freely on deck")
	check_eq(player.suit.battery_energy_j, energy, "view spends no motor energy")
	check_eq(player.suit.propellant_kg, 8.0, "view uses no jets")
	check(player.angular_velocity.length() < 0.001, "view does not turn physical suit")
	check(player.attitude.momentum_body.length() < 0.001, "view leaves suit wheels idle")
	f.root.free()


## Arming in open space waits without drawing power, then catches a real deck landing.
func test_armed_boots_latch_after_actual_thruster_descent() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var deck: RigidBody3D = f.deck
	var boots: MagneticBoots = f.boots
	player.position.y = 1.65
	var contact: Dictionary = _watch_deck_contact(player, deck)
	await _frames(3)
	boots.toggle()
	check(boots.is_armed(), "B arms boots before the soles reach the deck")
	await _frames(12)
	check(not boots.is_attached(), "armed boots do not attract across open space")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "waiting for contact consumes no engagement pulses")
	player.set_motion_input(Vector3.DOWN, 0.0)
	await _frames(100)
	check(bool(contact.hit), "descent reaches an actual capsule-to-deck collision")
	check(boots.is_attached(), "armed soles latch after landing without a second B press")
	check(player.surface_motion_active, "landing switches to surface movement")
	check_near(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J - MagneticBoots.ENGAGE_ENERGY_J, 0.001, "one successful landing pays exactly one engagement pulse")
	check((player.linear_velocity - deck.linear_velocity).length() < 0.05, "latched landing settles with its moving deck")
	var height: float = deck.to_local(player.global_position).y - 0.1
	check(height >= 0.88 and height <= 0.93, "soles retain the actual collision height")
	f.root.free()


## Pressing B again while waiting cancels future catches, including a later collision.
func test_cancel_armed_boots_before_descending() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var deck: RigidBody3D = f.deck
	var boots: MagneticBoots = f.boots
	player.position.y = 1.65
	var contact: Dictionary = _watch_deck_contact(player, deck)
	await _frames(3)
	boots.toggle()
	check(boots.is_armed(), "first press arms waiting soles")
	boots.toggle()
	check(not boots.is_armed(), "second press cancels waiting soles")
	player.set_motion_input(Vector3.DOWN, 0.0)
	await _frames(100)
	player.set_motion_input(Vector3.ZERO, 0.0)
	check(bool(contact.hit), "cancelled suit still physically reaches the deck")
	check(not boots.is_attached(), "cancelled boots cannot latch on later contact")
	check(not player.surface_motion_active, "cancelled landing remains in EVA mode")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "cancelled approach spends no engagement energy")
	f.root.free()


## Automatic retry retains the steel requirement when the suit actually hits a deck.
func test_armed_boots_reject_nonmagnetic_landing() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var deck: RigidBody3D = f.deck
	var boots: MagneticBoots = f.boots
	deck.remove_from_group("magnetic_surface")
	player.position.y = 1.65
	var contact: Dictionary = _watch_deck_contact(player, deck)
	await _frames(3)
	boots.toggle()
	player.set_motion_input(Vector3.DOWN, 0.0)
	await _frames(100)
	player.set_motion_input(Vector3.ZERO, 0.0)
	check(bool(contact.hit), "nonmagnetic test includes real foot collision")
	check(not boots.is_attached(), "armed soles reject a nonmagnetic surface on contact")
	check(boots.is_armed(), "material rejection keeps the deliberate waiting state")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "repeated unsuitable contact costs no engagement pulses")
	f.root.free()


## Taking a seat cancels a pending sole catch; B cannot arm boots through restraints.
func test_armed_boots_cancel_when_seated_and_ignore_seated_toggle() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	player.position.y = 1.65
	await _frames(3)
	boots.toggle()
	check(boots.is_armed(), "soles wait before taking a seat")
	player.set_meta("seated", true)
	await _frames(3)
	check(not boots.is_armed(), "seated restraint cancels pending automatic attachment")
	check(not boots.is_attached(), "taking a seat cannot create sole attachment")
	boots.toggle()
	check(not boots.is_armed(), "B cannot arm soles while seated")
	player.set_meta("seated", false)
	player.position.y = 0.92
	await _frames(6)
	check(not boots.is_attached(), "leaving the seat does not restore a cancelled catch")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "seated cancellation uses no engagement power")
	f.root.free()


## An armed empty battery retries for free and pays once when power becomes available.
func test_armed_contact_waits_for_power_and_charges_once() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	player.suit.battery_energy_j = 0.0
	await _frames(3)
	boots.toggle()
	await _frames(12)
	check(boots.is_armed(), "unpowered soles retain the deliberate waiting command")
	check(not boots.is_attached(), "empty battery cannot engage at valid sole contact")
	check_eq(player.suit.battery_energy_j, 0.0, "unpowered retries consume and create no charge")
	player.suit.battery_energy_j = MagneticBoots.ENGAGE_ENERGY_J - 1.0
	await _frames(12)
	check(not boots.is_attached(), "partial engagement energy remains insufficient")
	check_eq(player.suit.battery_energy_j, MagneticBoots.ENGAGE_ENERGY_J - 1.0, "insufficient retries cannot consume partial pulses")
	player.suit.battery_energy_j = MagneticBoots.ENGAGE_ENERGY_J + 25.0
	await _frames(12)
	check(boots.is_attached(), "restored power engages waiting soles without another B press")
	check(not boots.is_armed(), "successful catch ends the pending retry state")
	check_eq(player.suit.battery_energy_j, 25.0, "power restoration pays exactly one engagement pulse")
	await _frames(12)
	check_eq(player.suit.battery_energy_j, 25.0, "passive contact does not repeat the engagement charge")
	f.root.free()


func _watch_deck_contact(player: Player, deck: RigidBody3D) -> Dictionary:
	var contact: Dictionary = {"hit": false}
	player.contact_monitor = true
	player.max_contacts_reported = 8
	player.body_entered.connect(func(body: Node) -> void:
		if body == deck:
			contact.hit = true
	)
	return contact


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
