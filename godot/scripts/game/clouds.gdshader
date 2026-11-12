// Drifting clouds on a dome high over the arena, in three layers read from one tileable noise texture: a low
// deck (broad shapes plus a finer layer that breaks them up, moving at different speeds) and a thin, high,
// slower layer of streaks behind it for depth. Lighting needs no extra reads: where a cloud is thin (its edge)
// the sun shines through, and its thick middle is in its own shade; towards the sun the edges light up (a
// silver lining) and the whole deck takes the sunset colour. Clouds thin out towards the horizon.
// Unshaded and blended over the sky; three texture reads per pixel.
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

void fragment() {
	vec3 d = normalize(dir);
	if (d.y < 0.01) { discard; }
	float t = TIME * 0.004 * speed;
	// the low deck: flat, seen in perspective, so far clouds bunch up towards the horizon
	vec2 uv = d.xz / (d.y + 0.12);
	float den = texture(noise_tex, uv * 0.35 + vec2(t, t * 0.3)).r * 0.72
			+ texture(noise_tex, uv * 0.9 - vec2(t * 1.6, -t * 0.5)).g * 0.38;
	float th = mix(0.72, 0.4, cover);
	float a = smoothstep(th, th + 0.2, den);
	float thick = smoothstep(th + 0.05, th + 0.45, den);     // 0 at the edge of a cloud, 1 deep inside
	// the high layer: further up (less bunching), stretched into streaks, drifting slowly the other way
	vec2 uvh = d.xz / (d.y + 0.34);
	float hi = texture(noise_tex, uvh * vec2(0.16, 0.42) + vec2(0.37 - t * 0.35, 0.61 + t * 0.12)).g;
	float ah = smoothstep(0.52, 0.86, hi + (cover - 0.5) * 0.25) * 0.5;
	// light
	float sunward = max(dot(d, normalize(sun_dir)), 0.0);
	float glow = sunward * sunward * sunward;
	float lit = clamp(0.28 + (1.0 - thick) * 0.6 + glow * 0.35, 0.0, 1.0);
	vec3 low_col = mix(shade_color, lit_color, lit);
	low_col += lit_color * (pow(sunward, 7.0) * (1.0 - thick) * 0.85 + glow * 0.25);   // silver lining, sunset wash
	vec3 hi_col = mix(shade_color, lit_color, 0.72) + lit_color * glow * 0.45;
	float alpha = a + ah * (1.0 - a);
	ALBEDO = (low_col * a + hi_col * ah * (1.0 - a)) / max(alpha, 0.001);
	ALPHA = alpha * opacity * smoothstep(0.01, 0.12, d.y);
}
