shader_type sky;
// A night sky in the stage's colours: a deep top, a glow at the horizon, square pixel stars
// and a big moon where the light comes from.

uniform vec3 top_color : source_color = vec3(0.07, 0.05, 0.18);
uniform vec3 horizon_color : source_color = vec3(0.6, 0.3, 0.55);
uniform vec3 moon_color : source_color = vec3(1.0, 0.95, 0.82);
uniform vec3 moon_dir = vec3(0.0, 0.5, 0.86);
uniform float moon_size = 0.085;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = max(dir.y, 0.0);
	float low = pow(1.0 - up, 5.0);
	vec3 color = mix(top_color, horizon_color, low);
	if (dir.y < 0.0) {
		color = mix(horizon_color, top_color * 0.4, clamp(-dir.y * 5.0, 0.0, 1.0));
	}
	// stars: a grid wrapped round the sky, one star in a few of its cells
	vec2 grid = vec2(atan(dir.x, dir.z), asin(clamp(dir.y, -1.0, 1.0))) * 70.0;
	vec2 cell = floor(grid);
	vec2 inside = abs(fract(grid) - 0.5);
	float seed = hash(cell);
	float size = 0.1 + 0.16 * hash(cell + 7.3);
	float star = step(0.975, seed) * step(max(inside.x, inside.y), size) * step(0.03, dir.y);
	color += star * (1.0 - low) * vec3(1.0, 0.95, 0.88) * (0.5 + 0.5 * hash(cell + 1.9));
	// the moon, with a bite out of it and a soft glow
	vec3 moon = normalize(moon_dir);
	float away = distance(dir, moon);
	float bite = distance(dir, normalize(moon + vec3(0.035, 0.03, 0.0)));
	float disc = step(away, moon_size) * step(moon_size * 0.92, bite);
	color += moon_color * 0.3 * exp(-away * 7.0);
	color = mix(color, moon_color, disc);
	COLOR = color;
}
