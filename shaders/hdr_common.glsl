#ifndef HDR_COMMON_GLSL_H
#define HDR_COMMON_GLSL_H

const float HDR_SCALE_MAX = 7.96875;
const float HDR_SCALE_STEPS = 32.0;
const float HDR_ALPHA_STEPS = 255.0;

// RGBM-style HDR packing into RGBA8: alpha stores a shared multiplier in 1/32 steps (up to
// HDR_SCALE_MAX), rgb the color divided by it. Values above HDR_SCALE_MAX are clipped.
float encode_hdr_scale(float scale) {
  return scale * HDR_SCALE_STEPS / HDR_ALPHA_STEPS;
}

float decode_hdr_scale(float alpha) {
  return floor(alpha * HDR_ALPHA_STEPS + 0.5) / HDR_SCALE_STEPS;
}

vec3 unpack_hdr(vec4 packed) {
  return packed.rgb * max(decode_hdr_scale(packed.a), 1.0);
}

vec4 pack_hdr(vec3 hdr) {
  vec3 positive = max(hdr, vec3(0.0));
  float peak = max(max(positive.r, positive.g), positive.b);
  // Round the multiplier up to the stored step first and divide by that same value, so
  // decoding returns exactly the packed color (up to 8-bit rounding of rgb).
  float scale = max(1.0, ceil(min(peak, HDR_SCALE_MAX) * HDR_SCALE_STEPS) / HDR_SCALE_STEPS);
  return vec4(min(positive / scale, vec3(1.0)), encode_hdr_scale(scale));
}

vec3 aces_fitted(vec3 x) {
  const mat3 aces_input_mat = mat3(
    vec3(0.59719, 0.07600, 0.02840),
    vec3(0.35458, 0.90834, 0.13383),
    vec3(0.04823, 0.01566, 0.83777)
  );

  const mat3 aces_output_mat = mat3(
    vec3(1.60475, -0.10208, -0.00327),
    vec3(-0.53108, 1.10813, -0.07276),
    vec3(-0.07367, -0.00605, 1.07602)
  );

  x = aces_input_mat * x;
  vec3 a = x * (x + 0.0245786) - 0.000090537;
  vec3 b = x * (0.983729 * x + 0.4329510) + 0.238081;
  x = a / b;
  x = aces_output_mat * x;
  return clamp(x, 0.0, 1.0);
}

vec3 tone_mapping_aces(vec3 hdr, float exposure) {
  vec3 mapped = aces_fitted(max(hdr, vec3(0.0)) * exposure);
  return pow(mapped, vec3(1.0 / 2.2));
}

#endif
