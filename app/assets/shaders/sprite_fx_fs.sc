$input v_texcoord0

#include <bgfx_shader.sh>

uniform vec4 color;
uniform vec4 texel_size;

SAMPLER2D(s_tex, 0);

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void main() {
	vec2 uv = v_texcoord0;
	vec2 px = max(texel_size.xy, vec2(1e-5, 1e-5));

	// Fast contour mode: 5 taps total (center + 4-neighbors) instead of full Sobel 9 taps.
	float c = luma(texture2D(s_tex, uv).rgb);
	float l = luma(texture2D(s_tex, uv + vec2(-px.x, 0.0)).rgb);
	float r = luma(texture2D(s_tex, uv + vec2( px.x, 0.0)).rgb);
	float u = luma(texture2D(s_tex, uv + vec2(0.0, -px.y)).rgb);
	float d = luma(texture2D(s_tex, uv + vec2(0.0,  px.y)).rgb);

	float gx = r - l;
	float gy = d - u;
	float edge = abs(gx) + abs(gy);
	edge = smoothstep(0.08, 0.28, edge);

	float ghost = c * 0.10;
	float scanline = 0.94 + 0.06 * sin(uv.y * 920.0);
	float intensity = clamp((edge + ghost) * scanline, 0.0, 1.0);

	gl_FragColor = vec4(mix(color.rgb * intensity, vec3(c*0.25,c,c*0.25), 0.15), 1.0);
}
