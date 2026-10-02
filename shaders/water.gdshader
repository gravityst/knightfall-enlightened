shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D watermap : filter_nearest, repeat_disable;
uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D flowmap : filter_linear, repeat_disable;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 sel_cam = vec3(0.0);
uniform float lod0_range = 90.0;
uniform bool ring = false;
uniform int ssr_steps = 24;
uniform vec3 deep_color : source_color = vec3(0.015, 0.07, 0.085);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.30, 0.27);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wetness;
global uniform float daylight;

const float HALF = 3072.0;
const float TEXEL = 1.5;
const int RES = 4096;
const float WTEXEL = 6.0;
const int WRES = 1024;

varying vec3 v_world;
varying float v_ocean;
varying float v_crest;

float wfetch(ivec2 p) { return texelFetch(watermap, clamp(p, ivec2(0), ivec2(WRES - 1)), 0).r; }
float water_at(vec2 xz) {
	vec2 f = (xz + HALF - 2.25) / WTEXEL;
	if (f.x < 0.0 || f.y < 0.0 || f.x > float(WRES - 1) || f.y > float(WRES - 1)) return 0.0;
	ivec2 i = ivec2(floor(f));
	vec2 t = fract(f);
	return mix(mix(wfetch(i), wfetch(i + ivec2(1, 0)), t.x), mix(wfetch(i + ivec2(0, 1)), wfetch(i + ivec2(1, 1)), t.x), t.y);
}
float hfetch(ivec2 p) { return texelFetch(heightmap, clamp(p, ivec2(0), ivec2(RES - 1)), 0).r; }
float terrain_at(vec2 xz) {
	vec2 f = (xz + HALF) / TEXEL;
	if (f.x < 0.0 || f.y < 0.0 || f.x > float(RES - 1) || f.y > float(RES - 1)) return -60.0;
	ivec2 i = ivec2(floor(f));
	vec2 t = fract(f);
	return mix(mix(hfetch(i), hfetch(i + ivec2(1, 0)), t.x), mix(hfetch(i + ivec2(0, 1)), hfetch(i + ivec2(1, 1)), t.x), t.y);
}

vec3 gerstner(vec2 p, vec2 dir, float wl, float amp, float steep, float t, inout vec3 tangent, inout vec3 binormal) {
	float k = 6.28318 / wl;
	float c = sqrt(9.81 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = amp;
	float q = steep / (k * a * 4.0 + 0.0001);
	tangent += vec3(-d.x * d.x * (q * a * k * sin(f)), d.x * (a * k * cos(f)), -d.x * d.y * (q * a * k * sin(f)));
	binormal += vec3(-d.x * d.y * (q * a * k * sin(f)), d.y * (a * k * cos(f)), -d.y * d.y * (q * a * k * sin(f)));
	return vec3(q * a * d.x * cos(f), a * sin(f), q * a * d.y * cos(f));
}

void vertex() {
	vec2 wp;
	if (ring) {
		wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	} else {
		float lod = INSTANCE_CUSTOM.r;
		float size = INSTANCE_CUSTOM.g;
		float grid = INSTANCE_CUSTOM.b;
		vec2 g = VERTEX.xz * grid;
		wp = MODEL_MATRIX[3].xz + VERTEX.xz * size;
		float rng = lod0_range * exp2(lod);
		float d = distance(vec3(wp.x, water_at(wp), wp.y), sel_cam);
		float m = clamp((d - rng * 0.8) / (rng * 0.2), 0.0, 1.0);
		g -= fract(g * 0.5) * 2.0 * m;
		wp = MODEL_MATRIX[3].xz + g / grid * size;
	}
	float level = ring ? 0.0 : water_at(wp);
	float ground = ring ? -80.0 : terrain_at(wp);
	float ocean = (level < 0.6) ? smoothstep(1.0, 14.0, level - ground) : 0.0;
	v_ocean = ocean;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);
	float amp = ocean * (0.25 + wind_strength * 0.9);
	float camd = length(vec3(wp.x, level, wp.y) - sel_cam);
	amp *= 1.0 - smoothstep(600.0, 2500.0, camd);
	if (amp > 0.001) {
		vec2 wd = normalize(wind_dir + vec2(0.0001));
		disp += gerstner(wp, wd, 38.0, 0.55 * amp, 0.55, TIME, tangent, binormal);
		disp += gerstner(wp, vec2(wd.y, -wd.x) * 0.6 + wd, 21.0, 0.32 * amp, 0.5, TIME * 1.07, tangent, binormal);
		disp += gerstner(wp, vec2(-wd.y, wd.x) * 0.4 + wd, 11.0, 0.16 * amp, 0.45, TIME * 1.13, tangent, binormal);
		disp += gerstner(wp, wd + vec2(0.3, 0.7), 6.3, 0.08 * amp, 0.4, TIME * 1.21, tangent, binormal);
	}
	v_crest = clamp(disp.y / max(amp, 0.05) * 0.9, 0.0, 1.0) * ocean;
	v_world = vec3(wp.x + disp.x, level + disp.y, wp.y + disp.z);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(v_world, 1.0)).xyz;
	NORMAL = normalize(cross(binormal, tangent));
}

vec3 linear_view(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

float ripple(vec2 p, float t) {
	vec2 cell = floor(p);
	float r = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			float h = fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
			vec2 center = c + vec2(fract(h * 7.31), fract(h * 3.17));
			float phase = fract(t * 0.9 + h);
			float d = length(p - center);
			float rr = d - phase * 0.9;
			r += sin(rr * 30.0) * (1.0 - phase) * smoothstep(0.12, 0.0, abs(rr));
		}
	}
	return r;
}

