// Angular celestial discs drawn only behind scene geometry, without distant depth-buffer meshes.
shader_type sky;
render_mode disable_fog;

uniform vec3 planet_direction = vec3(-1.0, 0.0, 0.0);
uniform float planet_radius_ratio = 0.0;
uniform float planet_distance_m = 1.0;
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);
uniform float moon_radius_ratio = 0.0;
uniform float moon_distance_m = 1.0;
uniform vec3 light_direction = vec3(0.35, 0.7, 0.6);

void body_disc(vec3 ray, vec3 centre, float radius_ratio, float distance_m, vec3 albedo, inout vec3 color, inout float nearest) {
	float projected = dot(ray, centre);
	float discriminant = projected * projected - (1.0 - radius_ratio * radius_ratio);
	if (radius_ratio > 0.0 && projected > 0.0 && discriminant >= 0.0) {
		float along_ray = projected - sqrt(discriminant);
		float depth = along_ray * distance_m;
		if (depth < nearest) {
			vec3 normal = normalize((ray * along_ray - centre) / radius_ratio);
			// Quantized normals give plain, flat colour facets like the local part kit.
			vec3 facet = normalize(floor(normal * 8.0 + vec3(0.5)) / 8.0);
			float illumination = 0.08 + 0.92 * max(dot(facet, normalize(light_direction)), 0.0);
			color = albedo * illumination;
			nearest = depth;
		}
	}
}

void sky() {
	vec3 color = vec3(0.002, 0.003, 0.007);
	if (!AT_CUBEMAP_PASS) {
		float nearest = 1e30;
		body_disc(EYEDIR, planet_direction, planet_radius_ratio, planet_distance_m, vec3(0.045, 0.19, 0.34), color, nearest);
		body_disc(EYEDIR, moon_direction, moon_radius_ratio, moon_distance_m, vec3(0.42, 0.43, 0.45), color, nearest);
	}
	COLOR = color;
}
