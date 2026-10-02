shader_type sky;
render_mode use_debanding;

uniform vec3 rayleigh_color : source_color = vec3(0.26, 0.41, 0.58);
uniform float rayleigh = 2.0;
uniform vec3 mie_color : source_color = vec3(0.63, 0.77, 0.92);
uniform float mie = 0.005;
uniform float mie_eccentricity = 0.78;
uniform float turbidity = 9.0;
uniform vec3 ground_color : source_color = vec3(0.16, 0.14, 0.12);
uniform float exposure = 0.12;
uniform float cloud_coverage = 0.45;
uniform float cloud_darkness = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float star_rotation = 0.0;
uniform float moon_phase = 0.5;
uniform float haze = 0.0;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 night_color : source_color = vec3(0.004, 0.007, 0.018);

const float rayleigh_zenith_size = 8.4e3;
const float mie_zenith_size = 1.25e3;
const float SUN_ENERGY = 1000.0;

float hg(float c, float g) {
	return 0.0795774715 * (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * c, 1.5);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 atmosphere(vec3 dir, vec3 sun_dir, float sun_e, vec3 sun_col, float sun_size) {
	float zenith_angle = clamp(dot(vec3(0.0, 1.0, 0.0), sun_dir), -1.0, 1.0);
	float sun_energy = max(0.0, 1.0 - exp(-((PI * 0.5) - acos(zenith_angle)))) * SUN_ENERGY * sun_e;
	float sun_fade = 1.0 - clamp(1.0 - exp(sun_dir.y), 0.0, 1.0);
	float rc = rayleigh - (1.0 - sun_fade);
	vec3 rb = rc * rayleigh_color * 0.0001;
	vec3 mb = turbidity * mie * mie_color * 0.000434;
	float zenith = acos(max(0.0, dir.y));
	float om = 1.0 / (cos(zenith) + 0.15 * pow(93.885 - degrees(zenith), -1.253));
	vec3 ext = exp(-(rb * rayleigh_zenith_size * om + mb * mie_zenith_size * om));
	float ct = dot(dir, sun_dir);
	float rp = (3.0 / (16.0 * PI)) * (1.0 + pow(ct * 0.5 + 0.5, 2.0));
	vec3 bR = rb * rp;
	vec3 bM = mb * hg(ct, mie_eccentricity);
	vec3 lin = pow(sun_energy * ((bR + bM) / (rb + mb)) * (1.0 - ext), vec3(1.5));
	lin *= mix(vec3(1.0), pow(sun_energy * ((bR + bM) / (rb + mb)) * ext, vec3(0.5)), clamp(pow(1.0 - zenith_angle, 5.0), 0.0, 1.0));
	lin *= mix(ground_color, vec3(1.0), smoothstep(-0.1, 0.1, dir.y));
	float sd = smoothstep(cos(sun_size * 1.2), cos(sun_size * 0.8), ct);
	vec3 l0 = sun_energy * 1900.0 * ext * sd * sun_col;
	vec3 c = (lin + l0) * 0.04;
	c = pow(c, vec3(1.0 / (1.2 + 1.2 * sun_fade)));
	return c * exposure;
}

vec3 rotate_y(vec3 v, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun_dir = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : vec3(0.0, -1.0, 0.0);
	float day = smoothstep(-0.12, 0.08, sun_dir.y);
	vec3 col = atmosphere(dir, sun_dir, 1.0, LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0), LIGHT0_ENABLED ? LIGHT0_SIZE : 0.01);
	// night sky gradient
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 night = night_color * (0.6 + 0.8 * (1.0 - up)) + vec3(0.02, 0.025, 0.04) * pow(1.0 - up, 6.0);
	col += night * (1.0 - day);
	// stars & moon
	if (!AT_CUBEMAP_PASS && dir.y > -0.05) {
		vec3 sd = rotate_y(dir, star_rotation);
		vec3 sp = sd * 260.0;
		vec3 cell = floor(sp);
		float h = hash3(cell);
		if (h > 0.9965) {
			vec3 c = cell + 0.5 + (vec3(hash3(cell + 1.7), hash3(cell + 3.1), hash3(cell + 5.9)) - 0.5) * 0.6;
			float d = length(sp - c);
			float tw = 0.65 + 0.35 * sin(TIME * (2.0 + h * 7.0) + h * 100.0);
			float star = smoothstep(0.32, 0.0, d) * tw * (h - 0.9965) * 300.0;
			vec3 sc = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.85, 0.7), hash3(cell + 9.0));
			col += sc * star * (1.0 - day) * smoothstep(-0.05, 0.25, dir.y) * (1.0 - cloud_coverage * 0.9);
		}
		// milky band
		float band = exp(-pow(dot(sd, normalize(vec3(0.3, 0.2, 1.0))) * 3.2, 2.0));
		col += vec3(0.05, 0.05, 0.08) * band * (1.0 - day) * (0.6 + 0.4 * texture(cloud_noise, sd.xz * 2.0).r) * 0.35;
		// moon
		float md = dot(dir, normalize(moon_dir));
		float msize = 0.0095;
		if (md > cos(msize * 1.6)) {
			vec3 mdn = normalize(moon_dir);
			vec3 mx = normalize(cross(mdn, vec3(0.0, 1.0, 0.0)));
			vec3 my = cross(mx, mdn);
			vec2 p = vec2(dot(dir - mdn, mx), dot(dir - mdn, my)) / msize;
			float r2 = dot(p, p);
			if (r2 < 1.0) {
				vec3 sph = vec3(p, sqrt(1.0 - r2));
				float ph = moon_phase * 2.0 * PI;
				vec3 ld = normalize(vec3(sin(ph), 0.0, -cos(ph)));
				float lit = smoothstep(-0.05, 0.1, dot(sph, ld));
				float maria = texture(cloud_noise, p * 0.35 + 0.2).r;
				vec3 mc = vec3(0.95, 0.93, 0.88) * (0.75 + 0.35 * maria) * (lit * 1.6 + 0.04);
				col = mix(col, mc, smoothstep(1.0, 0.92, r2) * (0.35 + 0.65 * (1.0 - day * 0.8)));
			}
			col += vec3(0.6, 0.65, 0.75) * pow(max(md, 0.0), 900.0) * 0.4 * (1.0 - day);
		}
	}
	// clouds (single slab projected on a dome)
	if (dir.y > 0.0) {
		vec2 cuv = dir.xz / (dir.y + 0.12) * 0.55 + cloud_offset;
		float n = texture(cloud_noise, cuv * 0.6).r * 0.62 + texture(cloud_noise, cuv * 1.7 + 0.3).r * 0.28;
		if (!AT_CUBEMAP_PASS) { n += texture(cloud_noise, cuv * 4.3 - 0.7).r * 0.1; }
		float cov = mix(0.72, 0.18, cloud_coverage);
		float dens = smoothstep(cov, cov + 0.22, n) * smoothstep(0.0, 0.18, dir.y);
		if (dens > 0.001) {
			float sunf = max(sun_dir.y + 0.1, 0.0);
			float fw = pow(max(dot(dir, sun_dir), 0.0), 6.0);
			vec3 sun_tint = mix(vec3(1.0, 0.55, 0.35), vec3(1.0), smoothstep(0.0, 0.35, sun_dir.y));
			vec3 lightc = sun_tint * (0.55 + 0.45 * sunf) * day + vec3(0.018, 0.022, 0.032) * (1.0 - day);
			float shade = mix(1.0, 0.45, smoothstep(0.4, 1.0, n)) * mix(1.0, 0.32, cloud_darkness);
			vec3 cc = lightc * shade * (1.0 + fw * 1.4 * (1.0 - dens));
			cc = mix(cc, col, smoothstep(0.25, 0.0, dir.y) * 0.5);
			col = mix(col, cc * mix(1.0, 0.8, cloud_coverage), dens * mix(0.85, 1.0, cloud_coverage));
		}
	}
	// overcast / haze flattening
	vec3 grey = vec3(dot(col, vec3(0.3, 0.5, 0.2)));
	col = mix(col, grey * mix(0.9, 0.55, cloud_darkness), clamp(haze, 0.0, 1.0) * 0.75);
	if (dir.y < 0.0) {
		col = mix(col, ground_color * (0.05 + 0.6 * day), smoothstep(0.0, -0.3, dir.y));
	}
	COLOR = col;
}
