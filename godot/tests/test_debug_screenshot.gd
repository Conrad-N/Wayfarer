## Checks capture input and headless refusal; actual PNGs require a windowed run.
extends TestCase


## F12 is reserved for capture, and an autorepeat cannot request another image.
func test_f12_binding_ignores_release_and_repeat() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F12
	event.pressed = true
	check(event.is_action_pressed("debug_screenshot"), "physical F12 requests capture")
	event.echo = true
	check(not event.is_action_pressed("debug_screenshot"), "held-key repeats do not request capture")
	event.echo = false
	event.pressed = false
	check(not event.is_action_pressed("debug_screenshot"), "releasing F12 does not request capture")


## Headless capture completes immediately with a useful error, without awaiting rendering.
func test_headless_capture_fails_without_waiting_for_a_frame() -> void:
	if DisplayServer.get_name() != "headless":
		check(true, "headless-only guard; windowed verification covers rendering")
		return
	var capture: DebugScreenshot = DebugScreenshot.new()
	var results: Array[Error] = []
	capture.capture_finished.connect(func(_path: String, error: Error) -> void: results.append(error))
	capture.capture()
	capture.capture()
	check_eq(results.size(), 2, "both requests finish immediately; no stuck capture")
	if results.size() == 2:
		check_eq(results[0], ERR_UNAVAILABLE, "no rendered viewport in headless mode")
		check_eq(results[1], ERR_UNAVAILABLE, "subsequent request also fails softly")
	capture.free()
