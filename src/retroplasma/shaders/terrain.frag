#version 450
layout(location=0) in vec2 texcoord;
layout(location=1) in vec3 surfaceNormal;
layout(location=0) out vec4 color;
layout(std140,binding=0) uniform CameraBlock {mat4 mvp;vec4 light;};
layout(binding=1) uniform sampler2D terrainTexture;
void main(){
    vec4 albedo=texture(terrainTexture,texcoord);if(albedo.a<0.5)discard;
    float facing=max(dot(normalize(surfaceNormal),normalize(light.xyz)),0.0);
    vec3 lit=albedo.rgb*(0.4+0.6*facing);
    // Globo (light.w=1, luz = dirección al ojo): atmósfera azul en el limbo (fresnel).
    float rim=light.w*pow(1.0-facing,3.0);
    lit=mix(lit,vec3(0.36,0.62,1.0),rim*0.70)+vec3(0.06,0.14,0.32)*rim;
    color=vec4(lit,albedo.a);
}
