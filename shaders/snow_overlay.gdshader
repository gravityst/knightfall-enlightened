shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;
// Next-pass overlay that settles snow on upward-facing surfaces (roofs in the Frostlands).
global uniform float snow_cover;
uniform float base_snow = 0.85;
varying vec3 v_n;
varying vec3 v_w;
void vertex() {
	v_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * 0.012;
}
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float n = h(floor(v_w.xz * 3.0)) * 0.25 + h(floor(v_w.xz * 0.7)) * 0.35;
	float a = smoothstep(0.35, 0.75, v_n.y) * clamp(base_snow + snow_cover * 0.5 + n - 0.2, 0.0, 1.0);
	ALBEDO = vec3(0.93, 0.95, 0.98);
	ROUGHNESS = 0.75;
	ALPHA = a;
}
