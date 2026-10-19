shader_type canvas_item;
// The whole world at any zoom, from the full chart down to a ship's deck: land and sea from the
// chart image, every screen pixel the same size.
//
// The chart image holds land or sea (red), distance to the coast in kilometers (green) and
// depth (blue: shelf, past 200 meters, past 2,000). Zoomed out to a kilometer a pixel or more,
// pixels are read straight from it. Zoomed in, the coast is the zero line of a smooth signed
// distance blended smoothly (Catmull-Rom) between chart pixels with noise for coves and points: the same calculation
// as Chart.signed_distance in simulation/chart.gd, so ships run aground exactly where the
// coast is drawn. Change one, change both.

uniform sampler2D chart : filter_nearest;
// The world position of the screen's top-left pixel, split into whole kilometers and the meters
// past them, so it stays exact far across the chart.
uniform vec2 origin_kilometers;
uniform vec2 origin_meters;
uniform float meters_per_pixel = 1000.0;
uniform vec2 visible_size = vec2(640.0, 360.0);
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_strength = 1.0;
// Wave patterns are drawn in screen pixels from this offset, which follows the ship's motion
// through the water at real speed so the sea is readable even while the clock races.
uniform vec2 water_offset;
uniform float wave_time;

uniform vec4 deep_color : source_color;
uniform vec4 slope_color : source_color;
uniform vec4 water_color : source_color;
uniform vec4 swell_color : source_color;
uniform vec4 ripple_color : source_color;
uniform vec4 foam_color : source_color;
uniform vec4 crest_color : source_color;
uniform vec4 shallows_color : source_color;
uniform vec4 shallows_light_color : source_color;
uniform vec4 sand_color : source_color;
uniform vec4 grass_color : source_color;
uniform vec4 forest_color : source_color;
uniform vec4 forest_dark_color : source_color;
uniform vec4 highland_color : source_color;

float lattice(ivec2 cell) {
	uint hash_value = uint(cell.x) * 374761393u + uint(cell.y) * 668265263u;
	hash_value = (hash_value ^ (hash_value >> 13u)) * 1274126177u;
	hash_value = hash_value ^ (hash_value >> 16u);
	return float(hash_value & 16777215u) / 16777215.0;
}

float smooth_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = point - cell;
	vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
	ivec2 corner = ivec2(cell);
	return mix(
		mix(lattice(corner), lattice(corner + ivec2(1, 0)), blend.x),
		mix(lattice(corner + ivec2(0, 1)), lattice(corner + ivec2(1, 1)), blend.x),
		blend.y);
}

float coast_detail(vec2 chart_coordinate) {
	return (smooth_noise(chart_coordinate * 4.0) - 0.5) * 0.3
		+ (smooth_noise(chart_coordinate * 16.0) - 0.5) * 0.12
		+ (smooth_noise(chart_coordinate * 64.0) - 0.5) * 0.04;
}

float catmull_rom(float before, float start, float finish, float after, float weight) {
	float squared = weight * weight;
	return 0.5 * (
		2.0 * start
		+ (finish - before) * weight
		+ (2.0 * before - 5.0 * start + 4.0 * finish - after) * squared
		+ (3.0 * start - before - 3.0 * finish + after) * squared * weight);
}

vec4 texel(ivec2 pixel) {
	ivec2 size = textureSize(chart, 0);
	if (pixel.x < 0 || pixel.y < 0 || pixel.x >= size.x || pixel.y >= size.y) {
		// Off the chart: open, deep sea.
		return vec4(0.0, 1.0, 1.0, 1.0);
	}
	return texelFetch(chart, pixel, 0);
}

float texel_distance(ivec2 pixel) {
	vec4 data = texel(pixel);
	float distance = floor(data.g * 255.0 + 0.5) - 0.5;
	return data.r > 0.5 ? -distance : distance;
}

