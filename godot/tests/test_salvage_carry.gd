## Complete salvage acceptance: grip an imported antenna, cut it, carry through the hatch.
extends TestCase


## Actual suit thrust transports a held antenna through the real ship door before release.
func test_grab_cut_carry_and_release_antenna_into_cargo() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate() as Node3D
	main.set("salvage_practice", true)
	var player: Player = main.get_node("Player") as Player
	player.input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	var ship: PlayerShip = main.get("_ship") as PlayerShip
	var wreck: SalvageWreck = main.get("_wreck") as SalvageWreck
	var grip: PhysicalGrip = main.get("_grip") as PhysicalGrip
	var hold: CargoHold = main.get("_cargo") as CargoHold
	var camera: Camera3D = player.get_node("Camera3D") as Camera3D
	# Controlled starting geometry only: antenna points along the real door and
	# the remaining wreck sits behind it. No position is assigned after catching.
	ship.global_transform = Transform3D.IDENTITY
	var antenna: ShipPart = wreck.graph.get_part("Antenna")
	var antenna_pose: Transform3D = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -10.0))
	var assembly: Transform3D = antenna_pose * antenna.transform.affine_inverse()
	var original: WreckBody = wreck.body_for_part("Antenna")
	original.global_transform = assembly * original.assembly_from_body
	original.linear_velocity = Vector3.ZERO
	original.angular_velocity = Vector3.ZERO
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -8.5))
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	check(ship.api.set_cargo_door(true), "open real cargo door before transport")
	await _frames(4)
	check(grip.grab_body(original, wreck.part_pose("Antenna") * Vector3(0.0, 0.0, -0.8), "Antenna"), "hold antenna while still attached to wreck")
	var marker: Area3D
	for child: Node in original.get_children():
		if child is Area3D and str(child.get_meta("edge_id", "")) == "Joint_Antenna" and str(child.get_meta("part_id", "")) == "Antenna":
			marker = child as Area3D
	check(marker != null, "imported antenna has an accessible real cut marker")
	if marker == null:
		main.free()
		return
	var direction: Vector3 = player.global_basis.transposed() * (marker.global_position - camera.global_position).normalized()
	var head_aim: Vector2 = Vector2(atan2(-direction.x, -direction.z), asin(direction.y))
	player.set_freelooking(true)
	player.queue_mouse_look(-head_aim / player.mouse_sensitivity)
	player.salvage_tools.select_tool(SalvageTools.Tool.CUTTER)
	var energy_before: float = player.suit.battery_energy_j
	player.salvage_tools.set_triggers(true, false)
	for tick: int in range(180):
		await _frames(1)
		if wreck.body_for_part("Antenna").part_ids.size() == 1:
			break
	player.salvage_tools.cancel_input()
	var body: WreckBody = wreck.body_for_part("Antenna")
	check_eq(body.part_ids, PackedStringArray(["Antenna"]), "real cutter severs the antenna mount")
	check(player.suit.battery_energy_j < energy_before, "cut consumes suit battery")
	check(grip.is_attached() and grip.target_body() == body, "hand remains on detached imported antenna")
	if body.part_ids.size() != 1 or not grip.is_attached():
		main.free()
		return
	var initial_position: Vector3 = body.global_position
	var fuel_before: float = player.suit.propellant_kg
	player.set_motion_input(Vector3.BACK, 0.0)
	for tick: int in range(60):
		await _frames(1)
		if player.linear_velocity.z >= 0.4:
			break
	player.set_motion_input(Vector3.ZERO, 0.0)
	for tick: int in range(900):
		await _frames(1)
		if PlayerShip.CARGO_BOUNDS.encloses(hold.bounds_in_bay(body)):
			break
	check(PlayerShip.CARGO_BOUNDS.encloses(hold.bounds_in_bay(body)), "suit and held antenna physically cross the 2.2m cargo doorway")
	check(body.global_position.z - initial_position.z > 4.0, "antenna travels over four metres under suit power")
	check(grip.is_attached(), "grip survives physical doorway passage")
	player.set_braking(true)
	await _frames(100)
	player.set_braking(false)
	check(player.suit.propellant_kg < fuel_before, "carry and braking consume suit propellant")
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "clamps wait while player is holding cargo")
	check(ship.api.last_message.contains("Release your grip"), "cargo explains that hands must release before clamping")
	var suit_position: Vector3 = player.global_position
	grip.release()
	await _frames(4)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 1, "released antenna secures inside cargo")
	check_near(ship.api.get_telemetry().cargo_mass_kg, 18.0, 0.001, "actual antenna adds eighteen kilograms to manifest")
	check_eq(wreck.body_for_part("Antenna"), null, "secured antenna leaves loose wreck bodies")
	check(player.global_position.distance_to(suit_position) < 0.02, "securing cargo does not teleport carrier")
	check(not player.freeze, "player remains free after releasing cargo")
	main.free()


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for tick: int in range(count):
		await tree.physics_frame
		await tree.process_frame
