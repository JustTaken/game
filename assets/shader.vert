#version 460

layout(location = 0) in vec2 positions;
layout(location = 1) in vec3 colors;

layout(set = 0, binding = 0) uniform UniformGlobalObject {
    mat4 proj;
    mat4 view;
} ugo;

layout(set = 0, binding = 1) uniform UniformModelObject {
    mat4 scale;
    mat4 rotation;
    mat4 translation;
} umo;

layout(location = 0) out vec3 frag_color;

void main() {
    mat4 model = umo.scale * umo.rotation * umo.translation;
    gl_Position = ugo.proj * ugo.view * model * vec4(positions, 0.0, 1.0);
    frag_color = colors;
}
