#include <metal_stdlib>
using namespace metal;

struct DOFUniforms {
    float4 focus; // near, far, focal distance, range (same scene units as the model)
    float4 blur;  // full width/height, full-res radius, enabled
    float4 exposure;
};
struct DOFVertexOut {
    float4 position [[position]];
    float2 uv;
};
constexpr sampler dofSampler(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler dofDepthSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

vertex DOFVertexOut dofFullscreenVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    DOFVertexOut out;
    out.position = float4(p * 2.0f - 1.0f, 0, 1);
    // Metal texture origin is top-left, unlike the original WebGL framebuffer.
    out.uv = float2(p.x, 1.0f - p.y);
    return out;
}

float circleOfConfusion(float2 uv, depth2d<float> depth, constant DOFUniforms &u) {
    float d = depth.sample(dofDepthSampler, uv);
    float z = (u.focus.x * u.focus.y) / (u.focus.y - d * (u.focus.y - u.focus.x));
    return smoothstep(0.0f, u.focus.w, abs(z - u.focus.z));
}

fragment float4 dofPrefilterFragment(DOFVertexOut in [[stage_in]], constant DOFUniforms &u [[buffer(0)]],
                                    texture2d<float> scene [[texture(0)]], depth2d<float> depth [[texture(1)]]) {
    float2 texel = 1.0f / u.blur.xy;
    float2 offsets[4] = {float2(-0.5f, -0.5f), float2(0.5f, -0.5f), float2(-0.5f, 0.5f), float2(0.5f, 0.5f)};
    float3 color = 0;
    float total = 0, coc = 0;
    for (uint i = 0; i < 4; i++) {
        float2 uv = in.uv + offsets[i] * texel;
        float3 sample = scene.sample(dofSampler, uv).rgb;
        float weight = 1.0f / (1.0f + dot(sample, float3(0.3333f)));
        color += sample * weight;
        total += weight;
        coc += circleOfConfusion(uv, depth, u);
    }
    return float4(color / total, coc * 0.25f);
}

fragment float4 dofBokehFragment(DOFVertexOut in [[stage_in]], constant DOFUniforms &u [[buffer(0)]],
                                texture2d<float> prefiltered [[texture(0)]]) {
    constexpr uint taps = 24; // Original Medium quality.
    float4 center = prefiltered.sample(dofSampler, in.uv);
    float coc = center.a;
    float radius = coc * u.blur.z * 0.5f;
    if (radius < 0.5f) return center;
    float noise = fract(52.9829189f * fract(dot(in.position.xy, float2(0.06711056f, 0.00583715f))));
    float angle = noise * 2.0f * M_PI_F;
    float2 dir = float2(cos(angle), sin(angle));
    float2 texel = 1.0f / float2(prefiltered.get_width(), prefiltered.get_height());
    float3 color = center.rgb;
    float total = 1;
    for (uint i = 0; i < taps; i++) {
        float r = sqrt((float(i) + 0.5f) / float(taps));
        dir = float2(-0.7373688f * dir.x - 0.6754903f * dir.y,
                      0.6754903f * dir.x - 0.7373688f * dir.y);
        float4 sample = prefiltered.sample(dofSampler, in.uv + dir * (r * radius) * texel);
        // A sharp sample contributes only if its own blur circle reaches this pixel.
        float weight = smoothstep(r * coc - 0.08f, r * coc + 0.02f, sample.a);
        color += sample.rgb * weight;
        total += weight;
    }
    return float4(color / total, coc);
}

fragment float4 dofFillFragment(DOFVertexOut in [[stage_in]], constant DOFUniforms &u [[buffer(0)]],
                               texture2d<float> bokeh [[texture(0)]]) {
    float4 center = bokeh.sample(dofSampler, in.uv);
    float gap = center.a * u.blur.z * 0.5f * (0.9f / sqrt(24.0f));
    float2 offset = max(gap, 0.5f) / float2(bokeh.get_width(), bokeh.get_height());
    float3 color = center.rgb * 2.0f;
    color += bokeh.sample(dofSampler, in.uv + offset).rgb;
    color += bokeh.sample(dofSampler, in.uv - offset).rgb;
    color += bokeh.sample(dofSampler, in.uv + float2(offset.x, -offset.y)).rgb;
    color += bokeh.sample(dofSampler, in.uv + float2(-offset.x, offset.y)).rgb;
    return float4(color / 6.0f, center.a);
}

fragment float4 dofCompositeFragment(DOFVertexOut in [[stage_in]], constant DOFUniforms &u [[buffer(0)]],
                                    texture2d<float> scene [[texture(0)]], depth2d<float> depth [[texture(1)]],
                                    texture2d<float> blurred [[texture(2)]]) {
    float3 color = scene.sample(dofSampler, in.uv).rgb;
    if (u.blur.w > 0) {
        float coc = circleOfConfusion(in.uv, depth, u);
        // Preserve the full-resolution focal plane until the blur spans ~2 pixels.
        float blend = saturate((coc * u.blur.z - 0.6f) / 1.6f);
        if (blend > 0) color = mix(color, blurred.sample(dofSampler, in.uv).rgb, blend);
    }
    return float4(color * u.exposure.x, 1);
}
