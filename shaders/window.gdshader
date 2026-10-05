shader_type spatial;
// A window pane that follows the day: from outside, dark by day and candle-lit at night; from
// inside (night_glow 0), daylight through the glass that fades out after dusk.

global uniform float daylight;
uniform vec3 base_color : source_color = vec3(0.025, 0.022, 0.02);
uniform vec3 glow_color : source_color = vec3(1.0, 0.6, 0.28);
uniform float night_glow = 1.6;
uniform float day_glow = 0.0;

void fragment() {
	ALBEDO = base_color;
	ROUGHNESS = 0.5;
	EMISSION = glow_color * mix(night_glow, day_glow, smoothstep(0.08, 0.3, daylight));
}
