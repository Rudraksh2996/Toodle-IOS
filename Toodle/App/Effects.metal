#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Shared noise field: every effect takes the same `seed` (Tok.noiseSeed) and light angle (Tok.lightAngle).
static float hash21(float2 p, float seed) {
    p = fract(p * float2(123.34, 456.21) + seed);
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
static float vnoise(float2 p, float seed) {
    float2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i, seed), hash21(i + float2(1, 0), seed), u.x),
               mix(hash21(i + float2(0, 1), seed), hash21(i + float2(1, 1), seed), u.x), u.y);
}
static float fbm(float2 p, float seed) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * vnoise(p, seed); p = p * 2.03 + 17.0; a *= 0.5; }
    return v;
}
static float3 lightDir(float angle) { return normalize(float3(cos(angle), sin(angle), 0.9)); }
// Blue-only spectral ramp (sampled from refs-foil-1/2, hue 228-258). Triangle-wave input so it never seams.
static half3 ramp(float x, half3 a, half3 b, half3 c, half3 d) {
    float t = abs(fract(x) * 2.0 - 1.0) * 3.0;
    if (t < 1.0) return mix(a, b, half(t));
    if (t < 2.0) return mix(b, c, half(t - 1.0));
    return mix(c, d, half(t - 2.0));
}

// 1. Bent holographic foil: 3 soft fold bands, light-to-shadow shading, hue shift along the fold normal.
static float folds(float2 uv, float time, float seed) {
    float w = fbm(uv * 1.2 + float2(time * 0.015, -time * 0.01), seed);
    float2 q = uv + 0.35 * float2(w, -w);
    return 0.55 * sin(q.x * 2.1 + q.y * 1.3 + 0.4)
         + 0.30 * sin(-q.x * 1.2 + q.y * 3.1 + 1.7 + time * 0.02)
         + 0.15 * sin(q.x * 4.0 - q.y * 0.7 + 3.1);
}
[[ stitchable ]] half4 foil(float2 pos, half4 color, float2 size, float time, float angle, float seed, float strength,
                           half4 base, half4 c1, half4 c2, half4 c3, half4 c4) {
    float px = 1.0 / max(size.y, 1.0), e = 2.0 * px;
    float2 uv = pos * px;
    float h = folds(uv, time, seed);
    float hx = folds(uv + float2(e, 0), time, seed) - h;
    float hy = folds(uv + float2(0, e), time, seed) - h;
    float3 n = normalize(float3(-hx / e * 0.25, -hy / e * 0.25, 1.0));
    float3 L = lightDir(angle);
    float diffuse = saturate(dot(n, L));
    float spec = pow(saturate(dot(n, normalize(L + float3(0, 0, 1)))), 48.0);
    float band = smoothstep(-0.2, 0.9, h);
    half3 spectral = ramp(0.5 + 0.6 * (n.x * 1.7 + n.y * 1.1) + h * 0.25, c1.rgb, c2.rgb, c3.rgb, c4.rgb);
    half3 rgb = mix(base.rgb, spectral, half(band * strength));
    rgb *= half(mix(0.88, 1.03, diffuse));
    rgb += half(spec * 0.3 * strength);
    return half4(saturate(rgb), 1.0h);
}

// 2. Perspective dot grid: horizon above the top edge, dots shrink and fade with depth.
[[ stitchable ]] half4 dotGrid(float2 pos, half4 color, float2 size, float density, half4 ink, float alpha) {
    float px = 1.0 / max(size.y, 1.0);
    float2 uv = pos * px;
    float y = uv.y + 0.35;
    float z = 1.0 / y;
    float2 p = float2((uv.x - 0.5 * size.x * px) * z, z) * density;
    float2 cell = fract(p) - 0.5;
    float2 screen = float2(cell.x * y, cell.y * y * y) / density;
    float r = 0.0032 * y;
    float a = (1.0 - smoothstep(r - px, r + px, length(screen))) * smoothstep(0.35, 1.25, y) * alpha;
    return half4(ink.rgb * half(a), half(a));
}

