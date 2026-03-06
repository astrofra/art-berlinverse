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

	float tl = luma(texture2D(s_tex, uv + vec2(-px.x, -px.y)).rgb);
	float tc = luma(texture2D(s_tex, uv + vec2(0.0,   -px.y)).rgb);
	float tr = luma(texture2D(s_tex, uv + vec2( px.x, -px.y)).rgb);
	float ml = luma(texture2D(s_tex, uv + vec2(-px.x,  0.0 )).rgb);
	float mr = luma(texture2D(s_tex, uv + vec2( px.x,  0.0 )).rgb);
	float bl = luma(texture2D(s_tex, uv + vec2(-px.x,  px.y)).rgb);
	float bc = luma(texture2D(s_tex, uv + vec2(0.0,    px.y)).rgb);
	float br = luma(texture2D(s_tex, uv + vec2( px.x,  px.y)).rgb);

	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
	float edge = sqrt(gx * gx + gy * gy);
	edge = smoothstep(0.12, 0.35, edge);

	float ghost = luma(texture2D(s_tex, uv).rgb) * 0.12;
	float scanline = 0.94 + 0.06 * sin(uv.y * 920.0);
	float intensity = clamp((edge + ghost) * scanline, 0.0, 1.0);

	gl_FragColor = vec4(color.rgb * intensity, 1.0);
}
