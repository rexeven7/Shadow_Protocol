// Full-screen post-process for the operative's goggles.
// mode 0 = normal (passthrough), 1 = night vision, 2 = thermal.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int mode = 0;
uniform float time_val = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	if (mode == 1) {
		// --- Night vision: amplify low light, green phosphor, grain + vignette ---
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		l = pow(clamp(l, 0.0, 1.0), 0.5) * 1.8 + 0.04;
		float n = (rand(SCREEN_UV * vec2(680.0, 380.0) + vec2(time_val)) - 0.5) * 0.14;
		float scan = 0.93 + 0.07 * sin(SCREEN_UV.y * 700.0);
		vec3 ndc = vec3(0.04, (l + n) * scan, 0.10);
		float d = distance(SCREEN_UV, vec2(0.5));
		ndc *= smoothstep(0.9, 0.32, d);
		COLOR = vec4(ndc, 1.0);
	} else if (mode == 2) {
		// --- Thermal: cool the cold world, let emissive (hot) bodies blaze ---
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		float brightest = max(max(col.r, col.g), col.b);
		float heat = smoothstep(0.5, 1.1, brightest);
		vec3 cold = vec3(0.02, 0.04 * l + 0.03, 0.16 + 0.30 * l);
		vec3 hot = mix(vec3(0.55, 0.0, 0.0), vec3(1.0, 1.0, 0.35), heat);
		COLOR = vec4(mix(cold, hot, heat), 1.0);
	} else {
		COLOR = vec4(col, 1.0);
	}
}
