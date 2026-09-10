## Hierarchical inertial frames, legacy celestial fixtures and invalid-tree protection.
extends TestCase


## Check 25: root origin, AU-scale planet radius, and relative translated states.
func test_legacy_hierarchy() -> void:
	var system: OrbitalSystem = SimConstants.default_system()
	check(system.valid, "default hierarchy valid")
	check_eq(system.root_id, "sol", "Sol is root")
	check_eq(system.children("sol").size(), 2, "two reference planets")
	var sol: Dictionary = system.body_state_in_root("sol", 12345.0)
	check_eq(SimVector.length(sol.position), 0.0, "root exact position origin")
	check_eq(SimVector.length(sol.velocity), 0.0, "root exact velocity origin")
	var cradle: Dictionary = system.body_state_in_root("cradle", 12345.0)
	check_near(SimVector.length(cradle.position), SimConstants.AU, 1.0, "Cradle at one AU")
	var relative: Dictionary = system.relative_state("cradle", "vesper", 7777.0)
	var a: Dictionary = system.body_state_in_root("cradle", 7777.0)
	var b: Dictionary = system.body_state_in_root("vesper", 7777.0)
	check_near(SimVector.distance(relative.position, SimVector.sub(b.position, a.position)), 0.0, 1e-3, "relative position subtraction")
	check_near(SimVector.distance(relative.velocity, SimVector.sub(b.velocity, a.velocity)), 0.0, 1e-6, "relative velocity subtraction")
	check_near(float(system.body("cradle").soi_radius) / 1e8, 9.2, 0.1, "Cradle Laplace sphere")
	var changed: Dictionary = system.body("cradle")
	changed.elements.a = 1.0
	check_near(system.body("cradle").elements.a, SimConstants.AU, 1.0, "readers cannot mutate stored hierarchy")


## A real third-level moon inherits both its planet's position and velocity.
func test_moon_hierarchy_and_invalid_trees() -> void:
	var moon: Dictionary = {"id": "moon", "name": "Moon", "mu": 4.9048695e12, "radius": 1.7374e6, "parent_id": "cradle", "elements": SimConstants.circular_orbit(SimConstants.cradle(), 384.4e6 - 6.371e6), "soi_radius": 66.1e6}
	var system: OrbitalSystem = OrbitalSystem.new([SimConstants.sol(), SimConstants.cradle(), moon])
	check(system.valid, "three-level hierarchy valid")
	var relative: Dictionary = system.relative_state("cradle", "moon", 12345.0)
	var expected: Dictionary = OrbitMath.propagate(moon.elements, SimConstants.cradle(), 12345.0)
	check_near(SimVector.distance(relative.position, expected.position), 0.0, 1e-4, "moon parent-relative position")
	check_near(SimVector.distance(relative.velocity, expected.velocity), 0.0, 1e-8, "moon parent-relative velocity")
	check(not OrbitalSystem.new([]).valid, "empty hierarchy invalid")
	check(not OrbitalSystem.new([SimConstants.sol(), SimConstants.sol()]).valid, "duplicate body rejected")
	var orphan: Dictionary = SimConstants.cradle()
	orphan.parent_id = "missing"
	check(not OrbitalSystem.new([SimConstants.sol(), orphan]).valid, "unknown parent rejected")
	var cycle: Dictionary = SimConstants.cradle()
	cycle.parent_id = "cradle"
	check(not OrbitalSystem.new([SimConstants.sol(), cycle]).valid, "cyclic hierarchy rejected")
	check(system.body("missing").is_empty(), "unknown lookup fails soft")
	check(system.body_state_in_root("missing", 0.0).is_empty(), "unknown state fails soft")
