shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// --- world data ---------------------------------------------------------------
uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D normalmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D splat0 : filter_linear, repeat_disable;
uniform sampler2D splat1 : filter_linear, repeat_disable;
uniform sampler2D biomemap : filter_linear, repeat_disable;
uniform sampler2D watermap : filter_nearest, repeat_disable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sel_cam = vec3(0.0);
uniform float lod0_range = 90.0;

global uniform float wetness;
global uniform float snow_cover;
global uniform float daylight;

const float HALF = 3072.0;
const float TEXEL = 1.5;
const int RES = 4096;
const float WTEXEL = 6.0;
const int WRES = 1024;
const int NL = 13;

varying vec3 v_world;

float hfetch(ivec2 p) {
	return texelFetch(heightmap, clamp(p, ivec2(0), ivec2(RES - 1)), 0).r;
}

float height_at(vec2 xz) {
	vec2 f = (xz + HALF) / TEXEL;
	if (f.x < 0.0 || f.y < 0.0 || f.x > float(RES - 1) || f.y > float(RES - 1)) {
		return -60.0;
	}
	ivec2 i = ivec2(floor(f));
	vec2 t = fract(f);
	float a = mix(hfetch(i), hfetch(i + ivec2(1, 0)), t.x);
	float b = mix(hfetch(i + ivec2(0, 1)), hfetch(i + ivec2(1, 1)), t.x);
	return mix(a, b, t.y);
}

float wfetch(ivec2 p) {
	return texelFetch(watermap, clamp(p, ivec2(0), ivec2(WRES - 1)), 0).r;
}

float water_at(vec2 xz) {
	vec2 f = (xz + HALF - 2.25) / WTEXEL;
	ivec2 i = ivec2(floor(f));
	vec2 t = fract(f);
	float a = mix(wfetch(i), wfetch(i + ivec2(1, 0)), t.x);
	float b = mix(wfetch(i + ivec2(0, 1)), wfetch(i + ivec2(1, 1)), t.x);
	return mix(a, b, t.y);
}

