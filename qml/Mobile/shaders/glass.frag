#version 440
// Material glass esmerilado del Home (2026-10-12). Muestra la región alineada
// de UNA textura compartida con la fotografía ya desenfocada (backdrop blur),
// recortada con el rectángulo redondeado exacto de la superficie, con tinte
// azulado translúcido, borde fino, leve profundidad y sombra exterior suave.
// Sin refracción ni distorsión por defecto. Opcional (InGe Earth, 2026-10-14):
// refraction/specular/bevel > 0 añaden lente en el borde y brillo especular;
// con los tres en 0 (valor por defecto de GlassSurface) la salida es idéntica a
// la anterior para Home, Calicatas y el resto de superficies. Salida premultiplicada.
// Material único del Dock (2026-10-15): contrast/frost > 0 añaden contraste
// adaptativo (oscurece sólo donde el fondo muestreado es claro, para iconos
// blancos legibles sin teñir el cristal) y esmerilado propio de 5 muestras
// (mismo grano de vidrio con texturas más o menos desenfocadas). En 0 no
// cambian nada para el resto de superficies.
// Composición: el interior es la reconstrucción del fondo REAL (textura
// alineada por `region`) y se emite con alfa 1 premultiplicada; mezclarla con
// el contenido nítido que hay detrás produciría doble imagen (fantasma) en la
// zona refractada. La transparencia la aporta el muestreo, no el alfa.

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
    float refraction;   // px: el borde muestrea hacia el centro (lente); 0 = sin refracción
    float specular;     // 0..1: brillo especular superior y filo de luz; 0 = sin brillo
    float bevel;        // px: ancho de la zona curva del borde
    float contrast;     // 0..1: contraste adaptativo sobre fondos claros; 0 = sin efecto
    float frost;        // px: esmerilado en el shader (5 muestras); 0 = sin efecto
};
layout(binding = 1) uniform sampler2D source;

// Muestra la textura del fondo en coordenadas locales de la superficie; fuera
// del rectángulo se fija al borde (sin UV fuera de rango ni repeticiones).
vec3 backdropAt(vec2 at, vec2 rectSize)
{
    vec2 uv = region.xy + clamp(at / rectSize, 0.0, 1.0) * region.zw;
    return texture(source, uv).rgb;
}

void main()
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
