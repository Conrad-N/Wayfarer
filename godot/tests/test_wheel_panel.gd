## Reaction-wheel telemetry and commands stay shared across terminals and tablet.
extends TestCase


## Wheel status reflects API state while its switch remains independent of jet RCS.
func test_wheel_controls_and_live_telemetry() -> void:
	var api: ShipApi = ShipApi.new()
	var panel: ShipPanel = ShipPanel.new()
	panel.configure(api, "SHIP")
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	api.publish_flight({"attitude_mode": "manual", "reaction_wheel": {"momentum_nms": {"x": -40000.0, "y": 200.0, "z": 0.0}, "capacity_nms": 100000.0, "utilization": 0.4}}, 0.0)
	panel.refresh()
	check(panel._wheel_readout.text.contains("40% / AUTO OFF"), "Storage and disabled automatic compensation are distinct")
	check(panel._wheel_readout.text.contains("-40000"), "Signed axis momentum is visible")
	check(panel._wheel_readout.text.contains("±100000"), "Capacity is explicitly per axis")
	panel.get_button("reaction_wheel").pressed.emit()
	check(not bool(api.get_telemetry().systems.reaction_wheel.enabled), "Shared wheel switch disables module through ShipApi")
	check(bool(api.get_telemetry().systems.rcs.enabled), "Wheel switch does not disable jet RCS")
	check(panel._wheel_readout.text.contains("UNAVAILABLE"), "Disabled module is visible")
	panel.get_button("reaction_wheel").pressed.emit()
	api.publish_flight({"attitude_mode": "kill", "reaction_wheel": {"momentum_nms": {"x": 100000.0, "y": 0.0, "z": 0.0}, "capacity_nms": 100000.0, "utilization": 1.0}}, 0.0)
	panel.select_app("NAV")
	check(panel._flight_wheels.text.contains("SATURATED"), "NAV warns when wheel storage is full")
	check_eq(panel._attitude.get_item_text(0), "AUTO OFF", "Manual mode explains that compensation is disabled")
	api.set_system_enabled("power", false)
	panel.refresh()
	check(panel._flight_wheels.text.contains("NO POWER"), "Power loss is visible on independent tablet")
	panel.free()