vec4 land_color(float inland, float bands, vec2 pattern, bool checker) {
	// inland is meters from the coast; bands is meters a pixel covers. Each band is its real
	// width, or one or two pixels when that's too narrow to see; never wider than that.
	float wander = (smooth_noise(pattern / 14000.0) - 0.5) * 16000.0;
	float speckle = lattice(ivec2(floor(pattern / max(bands, 1.0))));
	if (inland <= max(40.0, bands)) {
		return sand_color;
	} else if (inland <= max(400.0, 2.0 * bands) || (inland <= max(600.0, 3.0 * bands) && checker)) {
		return grass_color;
	} else if (inland + wander < 40000.0 || (inland + wander < 46000.0 && checker)) {
		return speckle > 0.88 ? forest_dark_color : forest_color;
	} else if (inland + wander < 80000.0 || (inland + wander < 88000.0 && checker)) {
		return speckle > 0.8 ? forest_color : forest_dark_color;
	}
	return speckle > 0.85 ? forest_dark_color : highland_color;
}

vec4 sea_color(float offshore, float depth, float bands, bool checker) {
	if (offshore <= max(15.0, bands)) {
		return foam_color;
	} else if (offshore <= max(150.0, 2.0 * bands)) {
		return shallows_light_color;
	} else if (offshore <= max(600.0, 3.0 * bands) || (offshore <= max(900.0, 4.0 * bands) && checker)) {
		return shallows_color;
	} else if (depth > 0.75) {
		return deep_color;
	} else if (depth > 0.25) {
		return slope_color;
	}
	return water_color;
}

void fragment() {
	vec2 screen = floor(UV * visible_size);
	bool checker = mod(screen.x + screen.y, 2.0) < 1.0;
	// Meters from the whole-kilometer origin; small enough to stay exact.
	vec2 local = origin_meters + screen * meters_per_pixel;
	vec2 chart_coordinate = origin_kilometers + local / 1000.0;

	bool land;
	float distance_meters;
	float depth;
	if (meters_per_pixel >= 1000.0) {
		vec4 data = texel(ivec2(floor(chart_coordinate)));
		land = data.r > 0.5;
		distance_meters = (floor(data.g * 255.0 + 0.5) - 0.5) * 1000.0;
		depth = data.b;
	} else {
		vec2 between = local / 1000.0 - 0.5;
		vec2 cell = floor(between);
		vec2 weight = between - cell;
		ivec2 corner = ivec2(origin_kilometers + cell);
		float rows[4];
		for (int row = 0; row < 4; row++) {
			rows[row] = catmull_rom(
				texel_distance(corner + ivec2(-1, row - 1)), texel_distance(corner + ivec2(0, row - 1)),
				texel_distance(corner + ivec2(1, row - 1)), texel_distance(corner + ivec2(2, row - 1)),
				weight.x);
		}
		float blended = catmull_rom(rows[0], rows[1], rows[2], rows[3], weight.y);
		float signed_distance = (blended + coast_detail(chart_coordinate)) * 1000.0;
		land = signed_distance < 0.0;
		distance_meters = abs(signed_distance);
		depth = texel(ivec2(floor(chart_coordinate))).b;
	}

	vec4 color;
	if (land) {
		color = land_color(distance_meters, meters_per_pixel, chart_coordinate * 1000.0, checker);
	} else {
		color = sea_color(distance_meters, depth, meters_per_pixel, checker);
		bool open_water = distance_meters > max(150.0, 2.0 * meters_per_pixel);
		if (open_water) {
			// Waves, drawn in screen pixels so they keep one look at every zoom. Crests lie across
			// the wind and creep downwind; long swell bands roll under them.
			vec2 water = screen + water_offset;
			vec2 across = vec2(-wind_direction.y, wind_direction.x);
			vec2 wave = vec2(dot(water, wind_direction), dot(water, across));
			if (meters_per_pixel < 50.0) {
				float swell = smooth_noise(vec2((wave.x - wave_time * 1.2) / 40.0, wave.y / 150.0));
				if (swell > 0.7 || (swell > 0.64 && checker)) {
					color = swell_color;
				}
			}
			float ripple = smooth_noise(vec2((wave.x - wave_time * 2.4) / 2.5, wave.y / 9.0));
			float scatter = smooth_noise(water / 23.0);
			float threshold = 0.92 - 0.04 * wind_strength;
			if (ripple > threshold && scatter > 0.55) {
				color = ripple_color;
				if (ripple > threshold + 0.06 && scatter > 0.75 && meters_per_pixel < 50.0) {
					color = crest_color;
				}
			}
		}
	}
	COLOR = color;
}
