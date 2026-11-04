// The arena floor (see Arena._ground): tiled dirt broken up by large light and dark patches, a concrete square in
// the middle on some maps, and the arena's baked detail masks: grime (cracks, tyre tracks, old scorches), oil and
// water, and patches of dark trodden mud. The ground itself is matte dirt: only oil and puddles are smooth, so
// only they mirror the sky and catch the searchlights and fires.
shader_type spatial;
render_mode cull_back;

uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D wet_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D water_map : filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(0.6, 0.55, 0.5);
uniform float tile = 0.28;
uniform float concrete_half = 0.0;
uniform float arena_half = 66.0;
uniform float mud = 0.0;   // how much of the floor is dark mud

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	// the floor texture, plus a second sample turned and scaled so the repeat doesn't show
	vec2 q = p * tile;
	vec3 dirt = texture(dirt_albedo, q).rgb;
	vec3 dirt2 = texture(dirt_albedo, vec2(q.y, -q.x) * 0.61 + 0.27).rgb;
	float blend = smoothstep(0.35, 0.65, texture(dirt_albedo, p * 0.013).g);
	dirt = mix(dirt, dirt2, blend * 0.5) * tint;
	// large soft light/dark patches
	float big = texture(dirt_albedo, p * 0.009 + 0.5).r;
	dirt *= 0.85 + 0.3 * big;
	// dark trodden mud in broad patches with ragged edges
	float mn = texture(dirt_albedo, p * 0.006 + vec2(0.31, 0.77)).g * 0.7 + texture(dirt_albedo, p * 0.031).b * 0.3;
	float mud_k = mud * smoothstep(0.42, 0.58, mn + (mud - 0.5) * 0.25);
	vec3 mud_col = vec3(0.16, 0.12, 0.085) * (0.75 + 0.5 * dot(dirt, vec3(0.33)) / max(0.05, dot(tint, vec3(0.33))));
	dirt = mix(dirt, mud_col, mud_k * 0.85);
	vec3 n_t = texture(dirt_normal, p * tile).rgb;
	float edge = max(abs(p.x), abs(p.y));
	float conc = concrete_half > 0.0 ? 1.0 - smoothstep(concrete_half - 0.6, concrete_half + 0.6, edge) : 0.0;
	vec3 concrete = texture(concrete_tex, p / 5.0).rgb * 0.95;
	vec3 col = mix(dirt, concrete, conc);
	vec2 duv = p / (2.0 * arena_half) + 0.5;
	float inside = step(0.0, duv.x) * step(duv.x, 1.0) * step(0.0, duv.y) * step(duv.y, 1.0);
	float grime = texture(grime_map, duv).r * inside;
	float wet = texture(wet_map, duv).r * inside;
	float water = texture(water_map, duv).r * inside;
	col *= 1.0 - 0.55 * grime;
	float oil = smoothstep(0.35, 0.75, wet);   // only the real oil slicks, not the faint edge of the mask
	col = mix(col, vec3(0.025, 0.022, 0.02), oil * 0.85);
	col = mix(col, col * 0.3 + vec3(0.015, 0.02, 0.03), water * 0.9);
	ALBEDO = col;
	float rough = max(texture(dirt_rough, q).r, 0.86);   // dirt never shines
	ROUGHNESS = mix(mix(rough, 0.9, conc), 0.07, max(oil, water));
	SPECULAR = mix(0.18, 0.5, max(oil, water));
	NORMAL_MAP = mix(n_t, vec3(0.5, 0.5, 1.0), max(conc * 0.6, water));
	NORMAL_MAP_DEPTH = 0.9;
}
