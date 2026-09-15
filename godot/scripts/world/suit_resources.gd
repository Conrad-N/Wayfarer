## Suit consumables in SI units. Each suit owns its own stores; spending never
## creates resources or lets them go negative. Powered tools draw energy explicitly.
class_name SuitResources
extends RefCounted

const PROPELLANT_CAPACITY_KG: float = 8.0
const BATTERY_CAPACITY_J: float = 720000.0
## Fractions of capacity whose crossing is worth a debug entry, low to high.
const _WARNING_FRACTIONS: Array[float] = [0.0, 0.10, 0.25]
const RECOVERY_MARGIN: float = 0.02

## Warning band last logged per store, so small wobbles at a level log once.
var _logged_bands: Dictionary = {"battery": _WARNING_FRACTIONS.size(), "propellant": _WARNING_FRACTIONS.size()}

var propellant_kg: float = PROPELLANT_CAPACITY_KG:
	set(value):
		propellant_kg = clampf(value, 0.0, PROPELLANT_CAPACITY_KG) if is_finite(value) else 0.0
var battery_energy_j: float = BATTERY_CAPACITY_J:
	set(value):
		battery_energy_j = clampf(value, 0.0, BATTERY_CAPACITY_J) if is_finite(value) else 0.0


## Spend up to the requested propellant mass and return the mass actually supplied.
func consume_propellant(requested_kg: float) -> float:
	if not is_finite(requested_kg) or requested_kg <= 0.0:
		return 0.0
	var before: float = propellant_kg
	var supplied: float = minf(requested_kg, propellant_kg)
	propellant_kg -= supplied
	_log_crossings("propellant", before, propellant_kg, PROPELLANT_CAPACITY_KG, "kg")
	return supplied


## Spend up to the requested tool energy and return the joules actually supplied.
func consume_energy(requested_j: float) -> float:
	if not is_finite(requested_j) or requested_j <= 0.0:
		return 0.0
	var before: float = battery_energy_j
	var supplied: float = minf(requested_j, battery_energy_j)
	battery_energy_j -= supplied
	_log_crossings("battery", before, battery_energy_j, BATTERY_CAPACITY_J, "J")
	return supplied


## Accept recovered electrical energy up to battery capacity; excess becomes heat.
func charge_energy(requested_j: float) -> float:
	if not is_finite(requested_j) or requested_j <= 0.0:
		return 0.0
	var before: float = battery_energy_j
	var accepted: float = minf(requested_j, BATTERY_CAPACITY_J - battery_energy_j)
	battery_energy_j += accepted
	_log_crossings("battery", before, battery_energy_j, BATTERY_CAPACITY_J, "J")
	return accepted


## Log battery/propellant falling to 25%, 10% or empty, and recovering past them.
## Recovery must clear the level by 2% of capacity, so a store hovering at a level
## (a flat battery braking on regeneration, say) logs once, not every frame.
func _log_crossings(kind: String, before: float, after: float, capacity: float, unit: String) -> void:
	if capacity <= 0.0 or is_equal_approx(before, after):
		return
	var logged: int = int(_logged_bands.get(kind, _WARNING_FRACTIONS.size()))
	var band: int = _band(after, capacity, 0.0)
	var recovered_band: int = _band(after, capacity, RECOVERY_MARGIN)
	if band < logged:
		# One large drain can pass several levels; log each, highest first.
		for level: int in range(logged - 1, band - 1, -1):
			if level == 0:
				DebugLog.event("suit", "%s empty" % kind)
			else:
				DebugLog.event("suit", "%s below %d%%: %.0f %s" % [kind, roundi(_WARNING_FRACTIONS[level] * 100.0), after, unit])
		_logged_bands[kind] = band
	elif recovered_band > logged:
		for level: int in range(logged, recovered_band):
			if level == 0:
				DebugLog.event("suit", "%s available again: %.0f %s" % [kind, after, unit])
			else:
				DebugLog.event("suit", "%s above %d%%: %.0f %s" % [kind, roundi(_WARNING_FRACTIONS[level] * 100.0), after, unit])
		_logged_bands[kind] = recovered_band


## How many warning levels the amount is above, each raised by `margin` of capacity.
func _band(amount: float, capacity: float, margin: float) -> int:
	var count: int = 0
	for fraction: float in _WARNING_FRACTIONS:
		if amount > capacity * (fraction + margin):
			count += 1
	return count


## Propellant and battery charge; there is no suit oxygen store to save yet.
func to_save() -> Dictionary:
	return {"propellant_kg": propellant_kg, "battery_energy_j": battery_energy_j}


## Restore saved stores. The property setters above clamp to [0, capacity].
func apply_save(data: Dictionary) -> void:
	propellant_kg = float(data.get("propellant_kg", propellant_kg))
	battery_energy_j = float(data.get("battery_energy_j", battery_energy_j))
	# Loading is not gameplay: start from the loaded levels without logging them.
	_logged_bands = {"battery": _band(battery_energy_j, BATTERY_CAPACITY_J, 0.0), "propellant": _band(propellant_kg, PROPELLANT_CAPACITY_KG, 0.0)}