void fragment() {
	vec3 wp = v_world;
	vec2 muv = (wp.xz + HALF) / 6144.0;
	vec4 fl = ring ? vec4(0.5, 0.5, 0.0, 0.0) : texture(flowmap, clamp(muv, 0.0, 1.0));
	vec2 flow = (fl.rg - 0.5) * 2.0;
	float speed = length(flow);
	// two-phase flow mapping for rivers, wind drift for lakes/ocean
	vec2 drift = wind_dir * (0.02 + wind_strength * 0.05);
	float ph0 = fract(TIME * 0.25);
	float ph1 = fract(TIME * 0.25 + 0.5);
	float fw = abs(ph0 - 0.5) * 2.0;
	vec2 fv = flow * 1.6;
	vec2 uv1 = wp.xz / 9.0;
	vec3 na = mix(texture(normal_a, uv1 - fv * ph0 + drift * TIME).rgb, texture(normal_a, uv1 - fv * ph1 + drift * TIME + 0.5).rgb, fw);
	vec3 nb = texture(normal_b, wp.xz / 23.0 + vec2(drift.y, -drift.x) * TIME * 0.7).rgb;
	vec3 n1 = na * 2.0 - 1.0;
	vec3 n2 = nb * 2.0 - 1.0;
	vec3 tn = normalize(vec3(n1.xy * (0.55 + speed * 0.6) + n2.xy * (0.35 + wind_strength * 0.6 + v_ocean * 0.4), 1.0));
	if (wetness > 0.05) {
		float r = ripple(wp.xz * 1.3, TIME) * wetness;
		tn.xy += vec2(dFdx(r), dFdy(r)) * 0.6;
	}
	vec3 base_n = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 vn = normalize(NORMAL);
	vec3 T = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 B = normalize((VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 N = normalize(vn * tn.z + T * tn.x - B * tn.y);
	if (!FRONT_FACING) { N = -N; }

	// depth / refraction
	vec3 surf_view = VERTEX;
	vec2 suv = SCREEN_UV;
	vec2 offs = (N.xz - base_n.xz) * 0.045;
	vec2 ruv = clamp(suv + offs, vec2(0.001), vec2(0.999));
	vec3 scene_v = linear_view(ruv, INV_PROJECTION_MATRIX);
	if (scene_v.z > surf_view.z) {   // refracted sample is in front of the water: use undistorted
		ruv = suv;
		scene_v = linear_view(suv, INV_PROJECTION_MATRIX);
	}
	float thick = max(length(scene_v) - length(surf_view), 0.0);
	vec3 refr = texture(screen_tex, ruv).rgb;
	float murk = 1.0 - exp(-thick * (0.16 + speed * 0.08));
	vec3 absorb = exp(-thick * vec3(0.45, 0.12, 0.09));
	vec3 water_col = mix(shallow_color, deep_color, smoothstep(0.0, 9.0, thick)) * (0.25 + daylight * 0.75);
	vec3 body = mix(refr * absorb, water_col, murk);

	// screen-space reflection
	vec3 V = normalize(-surf_view);
	vec3 R = reflect(-V, N);
	vec3 refl = vec3(0.0);
	float hit = 0.0;
	if (FRONT_FACING && R.z < 0.2) {
		vec3 p = surf_view;
		float stp = 0.6 + length(surf_view) * 0.015;
		for (int i = 0; i < ssr_steps; i++) {
			p += R * stp;
			stp *= 1.18;
			vec4 cp = PROJECTION_MATRIX * vec4(p, 1.0);
			vec2 uv = cp.xy / cp.w * 0.5 + 0.5;
			if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || cp.w < 0.0) { break; }
			vec3 sv = linear_view(uv, INV_PROJECTION_MATRIX);
			float dz = sv.z - p.z;
			if (dz > 0.0 && dz < stp * 2.5 + 0.5) {
				vec2 e = smoothstep(vec2(0.0), vec2(0.12), uv) * smoothstep(vec2(1.0), vec2(0.88), uv);
				hit = e.x * e.y * (1.0 - float(i) / float(ssr_steps));
				refl = texture(screen_tex, uv).rgb;
				break;
			}
		}
	}
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 5.0);
	// foam
	float foam_n = texture(foam_noise, wp.xz / 6.0 + flow * TIME * 0.3).r;
	float shore_foam = smoothstep(0.9, 0.0, thick) * smoothstep(0.35, 0.75, foam_n + 0.3 * sin(TIME * 1.3 + wp.x * 0.2));
	float river_foam = fl.b * smoothstep(0.45, 0.8, foam_n);
	float crest_foam = smoothstep(0.55, 0.95, v_crest) * smoothstep(0.4, 0.7, foam_n);
	float foam = clamp(shore_foam * (0.4 + v_ocean * 0.6) + river_foam + crest_foam, 0.0, 1.0);

	vec3 col = mix(body, refl, fres * hit);
	col = mix(col, foam_color * (0.3 + daylight * 0.7), foam * 0.85);
	if (!FRONT_FACING) {
		col = refr * vec3(0.5, 0.75, 0.75) + water_col * 0.4;
	}
	ALBEDO = vec3(0.0);
	EMISSION = col;
	NORMAL = N;
	ROUGHNESS = mix(0.03, 0.6, foam);
	SPECULAR = mix(0.5, 0.15, hit) * (1.0 - foam);
	METALLIC = 0.0;
	ALPHA = clamp(smoothstep(0.0, 0.25, thick) + foam, 0.0, 1.0);
}
