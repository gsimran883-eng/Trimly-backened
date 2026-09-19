#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D uTexture;
uniform float uBrightness;
uniform float uContrast;
uniform float uSaturation;
uniform float uGrayscale;
uniform float uSepia;

out vec4 fragColor;

vec3 applySaturation(vec3 color, float saturation) {
  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  return mix(vec3(luma), color, saturation);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 source = texture(uTexture, uv);
  vec3 color = source.rgb;

  color += vec3(uBrightness);
  color = ((color - 0.5) * uContrast) + 0.5;
  color = applySaturation(color, uSaturation);

  float gray = dot(color, vec3(0.299, 0.587, 0.114));
  color = mix(color, vec3(gray), clamp(uGrayscale, 0.0, 1.0));

  vec3 sepiaColor = vec3(
    dot(color, vec3(0.393, 0.769, 0.189)),
    dot(color, vec3(0.349, 0.686, 0.168)),
    dot(color, vec3(0.272, 0.534, 0.131))
  );
  color = mix(color, sepiaColor, clamp(uSepia, 0.0, 1.0));

  color = clamp(color, 0.0, 1.0);
  fragColor = vec4(color, source.a);
}
