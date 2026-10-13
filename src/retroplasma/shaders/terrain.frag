#version 450
layout(location=0) in vec2 texcoord;
layout(location=1) in vec3 surfaceNormal;
layout(location=0) out vec4 color;
layout(std140,binding=0) uniform CameraBlock {mat4 mvp;vec4 light;};
layout(binding=1) uniform sampler2D terrainTexture;
void main(){vec4 albedo=texture(terrainTexture,texcoord);float diffuse=0.4+0.6*max(dot(normalize(surfaceNormal),normalize(light.xyz)),0.0);color=vec4(albedo.rgb*diffuse,albedo.a);}
