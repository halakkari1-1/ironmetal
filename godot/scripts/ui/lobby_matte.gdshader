// The painting's own fence line, stood up in 3D at its place: it shows exactly the pixels of the painting
// behind it (looked up by screen position), so it cannot be seen, but it hides whatever of the 3D yard stands
// further away (the cliffs' feet behind the fence and barricades), as the painted fence would. Drawn after the
// solid pieces and blended over them, so what stands in front of it (lamps, the car) is never covered.
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D painting : source_color, filter_linear;
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);   // where the painting sits on screen: position, size (pixels)
uniform vec2 screen = vec2(1.0);                // viewport size in pixels

void fragment() {
	vec2 uv = (SCREEN_UV * screen - rect.xy) / rect.zw;
	ALBEDO = texture(painting, uv).rgb;
	// solid along the fence, fading out towards the top: the feet of the cliffs melt into the painted haze
	ALPHA = smoothstep(0.0, 0.75, UV.y);
}
