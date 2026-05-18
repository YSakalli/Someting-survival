shader_type canvas_item;

uniform float vignette_strength : hint_range(0.0, 2.0) = 0.85;
uniform float vignette_softness : hint_range(0.0, 1.5) = 0.45;
uniform vec3  vignette_color : source_color = vec3(0.0, 0.0, 0.0);

uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.004;

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.06;
uniform float scanline_count    : hint_range(50.0, 2000.0) = 720.0;

uniform float grain_strength : hint_range(0.0, 0.3) = 0.05;

uniform float saturation : hint_range(0.0, 2.0) = 1.18;
uniform float contrast   : hint_range(0.0, 2.0) = 1.08;
uniform vec3  tint : source_color = vec3(1.03, 1.0, 0.95);

uniform float bloom_strength  : hint_range(0.0, 1.5) = 0.35;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float bloom_radius    : hint_range(0.0, 0.02) = 0.004;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_linear_mipmap;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 apply_saturation(vec3 c, float s) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(l), c, s);
}

vec3 sample_bright(vec2 uv) {
	vec3 c = texture(SCREEN_TEXTURE, uv).rgb;
	float lum = max(max(c.r, c.g), c.b);
	float w = smoothstep(bloom_threshold, 1.0, lum);
	return c * w;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = uv - vec2(0.5);
	float dist = length(center);

	// Chromatic aberration — strength scales with distance from center
	vec2 dir = center;
	float ca = chromatic_aberration * dist * 2.0;
	float r = texture(SCREEN_TEXTURE, uv - dir * ca).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv + dir * ca).b;
	vec3 col = vec3(r, g, b);

	// Cheap 8-tap bloom
	vec3 bloom = vec3(0.0);
	float br = bloom_radius;
	bloom += sample_bright(uv + vec2( br,  0.0));
	bloom += sample_bright(uv + vec2(-br,  0.0));
	bloom += sample_bright(uv + vec2( 0.0,  br));
	bloom += sample_bright(uv + vec2( 0.0, -br));
	bloom += sample_bright(uv + vec2( br,  br) * 0.707);
	bloom += sample_bright(uv + vec2(-br,  br) * 0.707);
	bloom += sample_bright(uv + vec2( br, -br) * 0.707);
	bloom += sample_bright(uv + vec2(-br, -br) * 0.707);
	bloom *= 0.125;
	col += bloom * bloom_strength;

	// Color grading: contrast, tint, saturation
	col = (col - 0.5) * contrast + 0.5;
	col *= tint;
	col = apply_saturation(col, saturation);

	// Scanlines
	float scan = sin(uv.y * scanline_count * 3.14159) * 0.5 + 0.5;
	col *= mix(1.0, scan, scanline_strength);

	// Animated film grain
	float n = hash(uv + vec2(TIME * 0.37, TIME * 0.61));
	col += (n - 0.5) * grain_strength;

	// Vignette
	float vig = smoothstep(vignette_softness, vignette_softness + vignette_strength, dist);
	col = mix(col, vignette_color, vig);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
