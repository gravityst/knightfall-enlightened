shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Procedural animation for un-rigged animal models: quadruped gait (legs swing in a
// diagonal trot), grazing head dip, bird wing flapping and water bobbing.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform int mode = 0;                 // 0 quadruped, 1 bird, 2 swimmer
uniform float y0 = 0.0;
uniform float height = 1.0;
uniform float z0 = 0.0;
uniform float length = 1.0;
uniform float wing_x = 0.2;
uniform float cut_y = 1e9;
uniform float cut_z = -1e9;

instance uniform float gait = 0.0;
instance uniform float gait_rate = 6.0;
instance uniform float graze = 0.0;
instance uniform float flap = 0.0;
instance uniform float phase_off = 0.0;

varying float v_cut;

vec2 rot(vec2 p, vec2 pivot, float a) {
	vec2 r = p - pivot;
	float c = cos(a);
	float s = sin(a);
	return pivot + vec2(r.x * c - r.y * s, r.x * s + r.y * c);
}

void vertex() {
	vec3 v = VERTEX;
	v_cut = (v.y > cut_y && v.z > cut_z) ? 1.0 : 0.0;
	float t = TIME * gait_rate + phase_off;
	if (mode == 0) {
		float leg_top = y0 + height * 0.42;
		float hip_f = z0 + length * 0.7;
		float hip_b = z0 + length * 0.28;
		if (v.y < leg_top) {
			bool front = v.z > (hip_f + hip_b) * 0.5;
			bool left = v.x > 0.0;
			float ph = t + (front ? 0.0 : 3.14159) + (left ? 0.0 : 3.14159);
			float a = sin(ph) * 0.45 * min(gait, 1.6);
			float pz = front ? hip_f : hip_b;
			vec2 zy = rot(vec2(v.z, v.y), vec2(pz, leg_top), a * smoothstep(leg_top, y0, v.y) * 1.2);
			v.z = zy.x;
			v.y = zy.y;
		}
		v.y += abs(sin(t)) * 0.03 * height * min(gait, 1.0);
		float head_z = z0 + length * 0.78;
		if (graze > 0.0 && v.z > head_z && v.y > leg_top) {
			vec2 zy = rot(vec2(v.z, v.y), vec2(head_z, y0 + height * 0.62), -graze * 0.85 * smoothstep(head_z, z0 + length, v.z + length * 0.1));
			v.z = zy.x;
			v.y = zy.y;
		}
	} else if (mode == 1) {
		float wx = abs(v.x) - wing_x;
		if (wx > 0.0) {
			float side = sign(v.x);
			float a = sin(TIME * 12.0 + phase_off) * flap * 0.85 + flap * 0.15;
			v.y += wx * sin(a);
			v.x = side * (wing_x + wx * cos(a));
		}
		v.y += sin(TIME * 2.0 + phase_off) * 0.02 * height * (1.0 - flap);
	} else {
		v.y += sin(TIME * 1.7 + phase_off) * 0.025 * height;
		v.z += sin(TIME * 0.9 + phase_off) * 0.01 * length;
	}
	VERTEX = v;
}

void fragment() {
	if (v_cut > 0.5) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV) * tint;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
