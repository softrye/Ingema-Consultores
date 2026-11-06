#version 440
// GPU chroma key for the untouched 1280x720 H.264/AAC Gemini clip.
// The video is decoded by Qt Multimedia. This shader only masks green screen.
// Output is premultiplied RGBA, as required by Qt Quick ShaderEffect.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 pixel = texture(source, qt_TexCoord0);
    // Remove saturated greens (including the diagonal green streaks) without
    // destroying blue speech bubble, orange vest or white character.
    float excessGreen = pixel.g - max(pixel.r, pixel.b);
    float keyed = smoothstep(0.14, 0.38, excessGreen)
                * smoothstep(0.33, 0.55, pixel.g);
    float alpha = pixel.a * (1.0 - keyed) * qt_Opacity;
    vec3 rgb = pixel.rgb;
    rgb.g = mix(rgb.g, min(rgb.g, max(rgb.r, rgb.b) * 1.08), keyed * 0.82);
    fragColor = vec4(rgb * alpha, alpha);
}
