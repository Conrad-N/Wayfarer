## Normal mouse commands complete physical turns; held freelook only moves the head.
extends TestCase


## Fast half-turn and three-quarter-turn swipes survive the old neck and speed limits.
func test_fast_swipes_complete_requested_turn_and_settle() -> void:
	var players: Array[Player] = [_spawn(Vector3.ZERO), _spawn(Vector3(10.0, 0.0, 0.0))]
	var requests: Array[float] = [PI, PI * 1.5]
	check_eq(players[0].roll_torque_nm, 50.0, "suit has the requested 50 Nm shared motor torque")
	await _steps(3)
	for index: int in players.size():
		players[index].queue_mouse_look(Vector2(-requests[index] / players[index].mouse_sensitivity, 0.0))
	var total_yaw: Array[float] = [0.0, 0.0]
	var peak_speed: Array[float] = [0.0, 0.0]
	var previous: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
	for step: int in Engine.physics_ticks_per_second * 8:
		await _steps(1)
		for index: int in players.size():
			var player: Player = players[index]
			var delta_basis: Basis = previous[index].transposed() * player.global_basis
			total_yaw[index] += atan2(delta_basis.z.x, delta_basis.z.z)
			previous[index] = player.global_basis
			peak_speed[index] = maxf(peak_speed[index], player.angular_velocity.length())
	for index: int in players.size():
		var player: Player = players[index]
		check_near(total_yaw[index], requests[index], 0.015, "full unwrapped mouse turn completes in the requested direction")
		check(peak_speed[index] > 0.8, "available torque can accelerate past old fixed turning-speed cap")
		check(player.angular_velocity.length() < 0.01, "counter-torque settles after the requested turn")
		check_eq(player.head_angles_rad, Vector2.ZERO, "normal view stays centred in the suit")
		check((player.get_node("Camera3D") as Camera3D).basis.is_equal_approx(Basis.IDENTITY), "normal view has no independent neck angle")
		check(player.suit.battery_energy_j < SuitResources.BATTERY_CAPACITY_J, "physical turning spends electrical energy")
		check_eq(player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, "mouse turning uses no propellant")
		player.free()


## Modifier-held look is free, bounded and cannot leave a body-turn request on release.
func test_freelook_release_centres_immediately_without_queued_turn() -> void:
	var player: Player = _spawn(Vector3.ZERO)
	await _steps(3)
	player.set_freelooking(true)
	player.queue_mouse_look(Vector2(-1e6, 1e6))
	await _steps(3)
	check(player.is_freelooking(), "modifier state is reported")
	check_near(player.head_angles_rad.x, Player.HEAD_YAW_LIMIT_RAD, 1e-5, "free yaw stops at anatomical limit")
	check_near(player.head_angles_rad.y, -Player.HEAD_PITCH_LIMIT_RAD, 1e-5, "free pitch stops at anatomical limit")
	check(player.global_basis.is_equal_approx(Basis.IDENTITY), "free look does not turn the suit")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "free look uses no wheel energy")
	# Include movement queued since the last physics tick: release must discard it.
	player.queue_mouse_look(Vector2(-400, 0))
	player.set_freelooking(false)
	check_eq(player.head_angles_rad, Vector2.ZERO, "modifier release immediately centres the head")
	check((player.get_node("Camera3D") as Camera3D).basis.is_equal_approx(Basis.IDENTITY), "modifier release immediately centres the camera")
	await _steps(30)
	check_near(player.angular_velocity.length(), 0.0, 1e-6, "no neck movement is replayed as a body turn")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "released free look starts no hidden motor")
	player.free()


## An empty battery cannot turn the body, even when the mouse requests a half-turn.
func test_normal_look_requires_power_and_respects_grip_authority() -> void:
	var empty: Player = _spawn(Vector3.ZERO)
	var held: Player = _spawn(Vector3(10.0, 0.0, 0.0))
	empty.suit.battery_energy_j = 0.0
	held.body_follow_enabled = false
	await _steps(3)
	for player: Player in [empty, held]:
		player.queue_mouse_look(Vector2(-PI / player.mouse_sensitivity, 0))
	await _steps(15)
	for player: Player in [empty, held]:
		check_near(player.angular_velocity.length(), 0.0, 1e-6, "unpowered or disabled steering cannot rotate the body")
		check_eq(player.head_angles_rad, Vector2.ZERO, "normal mouse never bypasses motor limits with free head aim")
	held.body_follow_enabled = true
	await _steps(6)
	check_near(held.angular_velocity.length(), 0.0, 1e-6, "disabled grip steering does not queue a surprise turn")
	held.queue_mouse_look(Vector2(-0.5 / held.mouse_sensitivity, 0))
	await _steps(12)
	check(held.angular_velocity.y > 0.01, "deliberately enabled grip steering can turn")
	empty.free()
	held.free()


