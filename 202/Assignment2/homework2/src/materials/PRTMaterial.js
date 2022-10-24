class PRTMaterial extends Material {
    constructor(color, precomputeL, vertexShader, fragmentShader) {
        let LightSHC = getMat3ValueFromRGB(precomputeL)
        super({
            // Albedo
            'uSampler': { type: 'texture', value: color },
            
            //PRT
            'aPrecomputeLR': {type: 'matrix3fv', value: LightSHC[0]},
            'aPrecomputeLG': {type: 'matrix3fv', value: LightSHC[1]},
            'aPrecomputeLB': {type: 'matrix3fv', value: LightSHC[2]}

        }, ['aPrecomputeLT'], vertexShader, fragmentShader, null);
    }
}

async function buildPRTMaterial(color, precomputeL , vertexPath, fragmentPath) {


    let vertexShader = await getShaderString(vertexPath);
    let fragmentShader = await getShaderString(fragmentPath);

    return new PRTMaterial(color, precomputeL,  vertexShader, fragmentShader);
}