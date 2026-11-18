shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.02, 0.09, 0.12);
uniform vec3 shallow : source_color = vec3(0.05, 0.22, 0.24);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
vec2 wave(vec2 p, vec2 dir, float freq, float speed, float amp) {
	float ph = dot(p, dir) * freq + TIME * speed;
	return dir * cos(ph) * amp * freq;
}
void fragment() {
	vec2 p = wpos.xz;
	vec2 g = wave(p, normalize(vec2(0.8, 0.6)), 0.21, 0.9, 0.35) + wave(p, normalize(vec2(-0.5, 0.86)), 0.37, 1.3, 0.2)
		+ wave(p, normalize(vec2(0.2, -0.98)), 0.93, 1.9, 0.07) + wave(p, normalize(vec2(-0.9, -0.3)), 1.7, 2.6, 0.035)
		+ wave(p, normalize(vec2(0.6, 0.8)), 3.1, 3.4, 0.016);
	float far = clamp(length(wpos - CAMERA_POSITION_WORLD) / 900.0, 0.0, 1.0);
	g *= mix(1.0, 0.25, far);
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(shallow, deep, clamp(0.4 + far, 0.0, 1.0)) * (1.0 - fres * 0.6);
	ROUGHNESS = 0.06 + 0.2 * far; METALLIC = 0.0; SPECULAR = 0.7;
}
