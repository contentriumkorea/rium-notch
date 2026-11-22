#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 riumLightOnLight(float2 position, half4 color, float density,
                                        float saturation, float whiteCut, float amount) {
    (void)position;
    if (amount <= 0.0 || color.a <= half(0.002)) return color;
    half3 rgb = color.rgb / color.a;
    half luminance = dot(rgb, half3(0.2126, 0.7152, 0.0722));
    rgb = clamp(mix(half3(luminance), rgb, half(saturation)), half(0), half(1));
    half high = max(rgb.r, max(rgb.g, rgb.b));
    half low = min(rgb.r, min(rgb.g, rgb.b));
    half chroma = high - low;
    half neutral = (half(1) - smoothstep(half(0.02), half(0.12), chroma))
                 * smoothstep(half(0.55), half(0.85), high);
    half weight = half(whiteCut) * smoothstep(half(0.04), half(0.18), chroma);
    half removed = weight * low;
    half3 cleaned = (rgb - removed) / max(half(1) - removed, half(0.001));
    half cleanHigh = max(max(cleaned.r, max(cleaned.g, cleaned.b)), half(0.001));
    cleaned *= mix(half(1), high / cleanHigh, weight);
    cleaned = mix(cleaned, half3(0.62, 0.68, 0.90), neutral);
    half alpha = min(half(1), color.a * half(density));
    half4 adapted = half4(clamp(cleaned, half(0), half(1)) * alpha, alpha);
    return mix(color, adapted, half(amount));
}
