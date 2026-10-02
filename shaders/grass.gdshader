shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_disabled;
// GPU-placed ground cover. Instances form a grid that scrolls with the camera; each
// cell picks a stable random offset, reads the biome map for density & colour and the
// heightmap for its ground height. No CPU work per frame.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_alpha = false;
uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D biomemap : filter_linear, repeat_disable;
uniform sampler2D splat0 : filter_linear, repeat_disable;
uniform sampler2D watermap : filter_nearest, repeat_disable;
uniform sampler2D block_mask : filter_nearest, repeat_disable;
uniform bool use_mask = false;
uniform sampler2D splat1 : filter_linear, repeat_disable;
uniform float spacing = 0.6;
uniform float side = 128.0;
uniform float fade_start = 30.0;
uniform float fade_end = 48.0;
uniform vec2 scale_range = vec2(0.35, 0.6);
uniform int kind = 0;
uniform float density = 1.0;
uniform float mesh_height = 1.3;
uniform float min_dist = 0.0;

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform vec3 player_pos;
global uniform vec3 cam_pos;
global uniform float snow_cover;

varying vec3 v_tint;
varying float v_dry;
varying float v_top;

const float HALF = 3072.0;

// integer hash: exact on every GPU (a sin() hash loses precision at world-scale coordinates
// and returns exactly 0 for some cells, which slipped blades past the density test)
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(round(p * 10.0)) + ivec2(1048576));
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u);
	h = h * 747796405u + 2891336453u;
	h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
	h = (h >> 22u) ^ h;
	return float(h) * (1.0 / 4294967296.0);
}
float hfetch(ivec2 p) { return texelFetch(heightmap, clamp(p, ivec2(0), ivec2(4095)), 0).r; }
float height_at(vec2 xz) {
	vec2 f = (xz + HALF) / 1.5;
	ivec2 i = ivec2(floor(f));
	vec2 t = fract(f);
	return mix(mix(hfetch(i), hfetch(i + ivec2(1, 0)), t.x), mix(hfetch(i + ivec2(0, 1)), hfetch(i + ivec2(1, 1)), t.x), t.y);
}
float wfetch(ivec2 p) { return texelFetch(watermap, clamp(p, ivec2(0), ivec2(1023)), 0).r; }
float water_at(vec2 xz) {
	vec2 f = (xz + HALF - 2.25) / 6.0;
	ivec2 i = ivec2(floor(f));
	vec2 t = fract(f);
	return mix(mix(wfetch(i), wfetch(i + ivec2(1, 0)), t.x), mix(wfetch(i + ivec2(0, 1)), wfetch(i + ivec2(1, 1)), t.x), t.y);
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec2 g = vec2(mod(id, side), floor(id / side)) - side * 0.5;
	vec2 snap = floor(cam_pos.xz / spacing) * spacing;
	vec2 p = snap + g * spacing;
	vec2 cell = floor(p / spacing + 0.5);
	float h1 = hash(cell);
	float h2 = hash(cell + 13.7);
	float h3 = hash(cell + 91.3);
	float h4 = hash(cell + 47.1);
	p += (vec2(h1, h2) - 0.5) * spacing * 0.95;
	vec2 muv = (p + HALF) / 6144.0;
	vec4 bio = texture(biomemap, muv);
	vec4 sp = texture(splat0, muv);
	float dens = bio.a * smoothstep(0.16, 0.3, bio.r) * (1.0 - 0.85 * smoothstep(0.34, 0.2, bio.r)) * (1.0 - snow_cover * 0.7);
	float patch = hash(floor(p / 9.0)) * 0.6 + hash(floor(p / 23.0 + 3.1)) * 0.4;
	if (kind == 1) { dens *= smoothstep(0.55, 0.85, patch) * 0.55 * smoothstep(0.35, 0.6, bio.r); }
	else if (kind == 2) { dens = min(sp.g * 0.9, bio.a * 2.0) * smoothstep(0.3, 0.6, patch + 0.2); }
	else if (kind == 3) { dens *= smoothstep(0.45, 0.75, patch) * 0.8; }
	// never inside buildings or castle grounds, never on paving (applies to every layer)
	if (use_mask) { dens *= texture(block_mask, muv).r; }
	float paved = sp.a + texture(splat1, muv).a;
	dens *= 1.0 - smoothstep(0.18, 0.5, paved);
	float d = distance(p, cam_pos.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	float keep = float(dens * density > h3) * step(min_dist, d);
	float y = height_at(p);
	if (water_at(p) > y - 0.08) { keep = 0.0; }
	float s = mix(scale_range.x, scale_range.y, h4) * keep * clamp(fade * 3.0, 0.0, 1.0);
	float a = h1 * 6.2831;
	vec3 v = VERTEX * s;
	v.xz = vec2(v.x * cos(a) - v.z * sin(a), v.x * sin(a) + v.z * cos(a));
	float top = clamp(VERTEX.y / mesh_height, 0.0, 1.0);
	v_top = top;
	float t = TIME * 1.7 + p.x * 0.17 + p.y * 0.11;
	vec2 w = wind_dir * (0.35 + 0.65 * sin(t) * sin(t * 0.37 + 1.0)) * (0.15 + wind_strength) * top * top * 0.45;
	vec2 away = p - player_pos.xz;
	float pd = length(away);
	if (pd < 1.3 && abs(player_pos.y - y) < 2.0) { w += normalize(away + 0.001) * (1.3 - pd) * 0.7 * top; }
	v.xz += w * max(s, 0.2) * step(0.0001, s) * 1.6;   // culled blades must stay collapsed
	v.y -= length(w) * 0.3 * s;
	VERTEX = vec3(p.x, y - 0.03, p.y) + v;
	NORMAL = normalize(mix(vec3(NORMAL.x * cos(a) - NORMAL.z * sin(a), NORMAL.y, NORMAL.x * sin(a) + NORMAL.z * cos(a)), vec3(0.0, 1.0, 0.0), 0.65));
	// biome tint: lush green -> golden dry -> cold olive
	vec3 lush = vec3(0.78, 1.0, 0.62);
	vec3 dry = vec3(1.18, 1.0, 0.55);
	vec3 cold = vec3(0.92, 0.9, 0.66);
	vec3 tint = mix(dry, lush, smoothstep(0.35, 0.7, bio.g));
	tint = mix(cold, tint, smoothstep(0.3, 0.5, bio.r));
	v_tint = tint * (0.85 + h2 * 0.3);
	v_dry = max(1.0 - smoothstep(0.25, 0.6, bio.g), smoothstep(0.42, 0.25, bio.r));
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	if (use_alpha) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	vec3 col = c.rgb * (kind == 1 ? vec3(1.0) : v_tint);
	if (kind != 1) { col = mix(col, vec3(0.58, 0.47, 0.25) * (0.8 + 0.4 * c.g), v_dry * 0.8); }
	col *= mix(0.55, 1.05, v_top);
	col = mix(col, vec3(0.9, 0.93, 0.97), clamp(snow_cover * 0.7 * v_top, 0.0, 0.8));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.35;
	AO = mix(0.6, 1.0, v_top);
	AO_LIGHT_AFFECT = 0.3;
}
