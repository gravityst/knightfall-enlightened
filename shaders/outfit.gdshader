shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Character clothing / skin: PBR with per-NPC recolouring (hue, saturation, value) and an
// optional "steel" look used to turn leather garments into a knight's mail and plate.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : filter_linear_mipmap;
uniform bool use_normal = false;
uniform bool use_orm = false;
uniform bool is_skin = false;
uniform bool is_hair = false;
uniform float base_roughness = 0.8;
uniform bool mask_body = false;
uniform float keep[96];
varying float v_keep;

instance uniform float hue_shift = 0.0;
instance uniform float sat_mul = 1.0;
instance uniform float val_mul = 1.0;
instance uniform float steel = 0.0;
instance uniform vec3 skin_tint = vec3(1.0);
instance uniform float dust = 0.0;
instance uniform vec3 hair_color = vec3(0.35, 0.24, 0.15);

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	v_keep = 1.0;
	if (mask_body) {
		v_keep = keep[min(int(BONE_INDICES.x), 95)] * BONE_WEIGHTS.x + keep[min(int(BONE_INDICES.y), 95)] * BONE_WEIGHTS.y
			+ keep[min(int(BONE_INDICES.z), 95)] * BONE_WEIGHTS.z + keep[min(int(BONE_INDICES.w), 95)] * BONE_WEIGHTS.w;
	}
}

void fragment() {
	if (mask_body && v_keep < 0.5) {
		discard;
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	float rough = base_roughness;
	float metal = 0.0;
	float ao = 1.0;
	if (use_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		ao = orm.r;
		rough = orm.g;
		metal = orm.b;
	}
	if (is_skin) {
		c *= skin_tint;
	} else if (is_hair) {
		c = c * hair_color * 1.6;
		rough = 0.55;
	} else {
		vec3 hsv = rgb2hsv(c);
		hsv.x = fract(hsv.x + hue_shift);
		hsv.y = clamp(hsv.y * sat_mul, 0.0, 1.0);
		hsv.z = clamp(hsv.z * val_mul, 0.0, 1.0);
		c = hsv2rgb(hsv);
		if (steel > 0.0) {
			float l = dot(c, vec3(0.3, 0.55, 0.15));
			vec3 st = vec3(0.56, 0.58, 0.62) * (0.55 + l * 0.9);
			c = mix(c, st, steel);
			metal = mix(metal, 0.85, steel);
			rough = mix(rough, 0.32, steel);
		}
		c = mix(c, c * vec3(1.05, 0.92, 0.75), dust);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	if (is_skin) {
		SSS_STRENGTH = 0.35;
	}
}
