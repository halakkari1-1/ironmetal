// Drifting clouds on a dome high over the arena: two layers of a tileable noise texture scrolling at different
// speeds and directions, lit from the sun side (bright edges towards it, darker bellies away), thinning out
// towards the horizon. Unshaded and blended over the sky; a few texture reads per pixel, cheap on phones.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 lit_color : source_color = vec3(1.0, 0.75, 0.6);
uniform vec3 shade_color : source_color = vec3(0.35, 0.3, 0.4);
uniform vec3 sun_dir = vec3(0.4, 0.3, 0.8);     // towards the sun
uniform float cover = 0.5;                       // 0 clear .. 1 overcast
uniform float speed = 1.0;
uniform float opacity = 0.9;

varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

float dens(vec2 uv, float t) {
	float a = texture(noise_tex, uv * 0.35 + vec2(t, t * 0.3)).r;
	float b = texture(noise_tex, uv * 0.9 - vec2(t * 1.6, -t * 0.5)).g;
	return a * 0.72 + b * 0.38;
}

void fragment() {
	vec3 d = normalize(dir);
	if (d.y < 0.01) { discard; }
	// a flat cloud deck seen in perspective: far clouds bunch up towards the horizon
	vec2 uv = d.xz / (d.y + 0.12);
	float t = TIME * 0.004 * speed;
	float den = dens(uv, t);
	float th = mix(0.72, 0.4, cover);
	float a = smoothstep(th, th + 0.2, den);
	// thinner towards the sun = lit edge
	vec2 off = normalize(sun_dir.xz + vec2(0.0001)) * 0.08;
	float towards = dens(uv + off, t);
	float lit = clamp(0.55 + (den - towards) * 5.0, 0.0, 1.0);
	float sunward = pow(max(dot(d, normalize(sun_dir)), 0.0), 4.0);
	ALBEDO = mix(shade_color, lit_color, lit) + lit_color * sunward * 0.5;
	ALPHA = a * opacity * smoothstep(0.01, 0.12, d.y);
}
