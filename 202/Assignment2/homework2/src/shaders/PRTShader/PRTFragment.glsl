#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D uSampler;

varying vec3 vColor;
varying highp vec2 vTextureCoord;


void main(void) {
  gl_FragColor = vec4(vColor, 1.0);
}
