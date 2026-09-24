shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
global uniform vec4 season_ground;
global uniform float season_desat;

uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 terrain_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	terrain_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = terrain_pos.xz;
	float basin = smooth_noise(p * 0.29 + vec2(4.0, 9.0));
	basin = basin * 0.8 + smooth_noise(p * 0.75) * 0.2;
	float flatness = smoothstep(0.85, 0.98, NORMAL.y);
	float puddle = smoothstep(0.53, 0.66, basin) * flatness * wetness;
	float damp = wetness * (0.28 + 0.72 * smooth_noise(p * 0.45));
	ALBEDO = mix(COLOR.rgb, COLOR.rgb * vec3(0.55, 0.62, 0.65), damp);
	ALBEDO = mix(ALBEDO, vec3(0.12, 0.17, 0.20), puddle * 0.48);
	ROUGHNESS = mix(0.96, 0.54, damp);
	ROUGHNESS = mix(ROUGHNESS, 0.09, puddle);
	METALLIC = puddle * 0.32;
	SPECULAR = mix(0.5, 0.82, puddle);

	ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.3, 0.59, 0.11))), season_desat * 0.8) * season_ground.rgb;
}
