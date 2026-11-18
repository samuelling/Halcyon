shader_type canvas_item;
// The lens: a little chromatic fringe and vignette, film grain, a red pulse when hit, and the cold
// wash of a blackout. Drawn over the 3D view, under the HUD.
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float grain = 0.045;
uniform float fringe = 0.0018;
uniform float vignette = 0.42;
uniform float hurt = 0.0;
uniform float low = 0.0;
uniform float dark = 0.0;
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void fragment() {
	vec2 uv = SCREEN_UV; vec2 c = uv - 0.5; float r2 = dot(c, c);
	vec2 off = c * (fringe + hurt * 0.004) * (0.4 + r2 * 4.0);
	vec3 col = vec3(texture(screen, uv + off).r, texture(screen, uv).g, texture(screen, uv - off).b);
	float g = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(g), clamp(low * 0.6, 0.0, 0.7));
	col = mix(col, col * vec3(0.86, 0.95, 1.08), dark * 0.6);
	col *= 1.0 - vignette * smoothstep(0.12, 0.62, r2) ;
	col += (hash(uv * vec2(1920.0, 1080.0) + TIME * 61.0) - 0.5) * grain * (1.2 - g);
	col = mix(col, vec3(0.55, 0.02, 0.02), clamp((hurt * 0.55 + low * 0.25) * smoothstep(0.05, 0.5, r2), 0.0, 0.8));
	COLOR = vec4(col, 1.0);
}
