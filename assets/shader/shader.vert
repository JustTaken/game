#version 460

layout(location = 0) in vec3 positions;
layout(location = 1) in vec3 colors;
layout(location = 2) in vec2 texture_coords;

layout(location = 0) out vec4 frag_color;
layout(location = 1) out vec2 frag_texture_coords;

layout(set = 0, binding = 0) uniform UniformGlobalObject {
  mat4 view;
  mat4 proj;
} ugo;

layout(set = 2, binding = 0) uniform UniformModelObject {
  mat4 model;
  mat4 color;
} umo;

void main() {
  gl_Position = ugo.proj * ugo.view * umo.model * vec4(positions, 1.0);
  frag_color = umo.color * vec4(colors, 1.0);
  frag_texture_coords = texture_coords;
}
