// The 3D pieces of the lobby yard (towers, cliffs, bridge, outpost, flood lights, the car's platform).
// Lit by the scene's lights like any surface; on top of that, the warm bright spots of the colour map (lit
// windows, lamps, glowing seams) give off light of their own, each flickering slightly on its own rhythm, so
// the models glow the way the painting around them does. A tint pulls each model into the painting's colours.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float emit = 0.0;          // how strongly the warm bright spots glow
uniform float emit_lum = 0.5;      // how bright a spot of the colour map must be to glow
uniform vec3 emit_color : source_color = vec3(1.0, 0.55, 0.22);
uniform float metal = 0.6;
uniform float rough_min = 0.35;    // rock and concrete never shine

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	ALBEDO = a * tint;
	vec3 o = texture(orm_tex, UV).rgb;
	ROUGHNESS = max(o.g, rough_min);
	METALLIC = o.b * metal;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	float lum = dot(a, vec3(0.3, 0.59, 0.11));
	float warm = smoothstep(0.05, 0.22, a.r - a.b) * smoothstep(emit_lum, emit_lum + 0.18, lum);
	// a slow flicker per spot (cells of world space), like old sodium lamps and fires behind windows
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r = fract(sin(dot(floor(w * 0.5), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float fl = 0.8 + 0.2 * sin(TIME * (0.8 + r * 2.1) + r * 30.0) + 0.06 * sin(TIME * (7.0 + r * 9.0));
	EMISSION = emit_color * (0.4 + a) * warm * emit * fl;
}
