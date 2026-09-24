shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
global uniform float world_wind;
global uniform vec4 season_foliage;
global uniform float season_desat;

// Darken only green texels; preserve bark, highlights, and the original texture.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float foliage_strength : hint_range(0.0, 1.0) = 0.76;
uniform float canopy_brightness : hint_range(0.25, 1.0) = 0.76;

varying float canopy_face;

void vertex() {
    // Darker sides give the low-poly canopy volume without changing the lights.
    vec3 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    canopy_face = clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0);

	vec3 season_wind_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.x += sin(TIME * 1.4 + season_wind_p.x * 0.35 + season_wind_p.z * 0.27) * 0.025 * world_wind * clamp(VERTEX.y * 0.25, 0.0, 1.0);
	VERTEX.z += cos(TIME * 1.1 + season_wind_p.x * 0.21) * 0.015 * world_wind * clamp(VERTEX.y * 0.25, 0.0, 1.0);
}

void fragment() {
    vec4 texel = texture(albedo_texture, UV);
    vec3 original = texel.rgb * COLOR.rgb;
    float green_mask = smoothstep(0.01, 0.12, original.g - original.r)
        * smoothstep(0.015, 0.12, original.g - original.b);
    vec3 olive = vec3(
        original.r * 0.81 + original.g * 0.11,
        original.g * 0.78 + original.r * 0.10,
        original.b * 0.76 + original.r * 0.09
    );
    float shape_light = mix(0.72, 1.0, canopy_face);
    ALBEDO = mix(original, olive * canopy_brightness * shape_light, green_mask * foliage_strength);
    ROUGHNESS = 0.95;
    METALLIC = 0.0;

	ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.3, 0.59, 0.11))), season_desat) * season_foliage.rgb;
}
