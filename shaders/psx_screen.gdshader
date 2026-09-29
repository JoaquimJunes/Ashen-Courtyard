shader_type canvas_item;
// Bayer ordering adapted from snotbane/psx_visuals (Unlicense).
// Fixed virtual pixels keep dithering stable as the window changes size.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
global uniform bool psx_enabled;
uniform vec2 resolution = vec2(426.0, 240.0);
const float bayer[16] = float[](0.0,8.0,2.0,10.0,12.0,4.0,14.0,6.0,3.0,11.0,1.0,9.0,15.0,7.0,13.0,5.0);
void fragment() {
 vec2 pixel = floor(SCREEN_UV * resolution);
 vec2 uv = (pixel + 0.5) / resolution;
 vec3 color = texture(screen_tex, psx_enabled ? uv : SCREEN_UV).rgb;
 if (psx_enabled) {
  int index = int(mod(pixel.x, 4.0)) + int(mod(pixel.y, 4.0)) * 4;
  float dither = (bayer[index] / 16.0 - 0.5) * 0.65;
  color = clamp(floor(color * 31.0 + 0.5 + dither) / 31.0, 0.0, 1.0);
 }
 COLOR = vec4(color, 1.0);
}
