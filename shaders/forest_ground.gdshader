shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 grass_shadow : source_color = vec3(0.025, 0.060, 0.018);
uniform vec3 grass_base : source_color = vec3(0.060, 0.125, 0.035);
uniform vec3 grass_tip : source_color = vec3(0.120, 0.205, 0.055);
uniform vec3 moss_color : source_color = vec3(0.085, 0.145, 0.032);
uniform vec3 soil_dark : source_color = vec3(0.075, 0.043, 0.022);
uniform vec3 soil_light : source_color = vec3(0.145, 0.085, 0.038);
uniform float detail_strength : hint_range(0.0, 1.5) = 0.85;

varying vec3 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm3(vec2 p) {
	float n = value_noise(p) * 0.58;
	n += value_noise(p * 2.07 + vec2(17.4, 5.8)) * 0.28;
	n += value_noise(p * 4.13 + vec2(-8.2, 21.1)) * 0.14;
	return n;
}

float cellular(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 2.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 point = offset + vec2(hash21(cell + offset), hash21(cell + offset + 37.2));
			nearest = min(nearest, length(point - local));
		}
	}
	return nearest;
}

float ellipse_mask(vec2 p, vec2 center, vec2 radius, float softness) {
	float d = length((p - center) / radius);
	return 1.0 - smoothstep(1.0 - softness, 1.0, d);
}

float surface_height(vec2 p) {
	float medium = fbm3(p * 1.65);
	float fine = value_noise(p * 7.5 + vec2(31.0, -12.0));
	float grains = 1.0 - smoothstep(0.20, 0.62, cellular(p * 11.0));
	return medium * 0.52 + fine * 0.28 + grains * 0.20;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float macro = fbm3(p * 0.105);
	float medium = fbm3(p * 1.55 + vec2(11.3, -6.7));
	float fine = value_noise(p * 7.5 + vec2(-2.0, 19.0));
	float cells = cellular(p * 5.5);
	float crisp_cells = 1.0 - smoothstep(0.18, 0.46, cells);
	float flecks = step(0.78, hash21(floor(p * 10.0)));

	// Sharply separated low-poly color bands instead of a blurry gradient.
	float macro_band = smoothstep(0.38, 0.47, macro) * 0.52 + smoothstep(0.62, 0.69, macro) * 0.48;
	vec3 ground = mix(grass_shadow, grass_base, macro_band);
	float tip_mask = smoothstep(0.57, 0.68, medium) * (0.65 + crisp_cells * 0.35);
	ground = mix(ground, grass_tip, tip_mask * 0.56);
	float moss_mask = smoothstep(0.68, 0.75, macro + medium * 0.22) * smoothstep(0.35, 0.55, crisp_cells + fine * 0.25);
	ground = mix(ground, moss_color, moss_mask * 0.72);

	float cabin_wear = ellipse_mask(p, vec2(0.0, -2.0), vec2(8.5, 8.0), 0.28);
	float garden_wear = ellipse_mask(p, vec2(-8.0, -4.0), vec2(6.2, 5.2), 0.28);
	float wear_noise = fbm3(p * 0.42 + vec2(4.0, 8.0));
	float wear = max(cabin_wear, garden_wear) * smoothstep(0.46, 0.58, wear_noise) * 0.48;
	vec3 soil = mix(soil_dark, soil_light, smoothstep(0.38, 0.62, medium));
	ground = mix(ground, soil, wear);

	// Sub-decimetre flecks stay sharp even when viewed close to the ground.
	ground *= 0.91 + fine * 0.14;
	ground = mix(ground, grass_tip * 0.75, flecks * 0.12 * detail_strength);
	ground *= 0.93 + crisp_cells * 0.11 * detail_strength;
	ALBEDO = ground;
	ROUGHNESS = clamp(0.86 + (1.0 - fine) * 0.13, 0.0, 1.0);
	SPECULAR = 0.08;

	// High-frequency procedural normal: independent of texture resolution.
	float epsilon = 0.018;
	float h_l = surface_height(p - vec2(epsilon, 0.0));
	float h_r = surface_height(p + vec2(epsilon, 0.0));
	float h_d = surface_height(p - vec2(0.0, epsilon));
	float h_u = surface_height(p + vec2(0.0, epsilon));
	vec2 slope = vec2(h_l - h_r, h_d - h_u) * 2.8 * detail_strength;
	NORMAL_MAP = normalize(vec3(slope, 1.0));
	NORMAL_MAP_DEPTH = 0.62;
}
