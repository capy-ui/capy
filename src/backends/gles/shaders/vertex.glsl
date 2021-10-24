attribute vec2 a_position;
/* uniform vec2 u_resolution;

void main() {
	vec2 zeroToOne = a_position / u_resolution;
	zeroToOne.y = 1.0 - zeroToOne.y;
	vec2 clipSpace = zeroToOne * 2.0 - 1.0;
	gl_Position = vec4(clipSpace, 0, 1);
}
 */

void main() {
	gl_Position = vec4(a_position, 0, 1);
}
