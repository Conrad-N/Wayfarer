## Powered soles step over actual ship doorway thresholds while retaining physical contact.
extends TestCase


## The 30 cm hab sill is traversable in both directions without tipping the suit.
func test_actual_ship_threshold_both_directions() -> void:
	for direction: float in [-1.0, 1.0]:
		var f: Dictionary = _fixture()
		var player: Player = f.player
		var boots: MagneticBoots = f.boots
		player.position = Vector3(0, -0.48, -2.0 - direction * 1.0)
		await _frames(3)
		check(boots.try_latch(), "ship floor latches before threshold")
		boots.set_walk_input(Vector2(0, -direction))
		var stayed: bool = true
		var upright: float = 1.0
		var height: float = -1.0
		for tick: int in range(240):
			await _frames(1)
			stayed = stayed and boots.is_attached()
			upright = minf(upright, player.global_basis.y.dot(Vector3.UP))
			height = maxf(height, player.position.y)
		check(stayed, "sill traversal keeps boots attached in direction " + str(direction))
		check((player.position.z + 2.0) * direction > 0.7, "walks fully across actual sill " + str(player.position))
		check(height > -0.25, "physical capsule rises over threshold")
		check(upright > 0.98, "sill does not tip player head over heels: " + str(upright))
		check_eq(player.suit.propellant_kg, 8.0, "step motor needs no fuel")
		f.root.free()


## An obstacle taller than the step limit blocks travel without tearing off the boots.
func test_tall_obstacle_blocks_without_flipping() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	var obstacle: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.5, 0.55, 0.25)
	obstacle.shape = shape
	obstacle.position = Vector3(0, -1.125, -4.0)
	obstacle.set_meta("magnetic_surface", true)
	f.ship.add_child(obstacle)
	player.position = Vector3(0, -0.48, -3.0)
	await _frames(3)
	check(boots.try_latch(), "tall obstruction approach latches")
	boots.set_walk_input(Vector2(0, 1))
	await _frames(240)
	check(boots.is_attached(), "blocked walking retains latch")
	check(player.position.z > -3.6, "55 cm obstacle blocks forward travel")
	check(player.global_basis.y.dot(Vector3.UP) > 0.98, "blocked walking stays upright")
	check(player.position.y < -0.4, "tall obstacle cannot be climbed")
	f.root.free()


## A low ceiling prevents a step instead of forcing the capsule through solid hull.
func test_step_requires_capsule_headroom() -> void:
	var f: Dictionary = _fixture()
	var player: Player = f.player
	var boots: MagneticBoots = f.boots
	var ceiling: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.5, 0.3, 1.4)
	ceiling.shape = shape
	ceiling.position = Vector3(0, 0.70, -2.6)
	f.ship.add_child(ceiling)
	player.position = Vector3(0, -0.48, -3.0)
	await _frames(3)
	check(boots.try_latch(), "headroom approach latches")
	boots.set_walk_input(Vector2(0, -1))
	await _frames(180)
	check(boots.is_attached(), "low ceiling keeps soles safely attached")
	check(player.position.z < -2.4, "no climbing into low ceiling")
	check(player.position.y < -0.35, "capsule remains below overhead obstruction")
	f.root.free()


func _fixture() -> Dictionary:
	var holder: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var ship: PlayerShip = PlayerShip.new()
	ship.freeze = true
	holder.add_child(ship)
	var player: Player = preload("res://scenes/player.tscn").instantiate() as Player
	player.input_enabled = false
	holder.add_child(player)
	var boots: MagneticBoots = MagneticBoots.new()
	player.add_child(boots)
	boots.configure(player)
	return {"root": holder, "ship": ship, "player": player, "boots": boots}


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame
