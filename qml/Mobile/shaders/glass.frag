#version 440
// Material glass único de InGe+ (GlassSurface): Home, Calicatas, Earth y Dock.
// Muestra la región alineada de UNA textura compartida del fondo, recortada con
// el rectángulo redondeado exacto de la superficie. Salida premultiplicada.
//
// refraction > 0 (Dock, 2026-11-02): lente portada LITERALMENTE del AGSL
// LENS_AGSL de Liquid-Glass-Android (GlassLensRenderer.kt, MIT, (c) 2025-2026
// pandadog; thirdparty/liquid-glass-android): perfil de bisel por potencia inversa
// (falloff = 2, núcleo = 1/4 del bisel), muestreo hacia dentro a lo largo de la
// normal del SDF (refractDir = -1), dispersión por canal (azul se curva más),
// vibrancy de saturación 1,4 y dos lóbulos especulares simétricos pow 4,5
// (filo de 2 px en el borde + halo interior hacia la luz). Contorno: SDF de
// Kirigami (MIT, thirdparty/kirigami-sdf). Con refraction = 0 (tier LOW y
// reducedMotion) queda transparente con el filo especular.
// Activo con specular >= 0,95 (Dock). Las demás superficies conservan el material anterior.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 region;        // UV de la superficie en la textura: x, y, ancho, alto
    vec2 itemSize;      // px del item (superficie + margen de sombra)
    float margin;       // px de margen para la sombra
    float radius;       // px del radio de esquina
    float edgeWidth;    // px del borde
    float shadowAlpha;
    vec4 tint;          // color de cristal (alfa = intensidad del tinte)
    vec4 edge;          // color del borde (alfa = intensidad)
    vec4 shadowColor;
    float refraction;   // px: refractPx de la lente (0 = sin refracción)
    float specular;     // specStrength de los lóbulos especulares (0 = material esmerilado)
    float bevel;        // px: ancho del bisel de la lente
    float contrast;     // 0..1: contraste adaptativo sobre fondos claros (material anterior)
    float frost;        // px: esmerilado de 5 muestras (material anterior)
    // Perfil «Extrema» (GraphicsCore.extremeGlass). Con extreme = 0 nada de lo
    // siguiente se evalúa y el resultado es idéntico al material base.
    float extreme;      // 1 = vidrio animado, gotas y muestreo de alta calidad
    float time;         // s; congelado con reducedMotion
    float gel;          // 0..1: estiramiento tipo gel (cápsula -> panel)
    vec4 drop0;         // gotas: x, y (px locales de la superficie), radio px, vida 0..1
    vec4 drop1;         // drop0 es siempre la más reciente (el filo la sigue)
    vec4 drop2;
    vec4 drop3;
    vec4 drop4;
    vec4 drop5;
    vec4 drop6;
    vec4 drop7;
    float frostQuality; // 0: 5 muestras de esmerilado; 1: 9 (fidelidad VERY_HIGH/EXTREME)
};
layout(binding = 1) uniform sampler2D source;

// sdf_rounded_rectangle: KDE Kirigami src/primitives/shaders/sdf.glsl
// SPDX-FileCopyrightText: 2020 Arjen Hiemstra, 2017 Inigo Quilez
// SPDX-License-Identifier: MIT (thirdparty/kirigami-sdf). Sin `lowp`.
float sdf_rounded_rectangle(in vec2 point, in vec2 rect, in vec4 radius)
{
    radius.xy = (point.x > 0.0) ? radius.xy : radius.zw;
    radius.x = (point.y > 0.0) ? radius.x : radius.y;
    vec2 d = abs(point) - rect + radius.x;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - radius.x;
}

vec3 backdropAt(vec2 at, vec2 rectSize)
{
    vec2 uv = region.xy + clamp(at / rectSize, 0.0, 1.0) * region.zw;
    return texture(source, uv).rgb;
}

