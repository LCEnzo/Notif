#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uPixelScale; // device pixel ratio (1.0, 2.0, 3.0, …)

uniform float uGrainSpacing;
uniform float uGrainLimitYFactor;
uniform float uGrainNoiseThreshold;
uniform float uGrainOpacityScale;
uniform float uGrainMinRadius;
uniform float uGrainMaxRadiusDelta;
uniform vec4 uGrainFrom;
uniform vec4 uGrainTo;
uniform float uGrainColorLerpScale;
uniform vec2 uGrainFadeCenter;
uniform float uGrainFadeRadius;

uniform float uHalftoneSpacing;
uniform float uHalftoneStartYFactor;
uniform float uHalftoneBaseRadius;
uniform float uHalftoneRadiusGrowth;
uniform float uHalftoneOpacityBase;
uniform float uHalftoneOpacityGrowth;
uniform vec4 uHalftoneTop;
uniform vec4 uHalftoneBottom;
uniform float uHalftoneColorLerpScale;
uniform float uHalftoneConvexCurveDepthFactor;
uniform float uHalftoneLandscapeCurveBoost;
uniform float uHalftoneCurveExponent;
uniform float uHalftoneLandscapeExponentPull;

out vec4 fragColor;

float saturate(float value) {
  return clamp(value, 0.0, 1.0);
}

float hash12(vec2 value) {
  vec3 p3 = fract(vec3(value.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec4 composite(vec4 back, vec4 front) {
  return front + back * (1.0 - front.a);
}

float circleCoverage(vec2 fragCoord, vec2 center, float radius) {
  float distanceToCenter = length(fragCoord - center);
  float antialias = 0.75 * uPixelScale;
  return 1.0 - smoothstep(
    radius - antialias,
    radius + antialias,
    distanceToCenter
  );
}

vec4 grainLayer(vec2 fragCoord) {
  float spacing = uGrainSpacing * uPixelScale;
  float minRadius = uGrainMinRadius * uPixelScale;
  float maxRadiusDelta = uGrainMaxRadiusDelta * uPixelScale;

  float limitY = uSize.y * uGrainLimitYFactor;
  if (fragCoord.y > limitY + spacing) {
    return vec4(0.0);
  }

  vec2 fadeCenter = vec2(
    (uGrainFadeCenter.x + 1.0) * 0.5 * uSize.x,
    (uGrainFadeCenter.y + 1.0) * 0.5 * uSize.y
  );
  float halfW = max(uSize.x * 0.5, 0.0001);
  float halfH = max(uSize.y * 0.5, 0.0001);
  vec4 result = vec4(0.0);
  float baseRow = floor(fragCoord.y / spacing);

  for (int rowOffset = -1; rowOffset <= 1; rowOffset++) {
    float row = baseRow + float(rowOffset);
    if (row < 0.0) {
      continue;
    }

    float centerY = row * spacing;
    if (centerY > limitY) {
      continue;
    }

    float offsetX = mod(row, 2.0) < 0.5 ? 0.0 : spacing * 0.5;
    float baseColumn = floor((fragCoord.x - offsetX) / spacing);

    for (int colOffset = -1; colOffset <= 1; colOffset++) {
      float column = baseColumn + float(colOffset);
      float centerX = column * spacing + offsetX;
      vec2 center = vec2(centerX, centerY);

      vec2 normalizedCenter = vec2(
        (centerX - fadeCenter.x) / halfW,
        (centerY - fadeCenter.y) / halfH
      );
      float radialFade = saturate(
        1.0 - length(normalizedCenter) / uGrainFadeRadius
      );
      if (radialFade <= 0.0) {
        continue;
      }

      float noise = hash12(vec2(column + 1.0, row));
      if (noise < uGrainNoiseThreshold) {
        continue;
      }

      float radius = minRadius + noise * maxRadiusDelta;
      float coverage = circleCoverage(fragCoord, center, radius);
      if (coverage <= 0.0) {
        continue;
      }

      float alpha =
          (noise - uGrainNoiseThreshold) *
          uGrainOpacityScale *
          radialFade *
          coverage;
      float colorMix = saturate(noise * uGrainColorLerpScale);
      vec3 rgb = mix(uGrainFrom.rgb, uGrainTo.rgb, colorMix);
      result = composite(result, vec4(rgb * alpha, alpha));
    }
  }

  return result;
}

vec4 halftoneLayer(vec2 fragCoord) {
  float spacing = uHalftoneSpacing * uPixelScale;
  float baseRadius = uHalftoneBaseRadius * uPixelScale;
  float radiusGrowth = uHalftoneRadiusGrowth * uPixelScale;

  float startY = uSize.y * uHalftoneStartYFactor;
  float heightSpan = max(uSize.y - startY, 0.0001);
  if (
    fragCoord.y < startY - spacing ||
    fragCoord.y > uSize.y + spacing
  ) {
    return vec4(0.0);
  }

  float aspectRatio = uSize.x / max(uSize.y, 0.0001);
  float landscapeFactor = clamp(aspectRatio - 1.0, 0.0, 1.8);
  float curveDepth =
      uSize.y *
      uHalftoneConvexCurveDepthFactor *
      (1.0 + landscapeFactor * uHalftoneLandscapeCurveBoost);
  float exponent = clamp(
    uHalftoneCurveExponent - landscapeFactor * uHalftoneLandscapeExponentPull,
    0.7,
    4.0
  );
  vec4 result = vec4(0.0);
  float baseRow = floor((fragCoord.y - startY) / spacing);

  for (int rowOffset = -2; rowOffset <= 2; rowOffset++) {
    float row = baseRow + float(rowOffset);
    if (row < 0.0) {
      continue;
    }

    float centerY = startY + row * spacing;
    if (centerY > uSize.y + spacing) {
      continue;
    }

    float normalized = saturate((centerY - startY) / heightSpan);
    float contrastFactor = 1.0 - normalized;
    float alphaBase = saturate(
      uHalftoneOpacityBase + contrastFactor * uHalftoneOpacityGrowth
    );
    float colorMix = saturate(contrastFactor * uHalftoneColorLerpScale);
    vec3 rgb = mix(uHalftoneBottom.rgb, uHalftoneTop.rgb, colorMix);
    float offsetX = mod(row, 2.0) < 0.5 ? 0.0 : spacing * 0.5;
    float baseColumn = floor((fragCoord.x - offsetX) / spacing);

    for (int colOffset = -2; colOffset <= 2; colOffset++) {
      float column = baseColumn + float(colOffset);
      float centerX = column * spacing + offsetX;
      float centerDistance = clamp(
        abs(centerX - (uSize.x * 0.5)) / max(uSize.x * 0.5, 0.0001),
        0.0,
        1.0
      );
      float edgeLift = 1.0 - pow(centerDistance, exponent);
      float localStartY = startY + curveDepth * edgeLift;
      if (centerY < localStartY) {
        continue;
      }

      float availableDepth = uSize.y - localStartY;
      float frontierNormalized = availableDepth <= 0.0
          ? 1.0
          : saturate((centerY - localStartY) / availableDepth);
      float radius = baseRadius +
          frontierNormalized * radiusGrowth;
      float coverage = circleCoverage(fragCoord, vec2(centerX, centerY), radius);
      if (coverage <= 0.0) {
        continue;
      }

      float alpha = alphaBase * coverage;
      result = composite(result, vec4(rgb * alpha, alpha));
    }
  }

  return result;
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec4 grain = grainLayer(fragCoord);
  vec4 halftone = halftoneLayer(fragCoord);
  fragColor = composite(grain, halftone);
}
