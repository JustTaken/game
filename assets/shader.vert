#version 460

layout(location = 0) in vec2 positions;
layout(location = 1) in vec3 colors;

layout(set = 0, binding = 0, offset = 0) uniform UniformGlobalObject {
  mat4 proj;
  mta4 view;
} ugo;

layout(set = 0, binding = 0, offset = 128) uniform UniformModelObject {
  mat4 model;
} umo;

layout(location = 0) out vec3 frag_color;

void main() {
  gl_Position = ugo.proj * ugo.view * umo.model * vec4(positions, 0.0, 1.0);
  frag_color = colors;
}
