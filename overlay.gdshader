shader_type canvas_item;

uniform int overlay_type : hint_enum("velocity", "pressure", "divergence") = 0;
uniform sampler2D data;
uniform sampler2D gradient;


void fragment() {
	float velocity = length(texture(data,UV).xy);
	float pressure = texture(data, UV).z;
	float divergence = texture(data, UV).w;

	switch(overlay_type) {
		case 0:
			COLOR = texture(gradient, vec2(velocity));
			break;
		case 1:
			COLOR = texture(gradient, vec2(pressure));
			break;
		case 2:
			COLOR = texture(gradient, vec2(divergence));
			break;
		default:
			COLOR = texture(gradient, vec2(velocity));
	};
}