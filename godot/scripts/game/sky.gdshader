// Arena sky: a graded dome from the zenith colour to a glowing horizon, the sun (or the moon at night) with a
// wide halo, a band of haze low down, and stars on the night map. Nothing here moves, so the reflections and
// ambient light computed from it are made once; the moving clouds are a separate dome (clouds.gdshader).
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.17, 0.18, 0.33);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.54, 0.3);
uniform vec3 ground_color : source_color = vec3(0.12, 0.1, 0.09);
uniform vec3 sun_color : source_color = vec3(1.0, 0.7, 0.45);
uniform float sun_size = 0.012;     // angular radius (radians) of the disc
uniform float halo = 0.35;          // strength of the wide glow around it
uniform float stars = 0.0;          // 0..1
uniform float moon = 0.0;           // 1: the disc is a pale moon

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	// zenith to horizon: the horizon colour climbs higher near the sun
	vec3 sdir = LIGHT0_DIRECTION;
	float to_sun = max(dot(d, sdir), 0.0);
	float band = pow(1.0 - clamp(h, 0.0, 1.0), 3.2 - 1.4 * to_sun);
	vec3 col = mix(top_color, horizon_color, band);
	// haze close to the horizon
	col = mix(col, horizon_color * 1.08, smoothstep(0.12, 0.0, abs(h)) * 0.6);
	// below the horizon: dark ground haze (rarely seen, the district hides it)
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	// the sun / moon
	float ang = acos(clamp(dot(d, sdir), -1.0, 1.0));
	float disc = 1.0 - smoothstep(sun_size * 0.85, sun_size, ang);
	col += sun_color * pow(to_sun, 8.0) * halo + sun_color * pow(to_sun, 90.0) * halo * 1.5;
	vec3 disc_col = mix(sun_color * 4.0, vec3(0.92, 0.95, 1.0) * 1.6, moon);
	col = mix(col, disc_col, disc * step(0.0, h));
	// stars
	if (stars > 0.0 && h > 0.0) {
		vec3 g = floor(d * 380.0);
		float s = hash(g);
		float tw = step(0.9965, s) * smoothstep(0.0, 0.25, h);
		col += vec3(0.9, 0.95, 1.0) * tw * stars * (0.4 + 0.6 * hash(g + 3.1));
	}
	COLOR = col;
}
