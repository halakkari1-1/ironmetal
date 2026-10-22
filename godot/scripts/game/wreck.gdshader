// Burnt-out wrecks: no texture, just charred paint, bare rusted metal and grey ash laid on in world space
// (triplanar noise), so every wreck in a pile looks different though they share a handful of meshes.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 char_color : source_color = vec3(0.06, 0.05, 0.045);
uniform vec3 rust_color : source_color = vec3(0.36, 0.17, 0.08);
uniform vec3 ash_color : source_color = vec3(0.32, 0.31, 0.3);

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 paint;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	paint = COLOR.rgb;   // per-wreck faded paint colour (instance colour)
}

void fragment() {
	float n1 = noise(wpos * 0.9);
	float n2 = noise(wpos * 3.7 + 11.0);
	float rust = smoothstep(0.55, 0.85, n1 * 0.7 + n2 * 0.4);
	float burnt = smoothstep(0.35, 0.65, noise(wpos * 0.45 + 5.0));   // where the fire took the paint off
	float ash = smoothstep(0.6, 0.9, n2) * smoothstep(0.3, 0.9, wnrm.y);   // ash settles on top faces
	vec3 col = mix(paint * 0.55, char_color, burnt);
	col = mix(col, rust_color, rust * 0.6);
	col = mix(col, ash_color, ash * 0.5);
	col *= 0.8 + 0.4 * noise(wpos * 12.0);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.85, burnt);
	METALLIC = mix(0.55, 0.3, rust);
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
