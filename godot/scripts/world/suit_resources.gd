## Suit consumables in SI units. Each suit owns its own stores; spending never
## creates resources or lets them go negative. Powered tools draw energy explicitly.
class_name SuitResources
extends RefCounted

const PROPELLANT_CAPACITY_KG: float = 8.0
const BATTERY_CAPACITY_J: float = 720000.0

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
	var supplied: float = minf(requested_kg, propellant_kg)
	propellant_kg -= supplied
	return supplied


## Spend up to the requested tool energy and return the joules actually supplied.
func consume_energy(requested_j: float) -> float:
	if not is_finite(requested_j) or requested_j <= 0.0:
		return 0.0
	var supplied: float = minf(requested_j, battery_energy_j)
	battery_energy_j -= supplied
	return supplied