// Esmerilado del Dock (frost px): 5 muestras sobre el nivel de mipmap que
// corresponde al radio, así la captura reducida se ve suave y sin mosaico.
// El sesgo de LOD (válido en GLSL ES 100) sube desde el nivel automático, que
// ya refleja la reducción de la captura. Sin mipmaps (tier LOW) no tiene efecto.
vec3 frostedAt(vec2 at, vec2 rectSize)
{
    float lod = log2(max(1.0, 0.5 * frost));
    vec2 k = region.zw / rectSize;
    vec2 uv = region.xy + clamp(at / rectSize, 0.0, 1.0) * region.zw;
    vec2 lo = region.xy;
    vec2 hi = region.xy + region.zw;
    float o = 0.6 * frost;
    vec3 diagonal = texture(source, clamp(uv + vec2( o,  o) * k, lo, hi), lod).rgb
                  + texture(source, clamp(uv + vec2(-o,  o) * k, lo, hi), lod).rgb
                  + texture(source, clamp(uv + vec2( o, -o) * k, lo, hi), lod).rgb
                  + texture(source, clamp(uv + vec2(-o, -o) * k, lo, hi), lod).rgb;
    if (frostQuality < 0.5)
        return 0.28 * texture(source, uv, lod).rgb + 0.18 * diagonal;
    float a = 0.85 * frost;                     // 4 muestras axiales extra: esmerilado más suave
    vec3 axial = texture(source, clamp(uv + vec2( a, 0.0) * k, lo, hi), lod).rgb
               + texture(source, clamp(uv + vec2(-a, 0.0) * k, lo, hi), lod).rgb
               + texture(source, clamp(uv + vec2(0.0,  a) * k, lo, hi), lod).rgb
               + texture(source, clamp(uv + vec2(0.0, -a) * k, lo, hi), lod).rgb;
    return 0.20 * texture(source, uv, lod).rgb + 0.12 * diagonal + 0.08 * axial;
}

