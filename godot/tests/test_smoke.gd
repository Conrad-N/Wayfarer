## Proves the runner works. Keep this file; add real suites beside it.
extends TestCase


func test_runner_is_alive() -> void:
	check_eq(1 + 1, 2, "arithmetic")
	check_close(PI, 3.14159265, 1e-6, "pi")


func test_gdscript_float_is_64_bit() -> void:
	# The orbital layer depends on this. If it ever fails, the sim is wrong.
	var a: float = 1.0
	var b: float = 1.0 + 1e-12
	check(a != b, "float must resolve 1e-12 differences (64-bit)")
	var v: Vector3 = Vector3(1.0, 0.0, 0.0)
	var w: Vector3 = Vector3(1.0 + 1e-12, 0.0, 0.0)
	check(v == w, "Vector3 is 32-bit and must NOT be used for orbital state")
