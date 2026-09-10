## Analytic elliptical and hyperbolic Kepler propagation in scalar SI doubles.
class_name OrbitMath
extends RefCounted


## Solve M = E - e sin(E), returning E in the signed principal interval.
static func solve_kepler(mean_anomaly: float, e: float) -> float:
	if not is_finite(mean_anomaly) or not is_finite(e) or e < 0.0 or e >= 1.0:
		return NAN
	var m: float = fposmod(mean_anomaly + PI, TAU) - PI
	var eccentric: float = m if e < 0.8 else PI * (-1.0 if m < 0.0 else 1.0)
	for _k: int in range(100):
		var delta: float = (eccentric - e * sin(eccentric) - m) / (1.0 - e * cos(eccentric))
		eccentric -= delta
		if absf(delta) < 1e-12:
			break
	return eccentric


## Solve the unwrapped hyperbolic Kepler equation M = e sinh(H) - H.
static func solve_hyper_kepler(mean_anomaly: float, e: float) -> float:
	if not is_finite(mean_anomaly) or not is_finite(e) or e <= 1.0:
		return NAN
	var h: float = signf(mean_anomaly) * log(2.0 * absf(mean_anomaly) / e + 1.8) if absf(mean_anomaly) > 6.0 else asinh_scalar(mean_anomaly / e)
	for _k: int in range(100):
		var delta: float = (e * sinh(h) - h - mean_anomaly) / (e * cosh(h) - 1.0)
		h -= delta
		if absf(delta) < 1e-12:
			break
	return h


## Stable odd inverse hyperbolic sine using only scalar arithmetic.
static func asinh_scalar(value: float) -> float:
	var magnitude: float = absf(value)
	return signf(value) * (log(magnitude) + log(2.0) if magnitude > 1e150 else log(magnitude + sqrt(magnitude * magnitude + 1.0)))


## Inverse hyperbolic cosine; invalid arguments return NaN.
static func acosh_scalar(value: float) -> float:
	if value < 1.0:
		return NAN
	return log(value) + log(2.0) if value > 1e150 else log(value + sqrt(value * value - 1.0))


## Inverse hyperbolic tangent; invalid arguments return NaN.
static func atanh_scalar(value: float) -> float:
	return 0.5 * log((1.0 + value) / (1.0 - value)) if absf(value) < 1.0 else NAN


## Validate supported nonradial conics. Exactly parabolic motion has no finite a.
static func valid_elements(el: Dictionary, body: Dictionary) -> bool:
	for key: String in ["a", "e", "i", "raan", "argp", "mean_anomaly_at_epoch", "epoch"]:
		if not el.has(key) or not (el[key] is float or el[key] is int) or not is_finite(float(el[key])):
			return false
	var a: float = el.a
	var e: float = el.e
	return float(body.get("mu", 0.0)) > 0.0 and is_finite(float(body.get("mu", 0.0))) and e >= 0.0 and ((e < 1.0 and a > 0.0) or (e > 1.0 and a < 0.0))


## Next strictly future outbound sphere crossing, or null if none exists.
static func next_escape_time(el: Dictionary, body: Dictionary, from_t: float, soi_radius: float) -> Variant:
	if not valid_elements(el, body) or not is_finite(from_t) or not is_finite(soi_radius) or soi_radius <= 0.0:
		return null
	var a: float = el.a
	var e: float = el.e
	var n: float = sqrt(float(body.mu) / pow(absf(a), 3.0))
	var m_now: float = float(el.mean_anomaly_at_epoch) + n * (from_t - float(el.epoch))
	if e < 1.0:
		if a * (1.0 + e) <= soi_radius or e == 0.0:
			return null
		var cos_e: float = (1.0 - soi_radius / a) / e
		if cos_e < -1.0 or cos_e > 1.0:
			return null
		var eccentric: float = acos(clampf(cos_e, -1.0, 1.0))
		var m_cross: float = eccentric - e * sin(eccentric)
		var m_target: float = m_cross + ceil((m_now - m_cross) / TAU - 1e-9) * TAU
		if m_target < m_now + 1e-9:
			m_target += TAU
		return from_t + (m_target - m_now) / n
	var cosh_h: float = (1.0 - soi_radius / a) / e
	if cosh_h < 1.0:
		return null
	var hyper: float = acosh_scalar(cosh_h)
	var m_cross: float = e * sinh(hyper) - hyper
	return from_t + (m_cross - m_now) / n if m_cross > m_now + 1e-9 else null


