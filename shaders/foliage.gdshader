shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
// Shared material for trees, bushes, crops and other vegetation: PBR + wind + translucency.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform bool use_alpha = false;
uniform float alpha_scissor = 0.5;
uniform float roughness = 0.85;
uniform float wind_amount = 1.0;
uniform float flutter = 0.0;
uniform float translucency = 0.0;
uniform float bend_height = 9.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_var = 0.12;
uniform float snow_amount = 0.0;
uniform float hue_shift = 0.0;
uniform float sat_mul = 1.0;
uniform float val_mul = 1.0;

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float snow_cover;

varying float v_rand;
varying vec3 v_wnormal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 hue_rotate(vec3 c, float h, float s, float v) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	vec3 hsv = vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
	hsv.x = fract(hsv.x + h);
	hsv.y = clamp(hsv.y * s, 0.0, 1.0);
	hsv.z = clamp(hsv.z * v, 0.0, 1.0);
	vec3 rgb = clamp(abs(fract(hsv.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return hsv.z * mix(vec3(1.0), rgb, hsv.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_rand = hash(origin.xz);
	float h = max(VERTEX.y, 0.0);
	float bend = pow(h / bend_height, 1.6) * wind_amount;
	float t = TIME * (0.9 + v_rand * 0.4) + v_rand * 6.28;
	float gust = sin(t * 1.1 + origin.x * 0.02) * 0.5 + sin(t * 0.43 + origin.z * 0.015) * 0.5;
	vec2 sway = wind_dir * (0.35 + gust * 0.65) * wind_strength * bend * 0.55;
	vec3 disp = vec3(sway.x, 0.0, sway.y);
	if (flutter > 0.0) {
		float f = sin(t * 7.0 + VERTEX.x * 3.1 + VERTEX.z * 2.7) * 0.5 + sin(t * 11.3 + VERTEX.y * 4.0) * 0.5;
		disp += NORMAL * f * flutter * 0.04 * (0.3 + wind_strength);
	}
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += inv * disp;
	v_wnormal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	if (use_alpha) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
	vec3 base = hue_shift != 0.0 ? hue_rotate(c.rgb, hue_shift, sat_mul, val_mul) : c.rgb;
	vec3 col = base * tint * (1.0 - tint_var + v_rand * tint_var * 2.0);
	float snow = clamp((snow_amount + snow_cover * 0.8) * smoothstep(0.2, 0.8, v_wnormal.y), 0.0, 0.85);
	col = mix(col, vec3(0.92, 0.94, 0.97), snow);
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	if (translucency > 0.0) {
		BACKLIGHT = col * translucency;
	}
}
