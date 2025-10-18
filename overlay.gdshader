shader_type canvas_item;

uniform int overlay_type : hint_enum("none", "velocity", "pressure", "divergence") = 0;
uniform float pressure_scale : hint_range(0, 2) = 0.5;
uniform sampler2D data;
uniform sampler2D gradient;


void fragment() {
	float velocity = length(texture(data,UV).xy);
	float pressure = texture(data, UV).z * pressure_scale;
	float divergence = texture(data, UV).w;

	switch(overlay_type) {
		case 1:
			COLOR = texture(gradient, vec2(velocity));
			break;
		case 2:
			COLOR = vec4(max(pressure, 0), abs(min(pressure, 0)), 0.0,1.0);;
			break;
		case 3:
			COLOR = vec4(max(divergence, 0), abs(min(divergence, 0)), 0.0,1.0);
			break;
		default:
			COLOR = vec4(0.0);
			break;
	};
}