## Full orbit telemetry at an explicit sim time. Invalid elements return an empty dictionary.
static func propagate(el: Dictionary, body: Dictionary, t: float) -> Dictionary:
	if not valid_elements(el, body) or not is_finite(t):
		return {}
	var a: float = el.a
	var e: float = el.e
	var inclination: float = el.i
	var raan: float = el.raan
	var argp: float = el.argp
	var mu: float = body.mu
	var mean_motion: float = sqrt(mu / pow(absf(a), 3.0))
	var period: float = TAU / mean_motion if e < 1.0 else INF
	var mean_anomaly: float = float(el.mean_anomaly_at_epoch) + mean_motion * (t - float(el.epoch))
	var eccentric: float
	var true_anomaly: float
	var radius: float
	var apoapsis: float = INF
	var time_to_apoapsis: float = INF
	var time_to_periapsis: float
	if e < 1.0:
		mean_anomaly = fposmod(mean_anomaly, TAU)
		eccentric = solve_kepler(mean_anomaly, e)
		true_anomaly = fposmod(2.0 * atan2(sqrt(1.0 + e) * sin(eccentric / 2.0), sqrt(1.0 - e) * cos(eccentric / 2.0)), TAU)
		radius = a * (1.0 - e * cos(eccentric))
		eccentric = fposmod(eccentric, TAU)
		apoapsis = a * (1.0 + e)
		time_to_apoapsis = fposmod(PI - mean_anomaly, TAU) / mean_motion
		time_to_periapsis = fposmod(TAU - mean_anomaly, TAU) / mean_motion
	else:
		eccentric = solve_hyper_kepler(mean_anomaly, e)
		true_anomaly = fposmod(2.0 * atan2(sqrt(e + 1.0) * sinh(eccentric / 2.0), sqrt(e - 1.0) * cosh(eccentric / 2.0)), TAU)
		radius = a * (1.0 - e * cosh(eccentric))
		time_to_periapsis = -mean_anomaly / mean_motion if mean_anomaly <= 0.0 else INF
	var periapsis: float = a * (1.0 - e)
	var speed: float = sqrt(mu * (2.0 / radius - 1.0 / a))
	var angular_momentum: float = sqrt(mu * a * (1.0 - e * e))
	var cos_nu: float = cos(true_anomaly)
	var sin_nu: float = sin(true_anomaly)
	var position: SimVector = _rotate_perifocal(raan, inclination, argp, radius * cos_nu, radius * sin_nu)
	var velocity: SimVector = _rotate_perifocal(raan, inclination, argp, -mu / angular_momentum * sin_nu, mu / angular_momentum * (e + cos_nu))
	var body_radius: float = body.get("radius", 0.0)
	return {
		"a": a, "e": e, "i": inclination, "raan": raan, "argp": argp,
		"true_anomaly": true_anomaly, "eccentric_anomaly": eccentric, "mean_anomaly": mean_anomaly,
		"period": period, "mean_motion": mean_motion, "periapsis_radius": periapsis, "apoapsis_radius": apoapsis,
		"periapsis_altitude": periapsis - body_radius, "apoapsis_altitude": apoapsis - body_radius,
		"radius": radius, "altitude": radius - body_radius, "speed": speed,
		"specific_energy": -mu / (2.0 * a), "specific_angular_momentum": angular_momentum,
		"flight_path_angle": atan2(e * sin_nu, 1.0 + e * cos_nu),
		"time_since_periapsis": mean_anomaly / mean_motion, "time_to_periapsis": time_to_periapsis,
		"time_to_apoapsis": time_to_apoapsis, "latitude": asin(clampf(position.z / radius, -1.0, 1.0)),
		"position": position, "velocity": velocity,
	}


static func _rotate_perifocal(raan: float, inclination: float, argp: float, x: float, y: float) -> SimVector:
	var co: float = cos(raan)
	var so: float = sin(raan)
	var ci: float = cos(inclination)
	var si: float = sin(inclination)
	var cw: float = cos(argp)
	var sw: float = sin(argp)
	return SimVector.new((co * cw - so * sw * ci) * x + (-co * sw - so * cw * ci) * y, (so * cw + co * sw * ci) * x + (-so * sw + co * cw * ci) * y, sw * si * x + cw * si * y)
