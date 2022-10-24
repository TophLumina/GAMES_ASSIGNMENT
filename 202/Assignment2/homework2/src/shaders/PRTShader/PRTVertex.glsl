attribute vec3 aVertexPosition;
attribute vec2 aTextureCoord;
attribute mat3 aPrecomputeLT;

uniform mat4 uModelMatrix;
uniform mat4 uViewMatrix;
uniform mat4 uProjectionMatrix;

// PRT
uniform mat3 aPrecomputeLR;
uniform mat3 aPrecomputeLG;
uniform mat3 aPrecomputeLB;

varying vec3 vColor;

varying highp vec2 vTextureCoord;

void main(void) {
  gl_Position = uProjectionMatrix * uViewMatrix * uModelMatrix *
                vec4(aVertexPosition, 1.0);

  vTextureCoord = aTextureCoord;

  vec3 vC = vec3(0.0, 0.0, 0.0);
  for(int i = 0; i < 3; i++){
    vC += vec3(dot(aPrecomputeLR[i], aPrecomputeLT[i]), dot(aPrecomputeLG[i], aPrecomputeLT[i]), dot(aPrecomputeLB[i], aPrecomputeLT[i]));
  }

  vColor = vC;
}