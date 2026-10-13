#version 440
// Aurora del acceso InGe+ (V2, 2026-10-12). Masas de luz azul y verde
// corporativas que fluyen como pintura en agua: el espacio se deforma con
// ondas lentas (domain warping), cada masa orbita y respira, y sus colores se
// mezclan por ponderación (sin tender a blanco). Dithering para evitar bandas
// en gradientes oscuros. mode 0 = Login, mode 1 = Welcome (arco superior).
// boost = luz verde que entra desde la esquina superior derecha y se expande
// en diagonal (Continue). tintAmount = tinte temporal de error.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float mode;
    float boost;
    float tintAmount;
    float glowGain;
    vec4 baseColor;     // #151A30
    vec4 deepColor;     // #1C2D50
    vec4 primaryColor;  // #0654A2 (animable)
    vec4 accentColor;   // #486426
    vec4 tintColor;     // color de error existente
};

vec3 acc = vec3(0.0);
float wsum = 0.0;

void addLight(vec3 color, float weight)
{
    acc += color * weight;
    wsum += weight;
}

// Masa gaussiana anisótropa: se estira a lo largo de un eje que gira.
float mass(vec2 p, vec2 c, vec2 radii, float angle)
{
    vec2 d = p - c;
    float cs = cos(angle), sn = sin(angle);
    vec2 r = vec2(cs * d.x + sn * d.y, -sn * d.x + cs * d.y) / radii;
    return exp(-dot(r, r));
}

float hash(vec2 v)
{
    return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec2 uv = qt_TexCoord0;
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = time;

    // Corrientes suaves: el plano se ondula lentamente en dos escalas.
    vec2 w = p + 0.055 * vec2(sin(3.1 * p.y + 0.55 * t) + 0.5 * sin(5.3 * p.y - 0.37 * t + 1.7),
                              cos(2.7 * p.x - 0.43 * t) + 0.5 * cos(4.9 * p.x + 0.29 * t + 0.6));

    // Los mismos tonos de marca con más luz (emisión), sin cambiar de color.
    vec3 blue = clamp(primaryColor.rgb * 1.45, 0.0, 1.0);
    vec3 sky = clamp(primaryColor.rgb * 1.45 + vec3(0.02, 0.12, 0.10), 0.0, 1.0);
    vec3 green = clamp(accentColor.rgb * 2.35, 0.0, 1.0);
    vec3 deep = deepColor.rgb * 1.25;
    vec3 base;

    if (mode < 0.5) {
        base = mix(deepColor.rgb, baseColor.rgb * 0.42, smoothstep(0.02, 0.62, uv.y));
        // Masa azul principal: orbita en la parte alta izquierda y respira.
        addLight(blue, 1.30 * mass(w, vec2(0.30 * aspect + 0.10 * sin(0.31 * t), 0.10 + 0.07 * sin(0.23 * t + 1.0)),
                                   vec2(0.34 + 0.04 * sin(0.41 * t), 0.24 + 0.03 * cos(0.37 * t)), 0.6 * sin(0.17 * t)));
        // Azul claro que cruza el centro y se funde con el verde.
        addLight(sky, 0.70 * mass(w, vec2(0.55 * aspect + 0.14 * sin(0.27 * t + 2.0), 0.30 + 0.08 * cos(0.21 * t)),
                                  vec2(0.22, 0.15 + 0.03 * sin(0.33 * t)), 0.9 + 0.5 * sin(0.19 * t)));
        // Azul profundo bajo, da cuerpo detrás del texto.
        addLight(deep, 0.65 * mass(w, vec2(0.18 * aspect + 0.05 * sin(0.15 * t + 3.0), 0.52 + 0.05 * cos(0.13 * t)),
                                   vec2(0.32, 0.22), 0.3));
        // Masa verde: nace en la esquina superior derecha, avanza y se retira.
        addLight(green, 1.70 * mass(w, vec2(0.93 * aspect + 0.10 * sin(0.29 * t + 0.5), 0.03 + 0.08 * sin(0.25 * t + 2.2)),
                                    vec2(0.20 + 0.05 * sin(0.37 * t), 0.15 + 0.04 * cos(0.31 * t)), -0.7 + 0.4 * sin(0.23 * t)));
        // Lengua verde-azulada que se separa y vuelve a unirse.
        addLight(mix(blue, green, 0.55), 0.45 * mass(w, vec2(0.72 * aspect + 0.12 * cos(0.22 * t), 0.18 + 0.07 * sin(0.35 * t + 1.3)),
                                                     vec2(0.16, 0.09), 1.1 + 0.6 * sin(0.27 * t)));
    } else {
        base = mix(baseColor.rgb * 0.80, baseColor.rgb * 0.42, smoothstep(0.0, 1.0, uv.y));
        vec2 c = vec2(0.55 * aspect + 0.02 * sin(0.19 * t), 0.50);
        vec2 d = vec2((w.x - c.x) * 0.80, w.y - c.y);
        float dist = length(d);
        float angle = atan(d.y, d.x);
        float radius = 0.40 + 0.015 * sin(3.0 * angle + 0.45 * t) + 0.01 * sin(0.33 * t);
        float width = 0.085 + 0.015 * sin(2.0 * angle - 0.38 * t);
        float x = (dist - radius) / width;
        float band = exp(-x * x);
        float upper = smoothstep(0.66, 0.26, w.y);
        float k = smoothstep(-2.5, -0.7, angle + 0.35 * sin(0.21 * t));
        addLight(blue, 1.6 * band * upper * (1.0 - k));
        addLight(green, 1.8 * band * upper * k);
        float inner = smoothstep(radius + 0.03, radius - 0.22, dist);
        addLight(blue, 0.45 * inner * upper);
    }

    // Continue: luz verde desde la esquina superior derecha, en diagonal.
    if (boost > 0.0) {
        vec2 origin = mix(vec2(aspect, 0.0), vec2(0.35 * aspect, 0.55), 0.55 * boost);
        float r = 0.16 + 1.25 * boost;
        float g = exp(-dot(p - origin, p - origin) / (r * r));
        addLight(green, 6.0 * boost * g);
    }

    float coverage = (1.0 - exp(-wsum)) * glowGain;
    vec3 light = acc / max(wsum, 1e-5);
    // Más luminosidad en el pico de la saturación (sin llegar a blanco).
    light = min(light * (1.0 + 0.35 * boost), vec3(1.0));
    light = mix(light, tintColor.rgb, tintAmount);
    vec3 color = mix(base, light, clamp(coverage, 0.0, 1.0));
    color += (hash(gl_FragCoord.xy + fract(t)) - 0.5) / 255.0;
    fragColor = vec4(color, 1.0) * qt_Opacity;
}
