shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;
global uniform float world_rain;
uniform vec4 shallow_color : source_color = vec4(0.18, 0.43, 0.46, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.19, 0.27, 1.0);
uniform float flow_speed = 0.0;
uniform float alpha = 0.8;
void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.55 + TIME * 1.1) * 0.025 + cos(VERTEX.z * 0.47 + TIME * 0.9) * 0.02;

	VERTEX.y += sin(VERTEX.x * 7.0 + TIME * 6.0) * cos(VERTEX.z * 6.3 - TIME * 5.2) * 0.01 * world_rain;
}
void fragment() {
	vec2 uv = UV + vec2(-TIME * flow_speed, 0.0);
	float r1 = sin(uv.x * 9.0 + uv.y * 3.0 + TIME * 1.6);
	float r2 = cos(uv.y * 11.0 - uv.x * 2.0 - TIME * 1.3);
	NORMAL_MAP = vec3(0.5 + r1 * 0.07, 0.5 + r2 * 0.07, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(shallow_color.rgb, deep_color.rgb, 0.55 + r1 * 0.05);
	ROUGHNESS = 0.07;
	SPECULAR = 0.7;
	ALPHA = clamp(alpha + fres * 0.15, 0.0, 1.0);

	NORMAL = normalize(NORMAL + vec3(sin(UV.x * 60.0 + TIME * 9.0), 0.0, cos(UV.y * 57.0 - TIME * 8.0)) * 0.08 * world_rain);
}