// ---------------- Perfil «Extrema» (sólo con extreme > 0,5) ----------------
float smin(float a, float b, float k)
{
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float dropSdf(vec2 p, vec4 dr)
{
    return (dr.w > 0.0 && dr.z > 0.5) ? length(p - dr.xy) - dr.z : 10000.0;
}

// Metaballs: unión suave de las gotas vivas (se fusionan entre sí).
float dropsSdf(vec2 p)
{
    const float k = 14.0;
    float d = dropSdf(p, drop0);
    d = smin(d, dropSdf(p, drop1), k);
    d = smin(d, dropSdf(p, drop2), k);
    d = smin(d, dropSdf(p, drop3), k);
    d = smin(d, dropSdf(p, drop4), k);
    d = smin(d, dropSdf(p, drop5), k);
    d = smin(d, dropSdf(p, drop6), k);
    d = smin(d, dropSdf(p, drop7), k);
    return d;
}

// Contorno líquido: rectángulo con ondulación de gel y gotas que se funden con el borde.
float liquidSdf(vec2 c, vec2 hs, vec4 rr)
{
    float d = sdf_rounded_rectangle(c, hs, rr);
    if (gel > 0.001)
        d += gel * 2.6 * sin(c.x * 0.050 + time * 5.0) * sin(c.y * 0.070 - time * 3.6);
    return smin(d, dropsSdf(c + hs), 10.0);
}

// Esmerilado de alta calidad: 13 muestras (centro + dos anillos de 6, ángulo áureo).
vec3 frostedHQ(vec2 at, vec2 rectSize)
{
    float lod = log2(max(1.0, 0.5 * frost));
    vec2 k = region.zw / rectSize;
    vec2 uv = region.xy + clamp(at / rectSize, 0.0, 1.0) * region.zw;
    vec2 lo = region.xy;
    vec2 hi = region.xy + region.zw;
    vec3 acc = 0.16 * texture(source, uv, lod).rgb;
    for (int i = 0; i < 12; ++i) {
        float fi = float(i);
        float ring = i < 6 ? 0.55 : 1.0;
        float a = fi * 2.39996 + (i < 6 ? 0.0 : 0.52);
        vec2 o = vec2(cos(a), sin(a)) * frost * ring;
        acc += (i < 6 ? 0.08 : 0.06) * texture(source, clamp(uv + o * k, lo, hi), lod).rgb;
    }
    return acc;
}

// Dispersión cromática espectral: 5 muestras a lo largo del desplazamiento.
vec3 spectralAt(vec2 at, vec2 offset, float spread, vec2 rectSize)
{
    vec3 s0 = backdropAt(at + offset * (1.0 - spread), rectSize);
    vec3 s1 = backdropAt(at + offset * (1.0 - 0.5 * spread), rectSize);
    vec3 s2 = backdropAt(at + offset, rectSize);
    vec3 s3 = backdropAt(at + offset * (1.0 + 0.5 * spread), rectSize);
    vec3 s4 = backdropAt(at + offset * (1.0 + spread), rectSize);
    return vec3(0.5 * s0.r + 0.5 * s1.r,
                0.25 * s1.g + 0.5 * s2.g + 0.25 * s3.g,
                0.5 * s3.b + 0.5 * s4.b);
}

void main()
{
    vec2 px = qt_TexCoord0 * itemSize;
    vec2 rectSize = max(itemSize - 2.0 * margin, vec2(1.0));
    vec2 local = px - vec2(margin);
    vec2 hs = 0.5 * rectSize;
    vec2 c = local - hs;
    float r = min(radius, 0.5 * min(rectSize.x, rectSize.y));
    vec4 rr = vec4(r);
    float d = sdf_rounded_rectangle(c, hs, rr);

    // Sombra exterior muy suave (común a ambos materiales).
    float fall = 1.0 - smoothstep(0.0, max(margin, 1.0), d);

    if (specular >= 0.95) {
        // ---------------- Liquid Glass (LENS_AGSL de Liquid-Glass-Android) ----------------
        bool xg = extreme > 0.5;
        if (xg) {
            d = liquidSdf(c, hs, rr);
            fall = 1.0 - smoothstep(0.0, max(margin, 1.0), d);
        }
        float cov = clamp(0.5 - d / 1.5, 0.0, 1.0);
        vec2 n;
        if (xg)
            n = vec2(liquidSdf(c + vec2(1.0, 0.0), hs, rr) - liquidSdf(c - vec2(1.0, 0.0), hs, rr),
                     liquidSdf(c + vec2(0.0, 1.0), hs, rr) - liquidSdf(c - vec2(0.0, 1.0), hs, rr));
        else
            n = vec2(sdf_rounded_rectangle(c + vec2(1.0, 0.0), hs, rr) - sdf_rounded_rectangle(c - vec2(1.0, 0.0), hs, rr),
                     sdf_rounded_rectangle(c + vec2(0.0, 1.0), hs, rr) - sdf_rounded_rectangle(c - vec2(0.0, 1.0), hs, rr));
        float nLen = length(n);
        n = nLen > 0.0001 ? n / nLen : vec2(0.0, -1.0);

        float t = clamp(-d / max(bevel, 1.0), 0.0, 1.0);
        const float falloff = 2.0;
        float gB = pow(5.0, -falloff);
        float slope = (pow(1.0 + 4.0 * t, -falloff) - gB) / (1.0 - gB);

        // «Extrema»: la lente respira con el tiempo.
        float refr = xg ? refraction * (1.0 + 0.14 * sin(time * 1.25) + 0.05 * sin(time * 2.9 + 1.3)) : refraction;
        vec2 offset = n * (-1.0 * slope * refr);
        // Gotas: lente propia (se hunde hacia su centro) y filo especular.
        float dropRim = 0.0;
        vec2 nD = vec2(0.0);
        if (xg) {
            float dd = dropsSdf(local);
            if (dd < 12.0) {
                nD = vec2(dropsSdf(local + vec2(1.0, 0.0)) - dropsSdf(local - vec2(1.0, 0.0)),
                          dropsSdf(local + vec2(0.0, 1.0)) - dropsSdf(local - vec2(0.0, 1.0)));
                float nDl = length(nD);
                nD = nDl > 0.0001 ? nD / nDl : vec2(0.0);
                float tD = clamp(-dd / 10.0, 0.0, 1.0);
                float slopeD = (pow(1.0 + 4.0 * tD, -falloff) - gB) / (1.0 - gB);
                offset += nD * (-slopeD * max(refraction, 8.0) * 0.9) * step(dd, 0.0);
                dropRim = clamp(1.0 - abs(dd + 1.5) / 2.5, 0.0, 1.0);
            }
        }
        const float dispersion = 0.10;
        vec3 col;
        if (xg) {
            // Alta calidad: esmerilado de 13 muestras y dispersión espectral de 5.
            float spread = 0.16 * max(slope, 0.25);
            vec3 spectral = spectralAt(local, offset, spread, rectSize);
            if (frost > 0.0) {
                col = frostedHQ(local + offset, rectSize) + spectral - backdropAt(local + offset, rectSize);
                col = clamp(col, vec3(0.0), vec3(1.0));
            } else {
                col = spectral;
            }
        } else if (frost > 0.0) {
            // Base esmerilada; la dispersión del bisel se suma como diferencia nítida.
            vec3 center = backdropAt(local + offset, rectSize);
            col = frostedAt(local + offset, rectSize);
            col.r += backdropAt(local + offset * (1.0 - dispersion * slope), rectSize).r - center.r;
            col.b += backdropAt(local + offset * (1.0 + dispersion * slope), rectSize).b - center.b;
            col = clamp(col, vec3(0.0), vec3(1.0));
        } else {
            col = vec3(backdropAt(local + offset * (1.0 - dispersion * slope), rectSize).r,
                       backdropAt(local + offset, rectSize).g,
                       backdropAt(local + offset * (1.0 + dispersion * slope), rectSize).b);
        }

        // Vibrancy (satFactor = 1,4).
        const float satFactor = 1.4;
        float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
        float satNow = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
        float room = 1.0 - smoothstep(0.2, 0.85, satNow);
        float hl = 1.0 - smoothstep(0.75, 0.98, lum);
        float amount = 1.0 + (satFactor - 1.0) * mix(0.3, 1.0, room * hl);
        col = clamp(mix(vec3(lum), col, amount), vec3(0.0), vec3(1.0));

        // tintColor (premultiplicado por Qt): 0 = vidrio transparente.
        col = mix(col, tint.a > 0.001 ? tint.rgb / tint.a : col, tint.a);

        // Dos lóbulos especulares simétricos; luz desde arriba.
        vec2 lightDir = normalize(vec2(0.35, 0.94));
        if (xg) {
            // El filo respira y sigue el último contacto (drop0).
            float a = 0.36 + 0.22 * sin(time * 0.7);
            lightDir = vec2(sin(a), cos(a));
            if (drop0.w > 0.0)
                lightDir = normalize(mix(lightDir, normalize(hs - drop0.xy + vec2(0.0, 0.001)), 0.55 * drop0.w));
        }
        float facing = dot(n, -lightDir);
        float lobeF = pow(max(facing, 0.0), 4.5);
        float lobeB = pow(max(-facing, 0.0), 4.5);
        float bandW = clamp(bevel * 0.3, 2.0, max(2.0, min(6.0, min(rectSize.x, rectSize.y) * 0.05)));
        float glowIn = clamp((-d - 1.0) / 2.0, 0.0, 1.0);
        float glow = glowIn * pow(clamp(1.0 - (-d - 3.0) / bandW, 0.0, 1.0), 1.5) * cov;
        float hair = clamp(1.0 - abs(d + 1.0) / 2.0, 0.0, 1.0) * cov;
        float spec = (hair * 0.70 * (lobeF + lobeB) + glow * 0.10 * lobeF) * specular;
        if (xg) {
            spec *= 1.0 + 0.18 * sin(time * 1.25 + 0.6);
            float dFacing = dot(nD, -lightDir);
            spec += dropRim * (0.55 * pow(max(dFacing, 0.0), 3.0) + 0.18 * pow(max(-dFacing, 0.0), 3.0)) * cov;
        }
        col = clamp(col + vec3(spec), vec3(0.0), vec3(1.0));

        vec4 surface = vec4(col * cov, cov);
        float shadow = shadowAlpha * fall * fall * (1.0 - cov);
        vec4 outer = vec4(shadowColor.rgb * shadow, shadow);
        fragColor = (surface + outer * (1.0 - surface.a)) * qt_Opacity;
        return;
    }

    // ---------------- Material esmerilado anterior (tarjetas, Earth, Home): sin cambios ----------------
    {
        vec2 px = qt_TexCoord0 * itemSize;
        vec2 rectSize = max(itemSize - 2.0 * margin, vec2(1.0));
        vec2 local = px - vec2(margin);

        // Rectángulo redondeado (distancia con signo, antialias de 1 px).
        float r = min(radius, 0.5 * min(rectSize.x, rectSize.y));
        vec2 q = abs(local - 0.5 * rectSize) - (0.5 * rectSize - vec2(r));
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
        float inside = clamp(0.5 - d, 0.0, 1.0);

        // Fotografía desenfocada alineada con su posición real.
        vec2 sampleAt = local;
        float bevelPx = max(bevel, 1.0);
        // 0 en el interior plano, 1 en el contorno (d = 0): zona curva del cristal.
        float rimZone = clamp(1.0 + d / bevelPx, 0.0, 1.0);
        if (refraction > 0.0) {
            // Lente: cerca del borde el cristal "dobla" la luz y muestrea más adentro.
            vec2 fromCenter = (local - 0.5 * rectSize) / max(0.5 * rectSize, vec2(1.0));
            sampleAt -= fromCenter * refraction * rimZone * rimZone;
        }
        vec3 backdrop = backdropAt(sampleAt, rectSize);
        if (frost > 0.0) {
            backdrop = 0.40 * backdrop
                     + 0.15 * (backdropAt(sampleAt + vec2(frost, 0.0), rectSize)
                             + backdropAt(sampleAt - vec2(frost, 0.0), rectSize)
                             + backdropAt(sampleAt + vec2(0.0, frost), rectSize)
                             + backdropAt(sampleAt - vec2(0.0, frost), rectSize));
        }
        // QColor uniforms arrive premultiplied from Qt Quick. Multiplying their
        // RGB by alpha again turns a translucent white tint into a gray film.
        vec3 glass = backdrop * (1.0 - tint.a) + tint.rgb;
        if (contrast > 0.0) {
            // Luminancia del fondo real: sobre blanco/tarjetas el cristal se vuelve
            // humo azulado (iconos blancos legibles); sobre fondos oscuros no cambia.
            float luma = dot(backdrop, vec3(0.2126, 0.7152, 0.0722));
            vec3 smoked = glass * 0.52 + vec3(0.03, 0.05, 0.09);
            glass = mix(glass, smoked, contrast * smoothstep(0.35, 0.90, luma));
        }
        // Profundidad discreta: un poco más de luz arriba que abajo.
        float t = clamp(local.y / rectSize.y, 0.0, 1.0);
        glass = mix(glass, vec3(1.0), 0.05 * (1.0 - t));
        if (specular > 0.0) {
            // Brillo especular: banda suave en el tercio superior y filo de luz arriba,
            // reflejo frío tenue abajo (profundidad del vidrio).
            float band = pow(1.0 - t, 3.0) * 0.16;
            float topRim = rimZone * rimZone * (1.0 - t) * 0.42;
            float lowRim = rimZone * rimZone * t * 0.12;
            glass = mix(glass, vec3(1.0), specular * clamp(band + topRim, 0.0, 1.0));
            glass = mix(glass, vec3(0.80, 0.92, 1.0), specular * lowRim);
        }

        // Borde fino dentro del contorno.
        float edgeMask = clamp(edgeWidth + 0.5 + d, 0.0, 1.0) * inside;
        glass = glass * (1.0 - edge.a * edgeMask) + edge.rgb * edgeMask;

        vec4 surface = vec4(glass, 1.0) * inside;

        // Sombra exterior muy suave (solo fuera de la superficie).
        float fall = 1.0 - smoothstep(0.0, max(margin, 1.0), d);
        float shadow = shadowAlpha * fall * fall * (1.0 - inside);
        vec4 outer = vec4(shadowColor.rgb * shadow, shadow);

        fragColor = (surface + outer * (1.0 - surface.a)) * qt_Opacity;
    }
}
