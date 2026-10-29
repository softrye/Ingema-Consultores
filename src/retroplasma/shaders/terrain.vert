#version 450
layout(location=0) in vec3 position;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 uv;
layout(location=0) out vec2 texcoord;
layout(location=1) out vec3 surfaceNormal;
layout(std140,binding=0) uniform CameraBlock {mat4 mvp;vec4 light;};
void main(){gl_Position=mvp*vec4(position,1.0);texcoord=vec2(uv.x,1.0-uv.y);surfaceNormal=normal;}