// 6. Metaball liquid-chrome spheres (landing only). balls = [x, y, radius] * count, in points.
static float field(float2 p, device const float *balls, int count, thread float2 &grad) {
    float f = 0.0; grad = float2(0.0);
    for (int i = 0; i + 2 < count; i += 3) {
        float2 d = p - float2(balls[i], balls[i + 1]);
        float r2 = balls[i + 2] * balls[i + 2], d2 = max(dot(d, d), 1.0);
        f += r2 / d2;
        grad += -2.0 * r2 * d / (d2 * d2);
    }
    return f;
}
static half4 chrome(float2 pos, float f, float2 grad, float angle, half3 refracted, half4 ink, half4 glint, half4 base) {
    float3 n = normalize(float3(-grad * 18.0, 1.0));
    float3 L = lightDir(angle);
    float fresnel = pow(1.0 - n.z, 3.0);
    float spec = pow(saturate(dot(reflect(-L, n), float3(0, 0, 1))), 40.0);
    half3 env = mix(ink.rgb, glint.rgb, half(saturate(0.5 + 0.5 * dot(n.xy, L.xy))));
    half3 rgb = mix(refracted, env, half(0.55 + 0.45 * fresnel)) + half(spec * 0.8);
    rgb = mix(rgb, base.rgb, half(0.15 * (1.0 - fresnel)));
    float alpha = smoothstep(0.92, 1.08, f);
    return half4(saturate(rgb) * half(alpha), half(alpha));
}
// High tier: refracts the foil + grid layer under the sphere.
[[ stitchable ]] half4 metaballs(float2 pos, SwiftUI::Layer layer, device const float *balls, int count,
                                float angle, float refraction, half4 ink, half4 glint, half4 base) {
    float2 grad;
    float f = field(pos, balls, count, grad);
    half4 under = layer.sample(pos);
    if (f < 0.9) return under;
    float2 off = grad * refraction;
    off *= min(1.0, 36.0 / max(length(off), 0.001)); // stay inside maxSampleOffset (40pt)
    half4 sphere = chrome(pos, f, grad, angle, layer.sample(pos + off).rgb, ink, glint, base);
    return sphere + under * (1.0h - sphere.a);
}
// Medium/low tier: same spheres drawn as an overlay, no layer sampling (no offscreen pass).
[[ stitchable ]] half4 metaballsFlat(float2 pos, half4 color, device const float *balls, int count,
                                    float angle, half4 ink, half4 glint, half4 base) {
    float2 grad;
    float f = field(pos, balls, count, grad);
    if (f < 0.9) return half4(0);
    return chrome(pos, f, grad, angle, base.rgb, ink, glint, base);
}

// 4. Caustics + diffraction edge: only on pressed/focused controls.
[[ stitchable ]] half4 caustics(float2 pos, half4 color, float2 size, float time, float angle, float seed,
                               half4 c1, half4 c2, half4 c3, half4 c4) {
    if (color.a == 0.0h) return color;
    float2 uv = pos / max(size.y, 1.0);
    float c = 0.0;
    for (int i = 0; i < 2; i++) {
        float2 q = uv * (3.0 + float(i) * 2.0) + float2(time * 0.12, -time * 0.08) + fbm(uv * 2.0 + float(i), seed);
        c += pow(1.0 - abs(sin(q.x * 3.1) * sin(q.y * 2.7)), 6.0);
    }
    float edge = 1.0 - smoothstep(0.0, 0.12, min(min(uv.x, size.x / size.y - uv.x), min(uv.y, 1.0 - uv.y)));
    half3 spectral = ramp(uv.x * 0.8 + cos(angle) * 0.3, c1.rgb, c2.rgb, c3.rgb, c4.rgb);
    float a = saturate(c * 0.25 + edge * 0.6) * float(color.a);
    return half4(spectral * half(a), half(a));
}
