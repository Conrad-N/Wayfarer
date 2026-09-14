## Render Cradle and Lune at their actual angular sizes in the sky, preserving local depth precision.
class_name OrbitalSky
extends Node

const SKY_SHADER: Shader = preload("res://scripts/world/orbital_sky.gdshader")

var _session: OrbitalSession
var _material: ShaderMaterial
var _sun_light: DirectionalLight3D


## Install the celestial background while preserving the scene's authored ambient lighting.
func configure(session: OrbitalSession, world_environment: WorldEnvironment) -> void:
	if session == null or world_environment == null:
		return
	_session = session
	_material = ShaderMaterial.new()
	_material.shader = SKY_SHADER
	var sky: Sky = Sky.new()
	sky.sky_material = _material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	if world_environment.environment == null:
		world_environment.environment = Environment.new()
	world_environment.environment.sky = sky
	world_environment.environment.background_mode = Environment.BG_SKY
	var lights: Array[Node] = get_tree().root.find_children("DirectionalLight3D", "DirectionalLight3D", true, false)
	_sun_light = lights[0] as DirectionalLight3D if not lights.is_empty() else null
	_update_bodies()


func _process(_delta: float) -> void:
	_update_bodies()


func _update_bodies() -> void:
	if not is_instance_valid(_session) or _session.world == null or _material == null:
		return
	var ship: Dictionary = _session.world.ship_root_state()
	if ship.is_empty():
		return
	_update_body("cradle", "planet", ship.position)
	_update_body("lune", "moon", ship.position)
	_update_sun(ship.position)


## Aim the scene light along the sim Sun bearing, so the lit hull side matches
## the solar panels. The bearing is a unit vector already normalized in scalar
## doubles (same root frame `_update_body` uses above), so converting it to a
## native Vector3 loses no precision even though `ship_position` can be huge.
func _update_sun(ship_position: SimVector) -> void:
	if not is_instance_valid(_sun_light):
		return
	var bearing: Dictionary = SolarArray.sun_bearing(_session.world.system, ship_position, _session.world.time)
	var direction: Vector3 = LocalOrbitFrame.native(bearing.direction)
	if direction.length() < 0.001:
		return
	_sun_light.global_basis = Basis.looking_at(-direction, Vector3.UP if absf(direction.y) < 0.999 else Vector3.FORWARD)


func _update_body(body_id: String, prefix: String, ship_position: SimVector) -> void:
	if not _session.world.system.has(body_id):
		_material.set_shader_parameter(prefix + "_radius_ratio", 0.0)
		return
	var body: Dictionary = _session.world.system.body(body_id)
	var state: Dictionary = _session.world.system.body_state_in_root(body_id, _session.world.time)
	if state.is_empty():
		_material.set_shader_parameter(prefix + "_radius_ratio", 0.0)
		return
	# All large translations and radius/distance division happen in scalar doubles.
	# Only the resulting unit vector and angular ratio are sent to the GPU.
	var relative: SimVector = SimVector.sub(state.position, ship_position)
	var distance: float = SimVector.length(relative)
	if distance <= 0.0 or not is_finite(distance):
		_material.set_shader_parameter(prefix + "_radius_ratio", 0.0)
		return
	_material.set_shader_parameter(prefix + "_direction", LocalOrbitFrame.native(SimVector.normalized(relative)))
	_material.set_shader_parameter(prefix + "_radius_ratio", clampf(float(body.radius) / distance, 0.0, 0.999999))
	_material.set_shader_parameter(prefix + "_distance_m", distance)
