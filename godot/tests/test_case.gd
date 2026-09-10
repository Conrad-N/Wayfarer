## Base class for headless tests. Subclass in tests/test_*.gd and add methods
## named test_*. Use the check_* helpers instead of assert() so one failure
## does not abort the whole run.
class_name TestCase
extends RefCounted

var failures: PackedStringArray = []
var checks: int = 0
var _current: String = ""


func set_current(name: String) -> void:
	_current = name


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [_current, msg])


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	check(actual == expected, "%s expected %s, got %s" % [msg, str(expected), str(actual)])


## Relative tolerance check for floats. tol is a fraction (0.001 = 0.1%).
func check_close(actual: float, expected: float, tol: float, msg: String = "") -> void:
	var denom: float = maxf(absf(expected), 1e-300)
	var rel: float = absf(actual - expected) / denom
	check(rel <= tol, "%s expected %s (±%s rel), got %s (rel err %s)" % [msg, expected, tol, actual, rel])


## Absolute tolerance check.
func check_near(actual: float, expected: float, abs_tol: float, msg: String = "") -> void:
	check(absf(actual - expected) <= abs_tol, "%s expected %s (±%s), got %s" % [msg, expected, abs_tol, actual])
