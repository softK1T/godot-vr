shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
global uniform float world_wind;
global uniform vec4 season_foliage;
global uniform float season_desat;

// Small, world-space wind: the base remains planted, tips move gently.
uniform float wind_strength : hint_range(0.0, 0.1) = 0.035;
uniform float wind_speed : hint_range(0.0, 3.0) = 0.9;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height = clamp(VERTEX.y / 0.8, 0.0, 1.0);
	float bend = height * height;
	float wave = sin(TIME * wind_speed + world_pos.x * 0.37 + world_pos.z * 0.21);
	float ripple = sin(TIME * wind_speed * 0.63 - world_pos.x * 0.16 + world_pos.z * 0.29);
	VERTEX.x += (wave + ripple * 0.35) * wind_strength * world_wind * bend;
	VERTEX.z += ripple * wind_strength * world_wind * 0.45 * bend;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.96;
	METALLIC = 0.0;

	ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.3, 0.59, 0.11))), season_desat) * season_foliage.rgb;
}
