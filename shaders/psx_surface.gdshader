shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled, vertex_lighting;

global uniform bool psx_enabled;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool textured = true;
uniform bool generated_uv = false;
uniform float brightness = 1.0;
varying vec2 surface_uv;
uniform float jitter : hint_range(0.0, 1.0) = 0.32;
uniform float affine_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec2 virtual_resolution = vec2(426.0, 240.0);
uniform vec3 fog_color : source_color = vec3(0.055, 0.066, 0.079);
uniform float fog_start = 12.0;
uniform float fog_end = 34.0;
varying vec2 affine_uv;
varying float clip_w;
varying float fog_amount;

void vertex() {
 vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
 vec4 clip = PROJECTION_MATRIX * view;
 clip_w = max(abs(clip.w), 0.001);
 surface_uv = UV;
 if (generated_uv) {
  vec3 axis = abs(NORMAL);
  surface_uv = (axis.y > axis.x && axis.y > axis.z) ? VERTEX.xz : (axis.z > axis.x ? VERTEX.xy : VERTEX.yz);
  surface_uv = surface_uv * 1.5 + vec2(0.5);
 }
 affine_uv = surface_uv * clip_w;
 fog_amount = smoothstep(fog_start, fog_end, length(view.xyz));
 if (psx_enabled && clip.w > 0.0) {
  vec2 grid = virtual_resolution * 0.5;
  vec2 screen = clip.xy / clip.w;
  clip.xy = mix(screen, floor(screen * grid + 0.5) / grid, jitter) * clip.w;
 }
 POSITION = clip;
}
void fragment() {
 vec2 coord = psx_enabled ? mix(surface_uv, affine_uv / clip_w, affine_strength) : surface_uv;
 vec3 base = (textured ? texture(albedo_texture, coord).rgb : vec3(1.0)) * tint.rgb * brightness;
 ALBEDO = base * (1.0 - fog_amount);
 EMISSION = fog_color * fog_amount;
 ROUGHNESS = 1.0;
 SPECULAR = 0.0;
}
