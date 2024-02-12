#version 460

layout(location = 0) in vec2 position;
layout(location = 1) in vec3 colors;

layout(location = 0) out vec3 frag_color;

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    frag_color = colors;
}
