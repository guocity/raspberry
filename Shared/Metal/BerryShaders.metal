#include <metal_stdlib>
using namespace metal;

struct BerryVertexIn {
    float3 position   [[attribute(0)]];
    float3 normal     [[attribute(1)]];
    float2 uv         [[attribute(2)]];
    float4 color      [[attribute(3)]]; // R=free, G=depth, B=rand, A=dome
    float3 center     [[attribute(4)]]; // 3D center of drupelet in model space
};

struct BerryVertexOut {
    float4 position [[position]];
    float2 uv;
    float3 modelPos;
    float3 worldPos;
    float3 normalModel;
    float3 center;
};

struct Light {
    float3 direction;
    float3 color;
};

struct BerryUniforms {
    float4x4 modelViewProjection;
    float3x3 modelRotation;
    float3   cameraPosition;
    Light    lights[3];        // Key, Fill, Rim
    
    // Skin & Translucency
    float3   tint;
    float    sss;
    float    beadGlow;
    float    seeThrough;
    float3   transColor;
    float    transDepth;
    float    roughnessScale;
    float    roughnessBias;
    float    specular;
    float    aoPower;
    float    tScale[9];        // Spherical Harmonics transfer scales
    
    // Core Cavity Lamp
    float3   innerPos;
    float3   innerColor;
    float    innerWall;
    float3   berryCenter;
};

inline float3 decodeTransfer(float4 texSample, float scale) {
    float3 v = texSample.rgb * 2.0 - 1.0;
    return sign(v) * v * v * scale;
}

vertex BerryVertexOut berryVertexShader(BerryVertexIn in [[stage_in]],
                                        constant BerryUniforms &u [[buffer(0)]]) {
    BerryVertexOut out;
    out.uv = in.uv;
    out.modelPos = in.position;
    out.center = in.center;
    out.normalModel = in.normal;
    out.worldPos = (u.modelRotation * in.position);
    out.position = u.modelViewProjection * float4(in.position, 1.0);
    return out;
}

fragment float4 berryFragmentShader(BerryVertexOut in [[stage_in]],
                                    constant BerryUniforms &u [[buffer(0)]],
                                    texture2d<float> tORM     [[texture(0)]],
                                    texture2d<float> tNormal  [[texture(1)]],
                                    texture2d<float> tT0      [[texture(2)]],
                                    texture2d<float> tT1      [[texture(3)]],
                                    texture2d<float> tT2      [[texture(4)]],
                                    texture2d<float> tT3      [[texture(5)]],
                                    sampler s [[sampler(0)]])
{
    float3 V = normalize(u.cameraPosition - in.worldPos);
    float3 orm = tORM.sample(s, in.uv).rgb;
    float ao = pow(orm.r, u.aoPower);
    float roughness = clamp(orm.g * u.roughnessScale + u.roughnessBias, 0.045, 1.0);
    
    // 1. Evaluate Precomputed Radiance Transfer (SH9 diffuse subsurface)
    float3 sss = decodeTransfer(tT0.sample(s, in.uv), u.tScale[0]) * 0.282095;
    sss += decodeTransfer(tT1.sample(s, in.uv), u.tScale[1]) * 0.488603;
    sss += decodeTransfer(tT2.sample(s, in.uv), u.tScale[2]) * 0.488603;
    sss += decodeTransfer(tT3.sample(s, in.uv), u.tScale[3]) * 0.488603;
    sss = max(sss * u.sss * u.tint, float3(0.0));

    // 2. Analytical Turbid Bead Translucency (Beer-Lambert Absorption)
    float3 toC = in.center - in.modelPos;
    float beadR = max(length(toC), 1e-3);
    float3 nS = -toC / beadR;
    float3 sigma = -log(clamp(u.transColor, float3(0.002), float3(0.999))) / u.transDepth;

    float3 bead = float3(0.0);
    for (int i = 0; i < 3; i++) {
        float3 Lm = transpose(u.modelRotation) * u.lights[i].direction;
        float nl = dot(nS, Lm);
        float chord = 2.0 * beadR * max(-nl, 0.0) + 0.10;
        float past = smoothstep(0.45, -0.30, nl);
        bead += u.lights[i].color * exp(-sigma * chord) * past;
    }
    bead *= u.beadGlow * (0.3 + 0.7 * ao);

    // 3. Hollow Core Cavity Lamp
    float3 coreGlow = float3(0.0);
    if (dot(u.innerColor, float3(1.0)) > 0.0) {
        float3 toL = u.innerPos - in.modelPos;
        float d2 = max(dot(toL, toL), 1e-4);
        float chord = u.innerWall * (1.0 - orm.b);
        coreGlow = u.innerColor * exp(-sigma * chord) / (4.0 * 3.14159 * d2);
    }

    // 4. Combine terms
    float3 finalColor = sss + bead + coreGlow;
    return float4(finalColor, 1.0);
}
