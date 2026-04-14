#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;           // viewport in physical pixels (matches FlutterFragCoord)
uniform vec4 uNeutralColor;   // structText RGB + alpha (0.018)
uniform vec4 uAccentColor;    // accentText RGB + alpha (0.014)
uniform float uAccentCutoff;  // 0.42 — fraction of height where accent dots stop
uniform float uStep;          // grid cell size in physical pixels (logical step × DPR)

out vec4 fragColor;

// Deterministic hash replicating the original Dart CustomPainter:
//   ((cellX * 73856093) ^ (cellY * 19349663)) & 7
// GLSL ES has no integer XOR/AND on floats, so we replicate via
// modular arithmetic on the low 3 bits → result 0-7.
float ditherHash(vec2 cell) {
    float a = mod(cell.x * 73856093.0, 65536.0);
    float b = mod(cell.y * 19349663.0, 65536.0);

    float c = 0.0;
    float pow2 = 1.0;
    for (int i = 0; i < 3; i++) {
        float bitA = mod(floor(a), 2.0);
        float bitB = mod(floor(b), 2.0);
        c += mod(bitA + bitB, 2.0) * pow2;
        a = floor(a * 0.5);
        b = floor(b * 0.5);
        pow2 *= 2.0;
    }
    return c;
}

void main() {
    vec2 coord = FlutterFragCoord().xy;
    vec2 cell = floor(coord / uStep);
    float h = ditherHash(cell);

    if (h < 0.5) {
        fragColor = uNeutralColor;
    } else if (h < 1.5 && coord.y < uSize.y * uAccentCutoff) {
        fragColor = uAccentColor;
    } else {
        discard;
    }
}
