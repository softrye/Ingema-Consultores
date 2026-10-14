#version 440
// Material glass esmerilado del Home (2026-10-12). Muestra la región alineada
// de UNA textura compartida con la fotografía ya desenfocada (backdrop blur),
// recortada con el rectángulo redondeado exacto de la superficie, con tinte
// azulado translúcido, borde fino, leve profundidad y sombra exterior suave.
// Sin refracción ni distorsión por defecto. Opcional (InGe Earth, 2026-10-14):
// refraction/specular/bevel > 0 añaden lente en el borde y brillo especular;
// con los tres en 0 (valor por defecto de GlassSurface) la salida es idéntica a
// la anterior para Home, Calicatas y el resto de superficies. Salida premultiplicada.

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
};
layout(binding = 1) uniform sampler2D source;

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
    vec2 uv = region.xy + clamp(sampleAt / rectSize, 0.0, 1.0) * region.zw;
    vec3 backdrop = texture(source, uv).rgb;
    vec3 glass = mix(backdrop, tint.rgb, tint.a);
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
    glass = mix(glass, edge.rgb, edge.a * edgeMask);

    vec4 surface = vec4(glass, 1.0) * inside;

    // Sombra exterior muy suave (solo fuera de la superficie).
    float fall = 1.0 - smoothstep(0.0, max(margin, 1.0), d);
    float shadow = shadowAlpha * fall * fall * (1.0 - inside);
    vec4 outer = vec4(shadowColor.rgb * shadow, shadow);

    fragColor = (surface + outer * (1.0 - surface.a)) * qt_Opacity;
}
