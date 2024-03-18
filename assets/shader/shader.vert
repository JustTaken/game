#version 460

layout(location = 0) in vec3 positions;
layout(location = 1) in vec3 colors;

layout(location = 0) out vec4 frag_color;

layout(set = 0, binding = 0) uniform UniformGlobalObject {
  mat4 view;
  mat4 proj;
} ugo;

layout(set = 1, binding = 0) uniform UniformModelObject {
  mat4 model;
  mat4 color;
} umo;

void main() {
  gl_Position = ugo.proj * ugo.view * umo.model * vec4(positions, 1.0);
  frag_color = umo.color * vec4(colors, 1.0);
}
