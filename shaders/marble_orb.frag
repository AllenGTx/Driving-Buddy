#version 460 core

#include <flutter/runtime_effect.glsl>

// Per-pixel Volumetric Studio Glass Weather Orb (Marble Spec)
// Uniform layout:
//  0..1 : uSize (width, height in px)
//  2..3 : uCenter (cx, cy in px)
//  4    : uRadius (orb radius in px)
//  5    : uPhase (integrated fog phase: phase += dt * speed)
//  6    : uEnergy (eased state & voice energy + press flare)
//  7..8 : uPointer (eased pointer offset -1..1)
//  9..11: uDeep (linear RGB deep state color)
// 12..14: uBright (linear RGB bright state color)
// 15..17: uRim (linear RGB rim state color)

uniform vec2 uSize;
uniform vec2 uCenter;
uniform float uRadius;
uniform float uPhase;
uniform float uEnergy;
uniform vec2 uPointer;
uniform vec3 uDeep;
uniform vec3 uBright;
uniform vec3 uRim;

out vec4 fragColor;

float hash31(vec3 p) {
  p = fract(p * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.x + p.y) * p.z);
}

float hash21(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Smooth 3D value noise
float vnoise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  vec3 u = f * f * (3.0 - 2.0 * f);

  float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
  float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
  float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
  float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
  float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
  float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
  float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
  float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

  float nx00 = mix(n000, n100, u.x);
  float nx10 = mix(n010, n110, u.x);
  float nx01 = mix(n001, n101, u.x);
  float nx11 = mix(n011, n111, u.x);

  float nxy0 = mix(nx00, nx10, u.y);
  float nxy1 = mix(nx01, nx11, u.y);

  return mix(nxy0, nxy1, u.z);
}

// Three octaves of value noise: weights 0.55, 0.30, 0.15 at 1x, 2.1x, 4.3x
float fbm3(vec3 p) {
  return 0.55 * vnoise(p)
       + 0.30 * vnoise(p * 2.1 + vec3(1.7, 9.2, 3.4))
       + 0.15 * vnoise(p * 4.3 + vec3(8.3, 2.8, 5.1));
}

float sdRoundRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + vec2(r);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // Convert to studio orb space where +x is right and +y is UP (matching WebGL)
  vec2 p = vec2((frag.x - uCenter.x) / uRadius, (uCenter.y - frag.y) / uRadius);
  float r2 = dot(p, p);
  float r = sqrt(r2);
  float aa = 2.0 / max(uRadius, 1.0);

  // Outside atmosphere: outer bloom exp(-(r - 1) * 4.4) + table light ellipse 1.26r below center
  float outsideDist = max(0.0, r - 1.0);
  float bloom = exp(-outsideDist * 4.4) * (0.28 + 0.18 * clamp(uEnergy, 0.0, 1.4));
  vec3 outCol = uRim * bloom;

  vec2 tableDelta = (p - vec2(0.0, -1.26)) / vec2(0.82 + 0.16 * clamp(uEnergy, 0.0, 1.2), 0.16);
  float tableFalloff = exp(-dot(tableDelta, tableDelta) * 1.65);
  float tableAlpha = tableFalloff * (0.26 + 0.16 * clamp(uEnergy, 0.0, 1.2));
  outCol += uDeep * tableAlpha;

  float outAlpha = clamp(bloom * 0.85 + tableAlpha * 0.80, 0.0, 0.88);

  // Inside the glass sphere (evaluated up to 1.0 + aa for 2px smooth silhouette anti-aliasing)
  vec3 ballCol = vec3(0.0);
  if (r < 1.0 + aa * 1.5) {
    float clampedR2 = min(r2, 0.9992);
    float z = sqrt(1.0 - clampedR2);
    vec3 normal = normalize(vec3(p.x, p.y, z));

    // 1. Refract view ray (0, 0, -1) through glass normal with ratio 1 / 1.4
    vec3 viewRay = vec3(0.0, 0.0, -1.0);
    vec3 ray = refract(viewRay, normal, 1.0 / 1.4);
    float chord = 2.0 * max(0.0, dot(-ray, normal));
    vec3 entry = vec3(p.x, p.y, z);

    // 2. Volumetric weather fog & plasma threads along 10 chord samples
    vec3 accum = uDeep * (0.16 + 0.10 * z);
    float stepLen = chord / 10.0;

    for (int i = 0; i < 10; i++) {
      float t = (float(i) + 0.5) * 0.1;
      vec3 pos = entry + ray * (chord * t);
      float distFromCenter = length(pos);

      // Twist about vertical Y axis: phase * 0.7 + y * (0.6 + energy)
      float twist = uPhase * 0.7 + pos.y * (0.6 + uEnergy);
      float ct = cos(twist);
      float st = sin(twist);
      vec3 twisted = vec3(
        pos.x * ct - pos.z * st,
        pos.y,
        pos.x * st + pos.z * ct
      );
      twisted.xy += uPointer * 0.10;

      // Sample at position * 2.1, domain-warped by second copy of 3-octave noise * 1.6
      vec3 baseCoord = twisted * 2.1;
      vec3 warp = vec3(
        fbm3(baseCoord + vec3(0.0, 0.0, uPhase * 0.18)),
        fbm3(baseCoord + vec3(5.2, 1.3, -uPhase * 0.15)),
        fbm3(baseCoord + vec3(2.8, 7.1, uPhase * 0.13))
      ) - 0.5;
      vec3 warpedCoord = baseCoord + warp * 1.6;

      float nVal = fbm3(warpedCoord);
      float density = smoothstep(0.35, 0.78, nVal);
      float shellFade = smoothstep(1.02, 0.35, distFromCenter);
      vec3 fogColor = mix(uDeep, uBright, smoothstep(0.42, 0.88, nVal));

      // 3. Living plasma threads: (1 - |2n - 1|)^10 scaled by 0.5 + energy * 2.2
      float nThread = vnoise(warpedCoord * 1.6 + vec3(uPhase * 0.12));
      float ridge = max(0.0, 1.0 - abs(2.0 * nThread - 1.0));
      float r2_ = ridge * ridge;
      float r4_ = r2_ * r2_;
      float r8_ = r4_ * r4_;
      float threads = (r8_ * r2_) * (0.5 + uEnergy * 2.2);

      vec3 sampleLight = fogColor * (density * 1.55)
                       + mix(uBright, vec3(1.0, 0.98, 0.94), 0.38) * (threads * 0.95);
      accum += sampleLight * shellFade * stepLen;
    }

    // 4. Soft studio exposure roll-off so bright states glow instead of clipping
    ballCol = 1.0 - exp(-accum * 1.32);

    // 5. Glass shell optics:
    //    - RGB edge glow of (1 - z) raised to 2.1, 2.6, 3.3
    float oneMinusZ = clamp(1.0 - z, 0.0, 1.0);
    vec3 rimSplit = vec3(
      pow(oneMinusZ, 2.1),
      pow(oneMinusZ, 2.6),
      pow(oneMinusZ, 3.3)
    );
    ballCol += rimSplit * mix(uRim, vec3(1.0), 0.25) * 0.68;

    //    - Soft rectangular studio window highlight ~0.16 x 0.09 radii, rotated 20 deg, at (-0.4, 0.47)
    vec2 winCenter = vec2(-0.40, 0.47) + uPointer * 0.05;
    vec2 hp = p - winCenter;
    float c20 = 0.9396926; // cos(20 deg)
    float s20 = 0.3420201; // sin(20 deg)
    vec2 hRot = vec2(hp.x * c20 + hp.y * s20, -hp.x * s20 + hp.y * c20);
    float winSdf = sdRoundRect(hRot, vec2(0.115, 0.062), 0.035);
    float winGlow = smoothstep(0.065, -0.025, winSdf);
    ballCol += vec3(1.0, 0.98, 0.95) * (winGlow * 0.62);

    //    - Faint round echo on the lower right
    vec2 echoDelta = p - (vec2(0.37, -0.43) - uPointer * 0.03);
    float echo = exp(-dot(echoDelta, echoDelta) / 0.026) * 0.16;
    ballCol += mix(uBright, vec3(1.0), 0.35) * echo;
  }

  // 6. Blend ball and outside across 2 pixels at the edge + 1.8% per-pixel noise to prevent banding
  float ballMask = smoothstep(1.0 + aa, 1.0 - aa, r);

  // Convert linear-ish studio light gently to display gamma for rich depth & vibrant filaments
  vec3 ballDisplay = pow(clamp(ballCol, 0.0, 1.0), vec3(0.88));
  vec3 outDisplay = pow(clamp(outCol, 0.0, 1.0), vec3(0.92));

  float dither = (hash21(frag) - 0.5) * 0.018;
  ballDisplay = clamp(ballDisplay + dither, 0.0, 1.0);
  outDisplay = clamp(outDisplay + dither * outAlpha, 0.0, 1.0);

  // Premultiplied RGBA output: inside r <= 1 alpha is 1.0 (cleanly hiding back-waves behind the glass ball!)
  vec3 premulOut = outDisplay * outAlpha;
  vec3 finalRgb = mix(premulOut, ballDisplay, ballMask);
  float finalAlpha = mix(outAlpha, 1.0, ballMask);

  fragColor = vec4(finalRgb, finalAlpha);
}
