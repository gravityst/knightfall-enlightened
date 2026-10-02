shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;
// Camera-facing (cylindrical) tree billboards rendered from an atlas captured at load time.

uniform sampler2D atlas_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_normal : filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(8.0, 3.0);
uniform float fade_near = 95.0;   // impostors dither in from here (full-detail trees fade out)
uniform float fade_len = 40.0;

global uniform float snow_cover;

varying vec3 v_right;
varying vec3 v_tocam;
varying float v_fade;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_fade = smoothstep(fade_near, fade_near + fade_len, distance(CAMERA_POSITION_WORLD, origin));
	vec3 tc = CAMERA_POSITION_WORLD - origin;
	tc.y = 0.0;
	tc = normalize(tc + vec3(0.0001, 0.0, 0.0));
	vec3 right = normalize(vec3(tc.z, 0.0, -tc.x));
	float h = INSTANCE_CUSTOM.g;
	float w = INSTANCE_CUSTOM.b;
	vec3 wpos = origin + right * VERTEX.x * w + vec3(0.0, VERTEX.y * h, 0.0) - tc * w * 0.25;
	VERTEX = wpos - origin;
	if (v_fade <= 0.0) {
		VERTEX = vec3(0.0);   // near trees are drawn as meshes: collapse the card entirely
	}
	NORMAL = tc;
	float idx = INSTANCE_CUSTOM.r;
	vec2 cell = vec2(mod(idx, grid.x), floor(idx / grid.x));
	UV = (cell + vec2(UV.x, UV.y)) / grid;
	v_right = right;
	v_tocam = tc;
}

void fragment() {
	vec4 a = texture(atlas_albedo, UV);
	if (v_fade < 0.999 && fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) > v_fade) {
		discard;   // dithered cross-fade with the full-detail trees
	}
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	vec3 n = texture(atlas_normal, UV).rgb * 2.0 - 1.0;
	vec3 wn = normalize(v_right * n.x + vec3(0.0, 1.0, 0.0) * n.y + v_tocam * max(n.z, 0.15));
	ALBEDO = mix(a.rgb, vec3(0.9, 0.92, 0.95), clamp(snow_cover * 0.6 * smoothstep(0.3, 0.9, wn.y), 0.0, 0.7));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = a.rgb * 0.25;
}
