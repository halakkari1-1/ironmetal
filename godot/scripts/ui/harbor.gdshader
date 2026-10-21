// The harbour backdrop comes alive: clouds drift over the sky, the city's windows shimmer and some blink,
// the river ripples, the moon breathes, and the painted ring pulses. Everything is driven by TIME on the
// painting itself; regions are picked by position and colour, so nothing else needs to be hand-masked.
shader_type canvas_item;

uniform vec2 moon = vec2(0.852, 0.175);
uniform vec2 ring_c = vec2(0.6926, 0.661);
uniform vec2 ring_r = vec2(0.2703, 0.0659);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.02 + vec2(3.1, 1.7); a *= 0.5; } return v; }

void fragment() {
	vec2 uv = UV;
	vec4 base = texture(TEXTURE, uv);
	float lum0 = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	// sky: the upper part, dark and bluish (not the lit towers)
	float upper = 1.0 - smoothstep(0.30, 0.46, uv.y);
	float sky = upper * (1.0 - smoothstep(0.16, 0.32, lum0)) * smoothstep(-0.02, 0.06, base.b - base.r);
	// river: a band under the skyline, ripples sideways
	float river = smoothstep(0.478, 0.49, uv.y) * (1.0 - smoothstep(0.515, 0.53, uv.y)) * step(0.36, uv.x);
	vec2 duv = uv;
	duv.x += sin(uv.y * 900.0 + TIME * 3.0) * 0.0016 * river;
	// the painted clouds sway a little along a slow flow
	float flow = fbm(uv * vec2(5.0, 9.0) + vec2(TIME * 0.035, 0.0));
	duv += vec2(flow - 0.5, (flow - 0.5) * 0.35) * 0.006 * sky;
	vec4 c = texture(TEXTURE, duv);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// a drifting cloud layer, moonlit near the moon
	float n = fbm(uv * vec2(4.0, 8.0) + vec2(TIME * 0.018, TIME * 0.004));
	float n2 = fbm(uv * vec2(9.0, 15.0) - vec2(TIME * 0.03, 0.0));
	float cl = smoothstep(0.5, 0.78, n * 0.75 + n2 * 0.35);
	float md = length((uv - moon) * vec2(1.78, 1.0));
	vec3 ccol = mix(vec3(0.10, 0.13, 0.22), vec3(0.55, 0.62, 0.78), exp(-md * 5.0));
	c.rgb = mix(c.rgb, ccol, cl * sky * 0.55);
	// windows: bright pixels in the towers shimmer; a few blink off and on
	float towers = (1.0 - smoothstep(0.47, 0.5, uv.y)) * step(0.3, uv.x) * step(0.05, md);
	float lit = smoothstep(0.42, 0.75, lum) * towers;
	vec2 cell = floor(uv * vec2(300.0, 190.0));
	float r = hash(cell);
	float shimmer = 0.82 + 0.3 * sin(TIME * (1.5 + r * 4.0) + r * 60.0);
	float blink = step(0.9, r) * step(0.55, fract(TIME * (0.12 + r * 0.35) + r * 9.0));
	float sparkle = step(0.985, r) * pow(max(sin(TIME * (0.8 + r) + r * 30.0), 0.0), 18.0) * 1.6;
	c.rgb *= mix(1.0, mix(shimmer, 0.12, blink) + sparkle, lit);
	// the moon breathes
	c.rgb += vec3(0.55, 0.65, 0.95) * 0.08 * exp(-md * 30.0) * (0.6 + 0.4 * sin(TIME * 0.9));
	// the painted ring pulses
	float e = length((uv - ring_c) / ring_r);
	float ring = exp(-pow((e - 1.0) * 14.0, 2.0)) * step(0.5, uv.y);
	c.rgb += vec3(1.0, 0.45, 0.12) * ring * (0.18 + 0.14 * sin(TIME * 2.2));
	COLOR = vec4(c.rgb, 1.0);
}
