#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D uSampler;

varying vec3 vColor;
varying highp vTextureCoord;


void main(void) {

  vec3 albedo = texture2D(uSampler, vTextureCoord);
  
  // gl_FragColor = vec4(albedo * vColor, 1.0);
  gl_FragColor = vec4(vColor, 1.0);
}
