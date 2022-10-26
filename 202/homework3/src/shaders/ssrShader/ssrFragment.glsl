#ifdef GL_ES
precision highp float;
#endif

uniform vec3 uLightDir;
uniform vec3 uCameraPos;
uniform vec3 uLightRadiance;
uniform sampler2D uGDiffuse;
uniform sampler2D uGDepth;
uniform sampler2D uGNormalWorld;
uniform sampler2D uGShadow;
uniform sampler2D uGPosWorld;

varying mat4 vWorldToScreen;
varying highp vec4 vPosWorld;

#define M_PI 3.1415926535897932384626433832795
#define TWO_PI 6.283185307
#define INV_PI 0.31830988618
#define INV_TWO_PI 0.15915494309

float Rand1(inout float p) {
  p = fract(p * .1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

vec2 Rand2(inout float p) {
  return vec2(Rand1(p), Rand1(p));
}

float InitRand(vec2 uv) {
	vec3 p3  = fract(vec3(uv.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 SampleHemisphereUniform(inout float s, out float pdf) {
  vec2 uv = Rand2(s);
  float z = uv.x;
  float phi = uv.y * TWO_PI;
  float sinTheta = sqrt(1.0 - z*z);
  vec3 dir = vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
  pdf = INV_TWO_PI;
  return dir;
}

vec3 SampleHemisphereCos(inout float s, out float pdf) {
  vec2 uv = Rand2(s);
  float z = sqrt(1.0 - uv.x);
  float phi = uv.y * TWO_PI;
  float sinTheta = sqrt(uv.x);
  vec3 dir = vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
  pdf = z * INV_PI;
  return dir;
}

void LocalBasis(vec3 n, out vec3 b1, out vec3 b2) {
  float sign_ = sign(n.z);
  if (n.z == 0.0) {
    sign_ = 1.0;
  }
  float a = -1.0 / (sign_ + n.z);
  float b = n.x * n.y * a;
  b1 = vec3(1.0 + sign_ * n.x * n.x * a, sign_ * b, -sign_ * n.x);
  b2 = vec3(b, sign_ + n.y * n.y * a, -n.y);
}

vec4 Project(vec4 a) {
  return a / a.w;
}

float GetDepth(vec3 posWorld) {
  float depth = (vWorldToScreen * vec4(posWorld, 1.0)).w;
  return depth;
}

/*
 * Transform point from world space to screen space([0, 1] x [0, 1])
 *
 */
vec2 GetScreenCoordinate(vec3 posWorld) {
  vec2 uv = Project(vWorldToScreen * vec4(posWorld, 1.0)).xy * 0.5 + 0.5;
  return uv;
}

float GetGBufferDepth(vec2 uv) {
  float depth = texture2D(uGDepth, uv).x;
  if (depth < 1e-2) {
    depth = 1000.0;
  }
  return depth;
}

vec3 GetGBufferNormalWorld(vec2 uv) {
  vec3 normal = texture2D(uGNormalWorld, uv).xyz;
  return normal;
}

vec3 GetGBufferPosWorld(vec2 uv) {
  vec3 posWorld = texture2D(uGPosWorld, uv).xyz;
  return posWorld;
}

float GetGBufferuShadow(vec2 uv) {
  float visibility = texture2D(uGShadow, uv).x;
  return visibility;
}

vec3 GetGBufferDiffuse(vec2 uv) {
  vec3 diffuse = texture2D(uGDiffuse, uv).xyz;
  diffuse = pow(diffuse, vec3(2.2));
  return diffuse;
}

/*
 * Evaluate diffuse bsdf value.
 *
 * wi, wo are all in world space.
 * uv is in screen space, [0, 1] x [0, 1].
 *
 */
vec3 EvalDiffuse(vec3 wi, vec3 wo, vec2 uv) {
  // vec3 L = vec3(0.0);
  // return L;

  vec3 albedo = GetGBufferDiffuse(uv);
  vec3 normal_world = GetGBufferNormalWorld(uv);

  // material is diffuse means pdf(wo) = 1/2PI<on semi-sphere>
  float costheta = max(dot(wi, normal_world), 0.0);
  vec3 irradience = uLightRadiance * costheta;
  vec3 radience_out = irradience * INV_TWO_PI;

  return radience_out;
}

/*
 * Evaluate directional light with shadow map
 * uv is in screen space, [0, 1] x [0, 1].
 *
 */
vec3 EvalDirectionalLight(vec2 uv) {
  // vec3 Le = vec3(0.0);
  // return Le;

  float visibility = GetGBufferuShadow(uv);
  vec3 view_dir = normalize(uCameraPos - vPosWorld.xyz);

  vec3 BRDF = EvalDiffuse(uLightDir, view_dir, uv);
  return BRDF * visibility;
}

bool RayMarch(vec3 ori, vec3 dir, out vec3 hitPos) {
  // return false;

  vec2 ori_uv = GetScreenCoordinate(ori);
  vec2 dir_uv = GetScreenCoordinate(dir);

  const int steps_num = 40;
  float single_step = 8.0 / float(steps_num) / length(dir_uv);

  for (int i = 1; i < steps_num; ++i) {
    vec3 now = ori + dir * float(i) * single_step;
    vec2 now_uv = GetScreenCoordinate(now);

    if (now_uv.x > 1.0 || now_uv.x < 0.0 || now_uv.y > 1.0 || now_uv.y < 0.0)
      return false;
    
    float depth = GetDepth(now);
    float depth_uv = GetGBufferDepth(now_uv);

    if (depth > depth_uv) {
      hitPos = now;
      return true;
    }
  }

  return false;
}

#define SAMPLE_NUM 256

void main() {
  float s = InitRand(gl_FragCoord.xy);

  vec3 L = vec3(0.0);
  // L = GetGBufferDiffuse(GetScreenCoordinate(vPosWorld.xyz));
  vec2 uv = GetScreenCoordinate(vPosWorld.xyz);
  vec3 L_d = EvalDirectionalLight(uv) * GetGBufferDiffuse(uv);

  vec3 L_i = vec3(0.0);
  for (int i = 0; i < SAMPLE_NUM; ++i) {
    float pdf;
    vec3 sdir_local = SampleHemisphereUniform(s, pdf);

    vec3 normal_world = GetGBufferNormalWorld(uv);
    vec3 t;
    vec3 bt;
    LocalBasis(normal_world, t, bt);
    t = normalize(t);
    bt = normalize(bt);
    mat3 TBN = mat3(t, bt, normal_world);
    vec3 sdir_world = TBN * sdir_local;

    vec3 intersection;
    if (RayMarch(vPosWorld.xyz, sdir_world, intersection)) {
      vec2 uv_int = GetScreenCoordinate(intersection);
      L_i += EvalDirectionalLight(uv_int) * GetGBufferDiffuse(uv_int) * EvalDiffuse(normalize(intersection - vPosWorld.xyz), normalize(uCameraPos - vPosWorld.xyz), uv) / pdf;
    }
  }

  L_i /= float(SAMPLE_NUM);

  L += L_d + L_i;

  vec3 color = pow(clamp(L, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
  gl_FragColor = vec4(vec3(color.rgb), 1.0);
}
