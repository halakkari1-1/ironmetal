// The arena floor (see Arena._ground): tiled dirt broken up by large light and dark patches, a concrete square in
// the middle on some maps, and the arena's baked detail masks: grime (cracks, tyre tracks, old scorches), oil and
// water. Oil and puddles are smooth, so they mirror the sky and catch the searchlights and fires.
shader_type spatial;
render_mode cull_back;

uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D wet_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D water_map : filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(0.6, 0.55, 0.5);
uniform float tile = 0.28;
uniform float concrete_half = 0.0;
uniform float arena_half = 66.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 dirt = texture(dirt_albedo, p * tile).rgb * tint * 1.5;
	// large patches: the same texture sampled huge and at another angle, as a soft light/dark variation
	float big = texture(dirt_albedo, p * 0.011).g;
	float big2 = texture(dirt_albedo, vec2(p.y, -p.x) * 0.023 + 0.37).r;
	dirt *= 0.78 + 0.5 * big * big2 * 1.6;
	vec3 n_t = texture(dirt_normal, p * tile).rgb;
	float edge = max(abs(p.x), abs(p.y));
	float conc = concrete_half > 0.0 ? 1.0 - smoothstep(concrete_half - 0.6, concrete_half + 0.6, edge) : 0.0;
	vec3 concrete = texture(concrete_tex, p / 15.0).rgb * vec3(0.78, 0.75, 0.71);
	vec3 col = mix(dirt, concrete, conc);
	vec2 duv = p / (2.0 * arena_half) + 0.5;
	float inside = step(0.0, duv.x) * step(duv.x, 1.0) * step(0.0, duv.y) * step(duv.y, 1.0);
	float grime = texture(grime_map, duv).r * inside;
	float wet = texture(wet_map, duv).r * inside;
	float water = texture(water_map, duv).r * inside;
	col *= 1.0 - 0.55 * grime;
	col = mix(col, vec3(0.025, 0.022, 0.02), wet * 0.85);
	col = mix(col, col * 0.3 + vec3(0.015, 0.02, 0.03), water * 0.9);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.95, 0.88, conc), 0.06, max(wet * 0.75, water));
	SPECULAR = 0.5 + 0.4 * water;
	NORMAL_MAP = mix(n_t, vec3(0.5, 0.5, 1.0), max(conc * 0.6, water));
	NORMAL_MAP_DEPTH = 0.9;
}
