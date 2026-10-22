// The lobby yard comes alive: the clouds drift across the moonlit sky, the street lamps and the lit towers
// glow up and fade like real sodium lights (each one on its own rhythm), their reflections on the wet ground
// follow them, the moon breathes and the painted ring pulses. Regions are picked by position and colour.
shader_type canvas_item;

uniform vec2 moon = vec2(0.841, 0.141);
uniform vec2 ring_c = vec2(0.6724, 0.674);
uniform vec2 ring_r = vec2(0.2686, 0.0622);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec4 base = texture(TEXTURE, uv);
	float lum0 = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float md = length((uv - moon) * vec2(1.78, 1.0));
	// sky: the upper part, dark and bluish, away from the moon disc
	float upper = 1.0 - smoothstep(0.30, 0.44, uv.y);
	float sky = upper * (1.0 - smoothstep(0.2, 0.42, lum0)) * smoothstep(-0.03, 0.04, base.b - base.r) * step(0.03, md);
	// the painted clouds drift: the sky is pushed along a slow flow
	float t = TIME;
	vec2 fl = texture(noise_tex, uv * vec2(1.2, 2.0) + vec2(t * 0.006, 0.0)).rg - 0.5;
	vec2 duv = uv + vec2(fl.x * 0.012 - 0.0, fl.y * 0.004) * sky;
	vec4 c = texture(TEXTURE, duv);
	// a thin moving cloud layer on top, moonlit near the moon
	float n = texture(noise_tex, uv * vec2(1.6, 3.2) + vec2(t * 0.01, t * 0.002)).r;
	float n2 = texture(noise_tex, uv * vec2(3.5, 6.0) - vec2(t * 0.016, 0.0)).g;
	float cl = smoothstep(0.52, 0.78, n * 0.72 + n2 * 0.38);
	vec3 ccol = mix(vec3(0.09, 0.1, 0.16), vec3(0.6, 0.64, 0.75), exp(-md * 5.5));
	c.rgb = mix(c.rgb, ccol, cl * sky * 0.6);
	// warm lights: bright orange pixels (lamps, lit floors, the glow in the mist) and their reflections below
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float warm = smoothstep(0.05, 0.25, c.r - c.b) * smoothstep(0.28, 0.65, lum);
	// each light flickers on its own: cells across the picture; reflections share their lamp's column
	vec2 cell = floor(vec2(uv.x * 46.0, uv.y < 0.6 ? uv.y * 18.0 : 0.0));
	float r = hash(cell);
	float glow = 0.82 + 0.22 * sin(t * (0.7 + r * 1.6) + r * 40.0) + 0.08 * sin(t * (5.0 + r * 7.0) + r * 13.0);
	float dip = step(0.93, r) * smoothstep(0.0, 0.08, fract(t * (0.08 + r * 0.1) + r * 7.0)) * (1.0 - smoothstep(0.08, 0.2, fract(t * (0.08 + r * 0.1) + r * 7.0)));
	c.rgb *= mix(1.0, glow * (1.0 - 0.55 * dip), warm);
	c.rgb += vec3(1.0, 0.5, 0.15) * warm * max(glow - 0.9, 0.0) * 0.6;
	// the moon breathes
	c.rgb += vec3(0.55, 0.65, 0.95) * 0.09 * exp(-md * 26.0) * (0.6 + 0.4 * sin(t * 0.9));
	// the painted ring pulses
	float e = length((uv - ring_c) / ring_r);
	float ring = exp(-pow((e - 1.0) * 14.0, 2.0)) * step(0.5, uv.y);
	c.rgb += vec3(1.0, 0.45, 0.12) * ring * (0.18 + 0.14 * sin(t * 2.2));
	COLOR = vec4(c.rgb, 1.0);
}