## Latched mouse freely aims in both axes, without commanding feet or suit wheels.
func test_surface_mouse_aim_is_free_unrestricted_and_persistent() -> void:
	var player: Player = _spawn(Vector3.ZERO)
	player.surface_motion_active = true
	await _steps(3)
	player.queue_mouse_look(Vector2(-PI * 1.5 / player.mouse_sensitivity, -PI / player.mouse_sensitivity))
	await _steps(3)
	check_near(player.head_angles_rad.x, -PI * 0.5, 1e-5, "walking yaw keeps the full three-quarter turn and wraps naturally")
	check_near(player.head_angles_rad.y, Player.SURFACE_PITCH_LIMIT_RAD, 1e-5, "walking view looks up to eighty-five degrees")
	check_eq(player.take_surface_look(), Vector2.ZERO, "free camera aim requests no boot pivot")
	var aimed: Vector2 = player.head_angles_rad
	await _steps(15)
	check_eq(player.head_angles_rad, aimed, "latched view stays aimed when the mouse stops")
	check(player.global_basis.is_equal_approx(Basis.IDENTITY), "camera aiming does not turn the physical suit")
	check_near(player.angular_velocity.length(), 0.0, 1e-6, "latched aiming adds no angular momentum")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "latched aiming spends no electricity")
	check_eq(player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, "latched aiming spends no propellant")
	player.set_freelooking(true)
	player.set_freelooking(false)
	check_eq(player.head_angles_rad, aimed, "EVA modifier transitions leave walking aim intact")
	player.suit.battery_energy_j = 0.0
	player.suit.propellant_kg = 0.0
	player.queue_mouse_look(Vector2(-PI * 2.0 / player.mouse_sensitivity, PI * 2.0 / player.mouse_sensitivity))
	await _steps(3)
	check_near(player.head_angles_rad.x, aimed.x, 1e-5, "empty suit can look all the way around while latched")
	check_near(player.head_angles_rad.y, -Player.SURFACE_PITCH_LIMIT_RAD, 1e-5, "empty suit can freely look down while latched")
	check_eq(player.suit.battery_energy_j, 0.0, "free surface view cannot create charge")
	player.free()


## Leaving a surface centres the view immediately and restores powered EVA mouse turns.
## Leaving the walking view keeps the view where it points (Conrad, 2026-09-14), drops
## aim queued in that frame, and turns the torso to the view before normal steering resumes.
func test_surface_release_keeps_view_and_discards_stale_aim() -> void:
	var player: Player = _spawn(Vector3.ZERO)
	var camera: Camera3D = player.get_node("Camera3D") as Camera3D
	player.surface_motion_active = true
	player.queue_mouse_look(Vector2(-800.0, -200.0))
	await _steps(3)
	check(player.head_angles_rad.length() > 1.0, "walking camera begins aimed away from torso")
	var view: Basis = camera.global_basis
	player.queue_mouse_look(Vector2(-400, 100))
	player.surface_motion_active = false
	check(camera.global_basis.is_equal_approx(view), "surface release leaves the view where it was aimed")
	check_eq(player.head_angles_rad, Vector2.ZERO, "head aim hands over to a torso turn")
	var steps: int = 0
	while player._view_handoff and steps < 900:
		await _steps(1)
		steps += 1
	check(not player._view_handoff, "the torso finishes turning to the view")
	check((-player.global_basis.z).angle_to(-view.z) < 0.02, "aim queued at release is dropped: the torso faces the held view")
	check(camera.basis.is_equal_approx(Basis.IDENTITY), "camera is back on the torso")
	check(player.suit.battery_energy_j < SuitResources.BATTERY_CAPACITY_J, "the wheels pay for the turn")
	var charge: float = player.suit.battery_energy_j
	player.queue_mouse_look(Vector2(-0.5 / player.mouse_sensitivity, 0.0))
	await _steps(12)
	check(player.angular_velocity.y > 0.01, "normal mouse resumes physical EVA steering after the turn")
	check_eq(player.head_angles_rad, Vector2.ZERO, "EVA camera stays centred during powered steering")
	check(player.suit.battery_energy_j < charge, "restored EVA steering pays electrical work")
	player.free()


func _spawn(at: Vector3) -> Player:
	var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	player.input_enabled = false
	player.position = at
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player


func _steps(count: int) -> void:
	for step: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
