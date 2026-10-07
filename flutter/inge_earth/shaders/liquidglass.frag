#version 460 core
// InGe+ Liquid Glass — port 1:1 para Flutter del material del Dock:
//   qml/Mobile/shaders/liquidglass.frag (GlobalContextDock.qml / GlassSurface).
// Mismo algoritmo, mismos uniforms y mismas constantes: SDF de caja redondeada,
// normal de bisel desde el gradiente del SDF, recogida refractiva hacia el
// borde, frost en ángulo áureo, saturación, tint y borde fresnel direccional.
// Origen del algoritmo: liquid-glass-bottom-nav-bar (MIT, A. B. Ozyurt).
// Cualquier cambio de material se hace en AMBOS archivos a la vez.
//
// Única diferencia de plataforma: Qt entrega una captura exacta del ítem +
// margen; aquí se muestrea la captura compartida del fondo Auth a través de
// `sourceRect` (rectángulo UV del ítem + margen dentro de esa captura).

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 itemSize;       // 0-1
uniform float margin;        // 2
uniform float radius;        // 3
uniform float thickness;     // 4
uniform float refraction;    // 5
uniform float frost;         // 6
uniform float rimLight;      // 7
uniform float rimShade;      // 8
uniform float rimSheen;      // 9
uniform float saturation;    // 10
uniform float backdropMix;   // 11
uniform float magnify;       // 12
uniform float edgeContrast;  // 13
uniform float taps;          // 14  frost samples, 1..12
uniform vec4 tint;           // 15-18
uniform vec4 fallbackColor;  // 19-22
uniform vec4 sourceRect;     // 23-26 (u, v, w, h) en la captura compartida
uniform float opacity;       // 27  equivalente a qt_Opacity

uniform sampler2D source;

out vec4 fragColor;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

float sdRoundedBox(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float sceneSDF(vec2 p)
{
    return sdRoundedBox(p - itemSize * 0.5, itemSize * 0.5, radius);
}

vec2 sceneGrad(vec2 p)
{
    const float e = 0.75;
    float dx = sceneSDF(p + vec2(e, 0.0)) - sceneSDF(p - vec2(e, 0.0));
    float dy = sceneSDF(p + vec2(0.0, e)) - sceneSDF(p - vec2(0.0, e));
    return normalize(vec2(dx, dy) + vec2(1.0e-6));
}

vec3 glassNormal(float sd, vec2 grad, float depth)
{
    float t = clamp(-sd / max(depth, 1.0e-3), 0.0, 1.0);
    float z = smoothstep(0.0, 1.0, t);
    float horiz = sqrt(max(0.0, 1.0 - z * z));
    return normalize(vec3(grad * horiz, max(z, 1.0e-3)));
}

// uv local 0..1 sobre (ítem + margen), como la captura de Qt.
vec3 sampleSource(vec2 uv)
{
    vec2 tex = sourceRect.xy + uv * sourceRect.zw;
#ifdef IMPELLER_TARGET_OPENGLES
    tex.y = 1.0 - tex.y;
#endif
    return texture(source, tex).rgb;
}

vec3 frostedSample(vec2 uv, vec2 pxToUv, float radiusPx)
{
    vec2 lo = pxToUv * 0.5;
    vec2 hi = vec2(1.0) - lo;
    if (radiusPx <= 0.5)
        return sampleSource(clamp(uv, lo, hi));
    const float kGolden = 2.399963229728653;
    float n = clamp(taps, 1.0, 12.0);
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 12; ++i) {
        if (float(i) < n) {
            float t = (float(i) + 0.5) / n;
            float rad = sqrt(t) * radiusPx;
            float a = float(i) * kGolden;
            float w = exp(-2.0 * t);
            vec2 off = vec2(cos(a), sin(a)) * rad * pxToUv;
            sum += sampleSource(clamp(uv + off, lo, hi)) * w;
            wsum += w;
        }
    }
    return sum / wsum;
}

void main()
{
    vec2 p = FlutterFragCoord().xy;
    float sd = sceneSDF(p);
    float coverage = clamp(0.5 - sd, 0.0, 1.0);
    if (coverage <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 grad = sceneGrad(p);
    vec3 n = glassNormal(sd, grad, thickness);
    float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.0);

    vec3 col = fallbackColor.rgb;
    float alpha = fallbackColor.a;
    if (backdropMix > 0.0) {
        vec2 pxToUv = vec2(1.0) / (itemSize + vec2(2.0 * margin));
        vec2 uv = (p + vec2(margin)) * pxToUv;
        vec2 centreUv = (itemSize * 0.5 + vec2(margin)) * pxToUv;
        uv = centreUv + (uv - centreUv) * (1.0 - magnify);
        float edge = clamp(1.0 + sd / max(thickness * 1.6, 1.0), 0.0, 1.0);
        float reach = thickness * refraction / max(n.z, 0.2);
        float frostPx = frost * mix(0.35, 1.0, edge);
        vec3 back = frostedSample(uv - grad * edge * reach * pxToUv, pxToUv, frostPx);
        float lum = dot(back, kLuma);
        back = mix(vec3(lum), back, saturation);
        col = mix(col, back, backdropMix);
        alpha = mix(alpha, 1.0, backdropMix);
    }

    col = mix(col, tint.rgb, tint.a);

    vec2 light = normalize(vec2(-0.35, -1.0));
    float facing = dot(normalize(n.xy + vec2(1.0e-5)), light);
    col += rim * smoothstep(0.0, 1.0, facing) * rimLight;
    col -= rim * smoothstep(0.0, 1.0, -facing) * rimShade;
    col += rim * rimSheen;
    float bevel = pow(1.0 - clamp(n.z, 0.0, 1.0), 6.0);
    col += bevel * pow(clamp(facing, 0.0, 1.0), 4.0) * rimLight * 1.4;
    col -= rim * edgeContrast;
    col = (col - vec3(0.5)) * 1.03 + vec3(0.5);
    alpha = clamp(alpha + rim * rimLight * 0.5, 0.0, 1.0);

    col = clamp(col, 0.0, 1.0);
    fragColor = vec4(col * alpha, alpha) * (coverage * opacity);
}
