shader_type spatial;
// Greybox material: a 1 m grid with a bolder line every 5 m, drawn in the block's own space
// so you can judge speed, jump height and distance at a glance.

uniform vec3 base_color : source_color = vec3(0.2, 0.17, 0.26);
uniform vec3 line_color : source_color = vec3(0.9, 0.5, 0.25);

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float grid(vec2 uv) {
	vec2 lines = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
	return 1.0 - min(min(lines.x, lines.y), 1.0);
}

void fragment() {
	vec3 n = abs(local_normal);
	vec2 uv = n.y > 0.5 ? local_pos.xz : (n.x > 0.5 ? local_pos.zy : local_pos.xy);
	float fade = clamp(1.0 - length(VERTEX) / 90.0, 0.0, 1.0);
	float lines = max(grid(uv) * 0.25, grid(uv / 5.0) * 0.7) * fade;
	ALBEDO = mix(base_color, line_color, lines);
	ROUGHNESS = 1.0;
}
