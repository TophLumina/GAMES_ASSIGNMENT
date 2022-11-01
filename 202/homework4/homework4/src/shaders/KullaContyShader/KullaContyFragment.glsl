#ifdef GL_ES
precision mediump float;
#endif

uniform vec3 uLightPos;
uniform vec3 uCameraPos;
uniform vec3 uLightRadiance;
uniform vec3 uLightDir;

uniform sampler2D uAlbedoMap;
uniform float uMetallic;
uniform float uRoughness;
uniform sampler2D uBRDFLut;
uniform sampler2D uEavgLut;
uniform samplerCube uCubeTexture;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;

const float PI = 3.14159265359;

float DistributionGGX(vec3 N, vec3 H, float roughness)
{
   // TODO: To calculate GGX NDF here
   float alpha = roughness * roughness;
   float alpha2 = alpha * alpha;

   float NdotH = dot(N, H);
   float NdotH2 = NdotH * NdotH;

   float GGX = alpha2 / (PI * pow(NdotH2 * (alpha2 - 1.0) + 1.0, 2.0));

   return GGX;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    // TODO: To calculate Schlick G1 here
    NdotV = clamp(NdotV, 0.0, 1.0);
    float k = roughness * roughness / 2.0;

    float SchlickGGX = NdotV / (NdotV * (1.0 - k) + k);
    return SchlickGGX;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    // TODO: To calculate Smith G here
    float GGX1 = GeometrySchlickGGX(dot(N, V), roughness);
    float GGX2 = GeometrySchlickGGX(dot(N, L), roughness);

    return GGX1 * GGX2;
}

vec3 fresnelSchlick(vec3 F0, vec3 V, vec3 H)
{
    // TODO: To calculate Schlick F here
    return F0 + (1.0 - F0) * pow((1.0 - dot(V, H)), 5.0);
}


//https://blog.selfshadow.com/publications/s2017-shading-course/imageworks/s2017_pbs_imageworks_slides_v2.pdf
vec3 AverageFresnel(vec3 r, vec3 g)
{
    return vec3(0.087237) + 0.0230685*g - 0.0864902*g*g + 0.0774594*g*g*g
           + 0.782654*r - 0.136432*r*r + 0.278708*r*r*r
           + 0.19744*g*r + 0.0360605*g*g*r - 0.2586*g*r*r;
}

vec3 MultiScatterBRDF(float NdotL, float NdotV)
{
  vec3 albedo = pow(texture2D(uAlbedoMap, vTextureCoord).rgb, vec3(2.2));

  vec3 E_o = texture2D(uBRDFLut, vec2(NdotL, uRoughness)).xyz;
  vec3 E_i = texture2D(uBRDFLut, vec2(NdotV, uRoughness)).xyz;

  vec3 E_avg = texture2D(uEavgLut, vec2(0, uRoughness)).xyz;
  // copper
  vec3 edgetint = vec3(0.827, 0.792, 0.678);
  vec3 F_avg = AverageFresnel(albedo, edgetint);
  
  // TODO: To calculate fms and missing energy here
  vec3 F_ms = (1.0 - E_o) * (1.0 - E_i) / (PI * (1.0 - E_avg));
  vec3 F_add = F_avg * E_avg / (1.0 - F_avg * (1.0 - E_avg));

  return F_add * F_ms;
}

void main(void) {
  vec3 albedo = pow(texture2D(uAlbedoMap, vTextureCoord).rgb, vec3(2.2));

  vec3 N = normalize(vNormal);
  vec3 V = normalize(uCameraPos - vFragPos);
  float NdotV = max(dot(N, V), 0.0);

  vec3 F0 = vec3(0.04); 
  F0 = mix(F0, albedo, uMetallic);

  vec3 Lo = vec3(0.0);

  // calculate per-light radiance
  vec3 L = normalize(uLightDir);
  vec3 H = normalize(V + L);
  float distance = length(uLightPos - vFragPos);
  float attenuation = 1.0 / (distance * distance);
  vec3 radiance = uLightRadiance;

  float NDF = DistributionGGX(N, H, uRoughness);   
  float G   = GeometrySmith(N, V, L, uRoughness);
  vec3 F = fresnelSchlick(F0, V, H);
      
  vec3 numerator    = NDF * G * F; 
  float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0);
  vec3 Fmicro = numerator / max(denominator, 0.001); 
  
  float NdotL = max(dot(N, L), 0.0);        

  vec3 Fms = MultiScatterBRDF(NdotL, NdotV);
  vec3 BRDF = Fmicro + Fms;
  
  Lo += BRDF * radiance * NdotL;
  vec3 color = Lo;
  
  color = color / (color + vec3(1.0));
  color = pow(color, vec3(1.0/2.2)); 
  gl_FragColor = vec4(color, 1.0);

}