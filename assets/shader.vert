#version 460

layout(location = 0) in vec2 positions;
layout(location = 1) in vec3 colors;
layout(binding = 0) uniform UniformBufferObject {
  mat4 model;
  mat4 view;
  mat4 proj;
} ubo;

layout(location = 0) out vec3 frag_color;

void main() {
  gl_Position = ubo.proj * ubo.view * ubo.model * vec4(positions, 0.0, 1.0);
  frag_color = colors;
}
