## Boot button edges distinguish taps, deliberate held approaches, and emergency release.
extends TestCase


## A short tap arms only; continuing an unlatched press enables paid approach after the delay.
func test_tap_and_hold_have_distinct_effects() -> void:
	var f: Dictionary = _fixture()
	await _frames(3)
	f.contacts.set_boot_input(true)
	f.contacts._advance_boot_hold(0.1)
	await _frames(2)
	check(f.boots.is_armed(), "press arms immediately")
	check(not f.boots.is_approaching(), "short tap does not drive suit")
	check_eq(f.player.suit.propellant_kg, 8.0, "short tap burns no fuel")
	f.contacts._advance_boot_hold(0.26)
	await _frames(3)
	check(f.boots.is_approaching(), "sustained press starts approach after hold threshold")
	check(f.player.suit.propellant_kg < 8.0, "held approach uses real thrusters")
	f.contacts.set_boot_input(false)
	check(not f.boots.is_approaching(), "button release cancels approach immediately")
	check(f.boots.is_armed(), "button release leaves contact detection armed")
	f.root.free()


## An already-armed hold can approach, but a hold that releases a latch cannot recatch it.
func test_armed_hold_rearms_but_latched_hold_only_releases() -> void:
	var f: Dictionary = _fixture()
	await _frames(3)
	f.boots.toggle()
	f.contacts.set_boot_input(true)
	f.contacts._advance_boot_hold(0.1)
	check(not f.boots.is_armed(), "second short press cancels armed mode")
	f.contacts._advance_boot_hold(0.26)
	await _frames(2)
	check(f.boots.is_approaching(), "continuing that press deliberately rearms and approaches")
	f.contacts.set_boot_input(false)
	f.boots.release()
	f.player.position.y = 0.92
	f.player.linear_velocity = Vector3.ZERO
	await _frames(3)
	check(f.boots.try_latch(), "fixture has actual sole contact")
	f.contacts.set_boot_input(true)
	f.contacts._advance_boot_hold(1.0)
	await _frames(3)
	check(not f.boots.is_attached(), "press releases the latch")
	check(not f.boots.is_armed() and not f.boots.is_approaching(), "continued release press cannot immediately reattach")
	f.root.free()


## Brief press/release events survive one physics tick; input ownership cancels paid motion.
func test_fast_tap_and_input_loss() -> void:
	var f: Dictionary = _fixture()
	await _frames(3)
	f.contacts.set_boot_input(true)
	f.contacts.set_boot_input(false)
	f.contacts._advance_boot_hold(1.0)
	check(f.boots.is_armed(), "tap between physics ticks still arms")
	check(not f.boots.is_approaching(), "released quick tap never starts approach")
	f.contacts.set_boot_input(true)
	f.contacts._advance_boot_hold(0.4)
	await _frames(3)
	check(f.boots.is_approaching(), "held command active before focus loss")
	f.contacts._physics_process(1.0 / 60.0)
	check(not f.boots.is_approaching(), "disabled player input cancels paid approach")
	check(f.boots.is_armed(), "input loss preserves passive armed state")
	f.contacts._advance_boot_hold(2.0)
	await _frames(2)
	check(not f.boots.is_approaching(), "input loss cannot silently restart held command")
	f.root.free()


func _fixture() -> Dictionary:
	var holder: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var deck: RigidBody3D = DebrisField.create_box(Vector3(6, 0.2, 8), 1000.0, Color.WHITE)
	deck.freeze = true
	deck.position.y = -0.1
	deck.add_to_group("magnetic_surface")
	holder.add_child(deck)
	var player: Player = preload("res://scenes/player.tscn").instantiate() as Player
	player.input_enabled = false
	player.position.y = 1.5
	holder.add_child(player)
	var boots: MagneticBoots = MagneticBoots.new()
	player.add_child(boots)
	boots.configure(player)
	var grip: PhysicalGrip = PhysicalGrip.new()
	grip.name = "PhysicalGrip"
	player.add_child(grip)
	grip.configure(player, player.get_node("Camera3D") as Camera3D)
	var contacts: SuitContacts = SuitContacts.new()
	player.add_child(contacts)
	contacts.configure(player, grip, boots)
	contacts.set_physics_process(false)
	return {"root": holder, "player": player, "boots": boots, "contacts": contacts}


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in count:
		await tree.physics_frame
		await tree.process_frame