void vertex() {
	float lod = INSTANCE_CUSTOM.r;
	float size = INSTANCE_CUSTOM.g;
	float grid = INSTANCE_CUSTOM.b;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 g = VERTEX.xz * grid;
	vec2 wp = origin.xz + VERTEX.xz * size;
	float h0 = height_at(wp);
	float rng = lod0_range * exp2(lod);
	float d = distance(vec3(wp.x, h0, wp.y), sel_cam);
	float m = clamp((d - rng * 0.8) / (rng * 0.2), 0.0, 1.0);
	g -= fract(g * 0.5) * 2.0 * m;
	wp = origin.xz + g / grid * size;
	float h = height_at(wp);
	v_world = vec3(wp.x, h, wp.y);
	VERTEX = v_world - origin;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

vec3 unpack_n(vec4 t) {
	vec2 xy = t.rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

float caustics(vec2 p, float t) {
	vec2 q = p * 0.35;
	float c = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		q += vec2(sin(q.y * 1.7 + t * 0.9 + fi), cos(q.x * 1.3 - t * 0.7 + fi * 1.7)) * 0.45;
		c += abs(sin(q.x + q.y + t * 0.5));
	}
	return pow(clamp(1.0 - c / 3.0, 0.0, 1.0), 6.0);
}

void fragment() {
	vec3 wp = v_world;
	vec2 muv = (wp.xz + HALF) / (TEXEL * float(RES));
	vec4 nt = texture(normalmap, muv);
	vec3 nw = normalize(vec3(nt.r * 2.0 - 1.0, nt.b, nt.g * 2.0 - 1.0));
	vec4 s0 = texture(splat0, muv);
	vec4 s1 = texture(splat1, muv);
	vec4 bio = texture(biomemap, muv);
	float biome_id = bio.b * 255.0 / 20.0;
	float slope = 1.0 - nw.y;
	float dist = length(wp - CAMERA_POSITION_WORLD);

	float macro = texture(macro_noise, wp.xz / 260.0).r;
	float macro2 = texture(macro_noise, wp.xz / 47.0 + 0.37).r;

	// --- layer weights -----------------------------------------------------
	float w[NL];
	w[0] = s0.r; w[1] = s0.g; w[2] = s0.b; w[3] = s0.a;
	w[4] = s1.r; w[5] = s1.g; w[6] = s1.b; w[7] = s1.a;
	w[8] = 0.0; w[9] = 0.0; w[10] = 0.0; w[11] = 0.0; w[12] = 0.0;
	// desert sand vs cracked earth, beach sand
	float beach = clamp(1.0 - abs(biome_id - 1.0), 0.0, 1.0) + clamp(1.0 - abs(biome_id), 0.0, 1.0);
	float crack = smoothstep(0.52, 0.66, macro2) * clamp(1.0 - abs(biome_id - 7.0), 0.0, 1.0);
	w[12] = w[6] * beach;
	w[11] = w[6] * (1.0 - beach) * crack;
	w[6] *= (1.0 - beach) * (1.0 - crack);
	// water edge: mud & pebbles
	float wl = water_at(wp.xz);
	float depth = wl - wp.y;
	float shore = smoothstep(-1.6, 0.1, depth) * step(0.5, wl + 50.0);
	float under = smoothstep(0.0, 1.2, depth);
	float lake_bed = under;
	float muddy = shore * (1.0 - under) * (1.0 - beach) * step(0.3, wl);
	for (int i = 0; i < 8; i++) { w[i] *= (1.0 - max(lake_bed, muddy * 0.8)); }
	w[10] += lake_bed * (wl > 0.5 ? 0.7 : 0.15);
	w[9] += lake_bed * (wl > 0.5 ? 0.3 : 0.0) + muddy * 0.8;
	w[12] += lake_bed * (wl > 0.5 ? 0.0 : 0.85);
	// cliffs by slope
	float cliff = smoothstep(0.30 + macro * 0.1, 0.48 + macro * 0.1, slope);
	for (int i = 0; i < NL; i++) { if (i != 8) { w[i] *= (1.0 - cliff); } }
	w[8] = cliff * (1.0 - under);
	w[4] += cliff * under;
	// dynamic snow
	float cold = smoothstep(0.55, 0.3, bio.r);
	float snowc = clamp(snow_cover * cold * smoothstep(0.55, 0.85, nw.y) * (1.0 - under) * (0.7 + macro), 0.0, 1.0);
	snowc = max(snowc, smoothstep(0.33, 0.17, bio.r) * smoothstep(0.45, 0.8, nw.y) * smoothstep(0.3, 0.6, macro + 0.2) * (1.0 - under));
	for (int i = 0; i < NL; i++) { if (i != 5) { w[i] *= (1.0 - snowc); } }
	w[5] += snowc;

	// --- sample & height blend --------------------------------------------
	float tile[NL] = float[](3.5, 4.0, 3.2, 3.0, 6.0, 6.0, 9.0, 2.8, 14.0, 4.0, 2.4, 5.0, 5.0);
	vec4 alb[NL];
	float best = 0.0;
	vec3 dpx = dFdx(wp);
	vec3 dpy = dFdy(wp);
	for (int i = 0; i < NL; i++) {
		alb[i] = vec4(0.0);
		if (w[i] > 0.015) {
			vec2 uv = wp.xz / tile[i];
			if (i == 8) {
				vec3 bw = pow(abs(nw), vec3(4.0));
				bw /= (bw.x + bw.y + bw.z);
				float it = 1.0 / tile[i];
				alb[i] = textureGrad(albedo_array, vec3(wp.zy * it, 8.0), dpx.zy * it, dpy.zy * it) * bw.x
					+ textureGrad(albedo_array, vec3(wp.xy * it, 8.0), dpx.xy * it, dpy.xy * it) * bw.z
					+ textureGrad(albedo_array, vec3(uv, 8.0), dpx.xz * it, dpy.xz * it) * bw.y;
				// the rock's strata repeat every tile: a second, larger and shifted sample on the steep
				// faces breaks the bands up across a mountainside
				float it2 = 1.0 / 41.0;
				vec4 big = textureGrad(albedo_array, vec3(wp.zy * it2 + 0.37, 8.0), dpx.zy * it2, dpy.zy * it2) * bw.x
					+ textureGrad(albedo_array, vec3(wp.xy * it2 + 0.61, 8.0), dpx.xy * it2, dpy.xy * it2) * bw.z;
				alb[i] = mix(alb[i], big + alb[i] * bw.y, (0.3 + macro2 * 0.4) * (1.0 - bw.y));
				// grey granite in the hills and mountains; the warm sandstone only in the desert
				float desert_rock = clamp(1.0 - abs(biome_id - 7.0), 0.0, 1.0) + beach;
				float lum = dot(alb[i].rgb, vec3(0.3, 0.59, 0.11));
				vec3 granite = vec3(lum) * vec3(0.9, 0.93, 1.0) * (0.86 + macro * 0.22);
				alb[i].rgb = mix(granite, alb[i].rgb, clamp(0.18 + desert_rock * 0.82, 0.0, 1.0));
			} else {
				float it = 1.0 / tile[i];
				alb[i] = textureGrad(albedo_array, vec3(uv, float(i)), dpx.xz * it, dpy.xz * it);
				if (dist > 45.0) {
					alb[i] = mix(alb[i], textureGrad(albedo_array, vec3(uv * 0.21 + 0.31, float(i)), dpx.xz * it * 0.21, dpy.xz * it * 0.21), smoothstep(45.0, 220.0, dist) * 0.55);
				}
			}
			best = max(best, w[i] + alb[i].a * 0.6);
		}
	}
	float hb[NL];
	float total = 0.0;
	for (int i = 0; i < NL; i++) {
		hb[i] = (w[i] > 0.015) ? max(w[i] + alb[i].a * 0.6 - best + 0.22, 0.0) : 0.0;
		total += hb[i];
	}
	vec3 col = vec3(0.0);
	vec3 nrm = vec3(0.0);
	float rough = 0.0;
	float ao = 0.0;
	for (int i = 0; i < NL; i++) {
		if (hb[i] > 0.0) {
			float k = hb[i] / total;
			col += alb[i].rgb * k;
			vec4 nt2;
			float it = 1.0 / tile[i];
			if (i == 8) {
				bool side_x = abs(nw.x) > abs(nw.z);
				vec2 uvc = nw.y > 0.75 ? wp.xz : (side_x ? wp.zy : wp.xy);
				vec2 gx = nw.y > 0.75 ? dpx.xz : (side_x ? dpx.zy : dpx.xy);
				vec2 gy = nw.y > 0.75 ? dpy.xz : (side_x ? dpy.zy : dpy.xy);
				nt2 = textureGrad(normal_array, vec3(uvc * it, 8.0), gx * it, gy * it);
			} else {
				nt2 = textureGrad(normal_array, vec3(wp.xz * it, float(i)), dpx.xz * it, dpy.xz * it);
			}
			nrm += unpack_n(nt2) * k;
			rough += nt2.b * k;
			ao += nt2.a * k;
		}
	}
	// --- tint & variation ------------------------------------------------
	float lush = clamp(bio.g * 1.3 - 0.1, 0.0, 1.0);
	vec3 grass_tint = mix(vec3(1.0, 1.0, 0.7), vec3(0.78, 1.0, 0.68), lush);
	col *= mix(vec3(1.0), grass_tint, (hb[0] + hb[2]) / max(total, 0.001));
	col *= 0.82 + macro * 0.36;
	// distant meadows read as grass rather than the soil between blades
	float grassiness = (hb[0] + hb[2] * 0.5 + hb[1] * 0.25) / max(total, 0.001);
	vec3 far_grass = mix(vec3(0.17, 0.2, 0.07), vec3(0.09, 0.17, 0.045), lush) * (0.75 + macro * 0.5);
	col = mix(col, far_grass, grassiness * smoothstep(12.0, 140.0, dist) * 0.72);
	// wetness
	float wet = clamp(max(wetness * smoothstep(0.4, 0.9, nw.y), shore * (1.0 - under) * 0.8), 0.0, 1.0);
	col *= mix(1.0, 0.62, wet);
	rough = mix(rough, 0.18, wet * 0.85);
	if (under > 0.0) {
		col *= mix(vec3(1.0), vec3(0.55, 0.72, 0.68), under);
		float c = caustics(wp.xz, TIME) * under * smoothstep(8.0, 0.5, depth) * daylight;
		EMISSION = vec3(0.55, 0.75, 0.7) * c * 0.6;
	}
	// --- normal: perturb the world normal with the layer normal (UDN) ---
	vec3 t = normalize(cross(nw, vec3(0.0, 0.0, 1.0)));
	vec3 b = cross(t, nw);
	vec3 n_world = normalize(t * nrm.x - b * nrm.y + nw * max(nrm.z, 0.3));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	AO = clamp(ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.4;
	SPECULAR = 0.3;
}
