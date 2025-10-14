shader_type canvas_item;

uniform sampler2D data;
uniform sampler2D gradient;


void fragment() {
	float velocity = length(texture(data,UV).xy);
	float pressure = texture(data, UV).z;
	float divergence = texture(data, UV).w;
	//COLOR = vec4(0.0,0.0,pressure ,1.0);
	COLOR = texture(gradient, vec2(velocity));
}
