shader_type spatial;
// The ground and rock of a stage, drawn as chunky pixel art to sit with the sprites: the
// surface is cut into square "pixels" in world space, shaded in a few flat tones from
// blotchy noise, with flecks of the stage's accent colour on top faces and strata on the
// sides. Nothing is sampled from a texture.

uniform vec3 base_color : source_color = vec3(0.2, 0.17, 0.26);
uniform vec3 accent_color : source_color = vec3(0.9, 0.5, 0.25);
// Metres to a pixel.
uniform float texel = 0.2;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float blotch(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 n = abs(world_normal);
	bool top = n.y > 0.6;
	vec2 uv = top ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	vec2 cell = floor(uv / texel);
	// far away the pixels are smaller than the screen's: fade the speckle so it does not crawl
	float near = clamp(1.0 - length(VERTEX) / 60.0, 0.0, 1.0);
	float grain = mix(0.5, hash(cell), near);
	float wide = blotch(cell * texel / 9.0);
	float fine = blotch(cell * texel / 2.2 + 17.0);
	float tone = floor((wide * 0.6 + fine * 0.4) * 4.0 + grain * 0.9) / 4.0;
	vec3 color = base_color * (0.74 + tone * 0.5);
	if (top) {
		float fleck = step(0.988, hash(cell + 31.7)) * near;
		color = mix(color, accent_color * 0.85, fleck * 0.45);
		color = mix(color, accent_color, smoothstep(0.6, 0.9, wide) * 0.1);
	} else {
		float band = floor(world_pos.y / (texel * 4.0));
		color *= 0.78 + 0.2 * hash(vec2(band, 3.0));
		float crack = step(0.93, hash(vec2(floor(cell.x / 3.0), band))) * near;
		color *= 1.0 - crack * 0.25;
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
}
