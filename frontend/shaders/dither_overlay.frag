#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;           // viewport in physical pixels (matches FlutterFragCoord)
uniform vec4 uNeutralColor;   // structText RGB + alpha (0.018)
uniform vec4 uAccentColor;    // accentText RGB + alpha (0.014)
uniform float uAccentCutoff;  // 0.42 — fraction of height where accent dots stop
uniform float uStep;          // grid cell size in physical pixels (logical step × DPR)

out vec4 fragColor;

// Per-cell scatter hash mapped to 0-7. Uses Dave Hoskins' sine-free hash:
// every intermediate stays small enough for exact float32 evaluation, unlike
// the previous integer-prime hash whose products exceeded the 24-bit mantissa
// and collapsed to 0 on GPUs.
float ditherHash(vec2 cell) {
    vec3 p3 = fract(vec3(cell.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return floor(fract((p3.x + p3.y) * p3.z) * 8.0);
}

void main() {
    vec2 coord = FlutterFragCoord().xy;
    vec2 cell = floor(coord / uStep);
    float h = ditherHash(cell);

    // Flutter's runtime-effect contract expects premultiplied alpha; writing
    // straight RGB at low alpha is additive and bleeds toward white.
    if (h < 0.5) {
        fragColor = vec4(uNeutralColor.rgb * uNeutralColor.a, uNeutralColor.a);
    } else if (h < 1.5 && coord.y < uSize.y * uAccentCutoff) {
        fragColor = vec4(uAccentColor.rgb * uAccentColor.a, uAccentColor.a);
    } else {
        // discard is illegal in SkSL runtime effects (breaks web builds and
        // desktop Skia shader loading); premultiplied transparent black is a
        // true no-op under srcOver.
        fragColor = vec4(0.0);
    }
}
