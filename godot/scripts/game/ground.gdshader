// The arena floor (see Arena._ground). Four layers, mixed by broad masks and by height:
//   1. the map's own dirt (or sand, or concrete slab texture): the base;
//   2. loose gravel, gathered in patches: stones poke through the dirt first where a patch thins out;
//   3. dark trodden mud, which settles into the low places of whatever is under it;
//   4. fine grit, seen only up close: it fades out with distance, where it would only shimmer.
// On top come the concrete square in the middle of some maps and the arena's baked detail masks: grime (cracks,
// tyre tracks, old scorches), oil and water. The ground is matte: only oil and puddles are smooth, so only they
// mirror the sky and catch the searchlights and fires.
//
// Arena._ground switches the lines below on to build the cheaper versions (texture reads per pixel in brackets):
//   full (13, 14 with the concrete square), GROUND_MED (12 / 13): one sample of the dirt instead of two,
//   GROUND_LOW (7 / 8): no fine grit, no roughness or layer normal maps, mud as a plain colour.
shader_type spatial;
render_mode cull_back;
//#define GROUND_MED
//#define GROUND_LOW
//#define GROUND_CONCRETE

uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_ch : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // colour, height in alpha
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;      // r gravel, g mud, b light and dark, a dirt mix
#ifndef GROUND_LOW
uniform sampler2D dirt_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_nr : filter_linear_mipmap_anisotropic, repeat_enable;    // normal x y, roughness
uniform sampler2D mud_ch : source_color, filter_linear_mipmap_anisotropic, repeat_enable;      // colour, height in alpha
uniform sampler2D mud_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;     // r grit, gb its normal
#endif
#ifdef GROUND_CONCRETE
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
#endif
uniform sampler2D grime_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D wet_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D water_map : filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(0.6, 0.55, 0.5);
uniform vec3 gravel_tint = vec3(0.7, 0.6, 0.55);   // multiplies the gravel colour, so it belongs to the map
uniform float tile = 0.28;
uniform float concrete_half = 0.0;
uniform float arena_half = 66.0;
uniform float mud = 0.0;      // how much of the floor is dark mud
uniform float gravel = 0.0;   // how much is gravel

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 q = p * tile;
	// 1 near the camera, 0 far away: fine detail and relief are for the ground close by
	float near = 1.0 - smoothstep(16.0, 60.0, distance(wpos, CAMERA_POSITION_WORLD));
	vec4 mac = texture(macro_tex, p * 0.0085);
	// base: the floor texture, with a second sample turned and scaled so the repeat doesn't show
	vec3 dirt = texture(dirt_albedo, q).rgb;
#ifndef GROUND_LOW
#ifndef GROUND_MED
	vec3 dirt2 = texture(dirt_albedo, vec2(q.y, -q.x) * 0.61 + 0.27).rgb;
	dirt = mix(dirt, dirt2, smoothstep(0.35, 0.65, mac.a) * 0.5);
#endif
#endif
	float dirt_h = clamp(dot(dirt, vec3(1.2)), 0.0, 1.0);   // lighter grains stand a little higher
	dirt *= tint * (0.82 + 0.36 * mac.b);                   // large soft light and dark patches
	// gravel: where its mask is strong it covers the dirt; at the edge of a patch only the tall stones show
	vec2 gq = p * 0.45;
	vec4 gr = texture(gravel_ch, gq);
	float gk = smoothstep(0.44, 0.58, mac.r + (gravel - 0.5) * 0.9 + (gr.a - 0.5) * 0.4 - (dirt_h - 0.5) * 0.15);
	gk *= step(0.001, gravel);
	vec3 col = mix(dirt, gr.rgb * gravel_tint * (0.9 + 0.2 * mac.b), gk);
	float surf_h = mix(dirt_h, gr.a, gk);
	// mud: broad patches that fill the low places first
	float mk = smoothstep(0.45, 0.6, mac.g + (mud - 0.68) * 0.9 + (0.5 - surf_h) * 0.3) * step(0.001, mud);
#ifdef GROUND_LOW
	col = mix(col, vec3(0.17, 0.125, 0.09), mk * 0.8);
	vec3 nm = mix(texture(dirt_normal, q).rgb, vec3(0.5, 0.5, 1.0), max(gk * 0.5, mk * 0.7));
	float rough = 0.9;
#else
	vec2 mq = p * 0.34 + 0.4;
	vec4 md = texture(mud_ch, mq);
	col = mix(col, md.rgb * (0.85 + 0.3 * mac.b), mk * 0.9);
	vec3 gnr = texture(gravel_nr, gq).rgb;
	vec3 mnr = texture(mud_nr, mq).rgb;
	vec3 nm = mix(texture(dirt_normal, q).rgb, vec3(gnr.rg, 1.0), gk);
	nm = mix(nm, vec3(mnr.rg, 1.0), mk);
	float rough = mix(max(texture(dirt_rough, q).r, 0.86), gnr.b, gk);   // dirt never shines
	rough = mix(rough, mnr.b, mk);
	// fine grit, close up only
	vec3 dt = texture(detail_tex, p * 1.7).rgb;
	col *= 1.0 + (dt.r - 0.5) * 0.55 * near * (1.0 - mk * 0.5);
	nm.rg += (dt.gb - 0.5) * 0.5 * near;
#endif
	float conc = 0.0;
#ifdef GROUND_CONCRETE
	float edge = max(abs(p.x), abs(p.y));
	conc = 1.0 - smoothstep(concrete_half - 0.6, concrete_half + 0.6, edge);
	col = mix(col, texture(concrete_tex, p / 5.0).rgb * 0.95, conc);
#endif
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
	ROUGHNESS = mix(mix(rough, 0.9, conc), 0.07, max(oil, water));
	SPECULAR = mix(0.18, 0.5, max(oil, water));
	NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), max(conc * 0.6, water));
	NORMAL_MAP_DEPTH = mix(0.6, 0.9, near);   // flatter far away, where relief turns into shimmer
}
