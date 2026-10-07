#version 440
// InGe+ dock glass. Ported from liquid-glass-bottom-nav-bar (MIT, A. B. Ozyurt):
// rounded-box SDF, bevel normal from the SDF gradient, inward refractive gather
// that grows toward the rim, golden-angle frost and a directional fresnel rim.
// Geometry is in logical pixels of the item; the source texture covers the
// item plus `margin` on every side so the rim can gather nearby content.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float margin;
    float radius;
    float thickness;
    float refraction;
    float frost;
    float rimLight;
    float rimShade;
    float rimSheen;
    float saturation;
    float backdropMix;
    float magnify;
    float edgeContrast;
    float taps;          // frost samples, 1..12 (constant-bounded loop)
    vec4 tint;
    vec4 fallbackColor;
};

layout(binding = 1) uniform sampler2D source;

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

vec3 frostedSample(vec2 uv, vec2 pxToUv, float radiusPx)
{
    vec2 lo = pxToUv * 0.5;
    vec2 hi = vec2(1.0) - lo;
    if (radiusPx <= 0.5)
        return texture(source, clamp(uv, lo, hi)).rgb;
    const float kGolden = 2.399963229728653;
    float n = clamp(taps, 1.0, 12.0);
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 12; ++i) {
        if (float(i) >= n)
            break;
        float t = (float(i) + 0.5) / n;
        float rad = sqrt(t) * radiusPx;
        float a = float(i) * kGolden;
        float w = exp(-2.0 * t);
        vec2 off = vec2(cos(a), sin(a)) * rad * pxToUv;
        sum += texture(source, clamp(uv + off, lo, hi)).rgb * w;
        wsum += w;
    }
    return sum / wsum;
}

void main()
{
    vec2 p = qt_TexCoord0 * itemSize;
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
        // Micro lens: almost no displacement in the centre, a few pixels of
        // inward gather at the bevel.
        vec2 centreUv = (itemSize * 0.5 + vec2(margin)) * pxToUv;
        uv = centreUv + (uv - centreUv) * (1.0 - magnify);
        float edge = clamp(1.0 + sd / max(thickness * 1.6, 1.0), 0.0, 1.0);
        float reach = thickness * refraction / max(n.z, 0.2);
        // Cleaner centre, a little more frost toward the bevel.
        float frostPx = frost * mix(0.35, 1.0, edge);
        vec3 back = frostedSample(uv - grad * edge * reach * pxToUv, pxToUv, frostPx);
        float lum = dot(back, kLuma);
        back = mix(vec3(lum), back, saturation);
        col = mix(col, back, backdropMix);
        alpha = mix(alpha, 1.0, backdropMix);
    }

    col = mix(col, tint.rgb, tint.a);

    // Light from the upper left (item space is y-down).
    vec2 light = normalize(vec2(-0.35, -1.0));
    float facing = dot(normalize(n.xy + vec2(1.0e-5)), light);
    col += rim * smoothstep(0.0, 1.0, facing) * rimLight;
    col -= rim * smoothstep(0.0, 1.0, -facing) * rimShade;
    col += rim * rimSheen;
    // Crisp specular on the lit bevel and a faint darkening of the bevel keep
    // the glass legible on near-white content without a grey fill.
    float bevel = pow(1.0 - clamp(n.z, 0.0, 1.0), 6.0);
    col += bevel * pow(clamp(facing, 0.0, 1.0), 4.0) * rimLight * 1.4;
    col -= rim * edgeContrast;
    col = (col - vec3(0.5)) * 1.03 + vec3(0.5);
    alpha = clamp(alpha + rim * rimLight * 0.5, 0.0, 1.0);

    col = clamp(col, 0.0, 1.0);
    fragColor = vec4(col * alpha, alpha) * (coverage * qt_Opacity);
}
