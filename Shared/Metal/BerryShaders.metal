#include <metal_stdlib>
using namespace metal;

struct BerryUniforms {
    float4x4 mvp;
    float4x4 model;
    float4 camera;
    float4 lightDirections[3];
    float4 lightColors[3];
    float4 sh[9];
    float4 skin;              // SSS, bead glow, absorption depth, roughness multiplier
    float4 innerPosition;     // position, wall thickness
    float4 innerColor;
    float4 transmission;
    float4 viewport;          // width, height, hair width, halo
    float4 ambient;
    float4 material;         // roughness bias, pore strength/scale, specular
    float4 sheen;
    float4 effects;          // see-through, seed visibility, AO power, reflections
    float4 fuzz;             // color, opacity
    float4 surface;          // styles brightness/specular, min hair pixels, ambient gradient
};
struct BerryVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float4 mask [[attribute(3)]];
    float3 center [[attribute(4)]];
};
struct BerryVertexOut {
    float4 position [[position]];
    float3 modelPosition;
    float3 worldPosition;
    float3 normal;
    float2 uv;
    float4 mask;
    float3 center;
};
constexpr sampler atlasSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
constexpr sampler detailSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);

float3x3 rotation(constant BerryUniforms &u) {
    return float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
}
float3 neutralToneMap(float3 color) {
    color = max(color, 0.0f);
    float x = min(color.r, min(color.g, color.b));
    color -= x < 0.08f ? x - 6.25f * x * x : 0.04f;
    float peak = max(color.r, max(color.g, color.b));
    if (peak < 0.76f) return color;
    float compressed = 1.0f - 0.0576f / (peak - 0.52f);
    color *= compressed / peak;
    float desaturation = 1.0f - 1.0f / (0.15f * (peak - compressed) + 1.0f);
    return mix(color, float3(compressed), desaturation);
}
float3 irradiance(float3 n, constant BerryUniforms &u) {
    float x = n.x, y = n.y, z = n.z;
    float3 e = M_PI_F * 0.282095f * u.sh[0].rgb;
    e += 2.094395f * 0.488603f * (y*u.sh[1].rgb + z*u.sh[2].rgb + x*u.sh[3].rgb);
    e += 0.785398f * (1.092548f * (x*y*u.sh[4].rgb + y*z*u.sh[5].rgb + x*z*u.sh[7].rgb)
         + 0.315392f * (3*z*z-1)*u.sh[6].rgb + 0.546274f*(x*x-y*y)*u.sh[8].rgb);
    return max(e, 0.0f);
}
float3 studioEnvironment(float3 direction, float roughness, constant BerryUniforms &u) {
    float3 result = u.ambient.rgb;
    float spread = 0.32f + roughness * roughness * 0.8f;
    for (int i = 0; i < 3; i++) {
        float3 light = u.lightDirections[i].xyz;
        if (u.lightDirections[i].w > 0) {
            // Original reel strip lights retain their angular size and stretch.
            float3 right = normalize(cross(float3(0,1,0), light));
            float3 up = cross(light, right);
            float stretch = max(u.lightColors[i].w, 0.1f);
            float radius = tan(u.lightDirections[i].w) + roughness * roughness * 0.8f;
            float2 p = float2(dot(direction,right), dot(direction,up) / stretch)
                     / max(dot(direction,light), 0.001f);
            float shape = exp(-pow(length(p) / radius, 4.0f));
            result += u.lightColors[i].rgb * shape / (M_PI_F * radius * radius * stretch);
        } else {
            float angle = acos(clamp(dot(direction, light), -1.0f, 1.0f));
            result += u.lightColors[i].rgb * (exp(-pow(angle / spread, 4.0f)) / (M_PI_F * spread * spread));
        }
    }
    return result * u.effects.w;
}
float3 decodeTransfer(float3 sample, float scale) {
    float3 v = sample * 2.0f - 1.0f;
    return sign(v) * v * v * scale;
}
vertex BerryVertexOut berryVertexShader(BerryVertexIn in [[stage_in]], constant BerryUniforms &u [[buffer(1)]]) {
    BerryVertexOut out;
    out.position = u.mvp * float4(in.position, 1);
    out.modelPosition = in.position;
    out.worldPosition = (u.model * float4(in.position, 1)).xyz;
    out.normal = in.normal;
    out.uv = in.uv;
    out.mask = in.mask;
    out.center = in.center;
    return out;
}
fragment float4 berryFragmentShader(BerryVertexOut in [[stage_in]], bool front [[front_facing]],
                                    constant BerryUniforms &u [[buffer(1)]],
                                    texture2d<float> albedo [[texture(0)]],
                                    texture2d<float> normalMap [[texture(1)]],
                                    texture2d<float> ormMap [[texture(2)]],
                                    texture2d<float> detailMap [[texture(3)]],
                                    array<texture2d<float>, 9> transfer [[texture(4)]]) {
    if (!front) return float4(neutralToneMap(float3(0.030f, 0.0008f, 0.0015f) * u.sh[0].rgb * 0.282095f), 1);
    float3 nBase = normalize(normalMap.sample(atlasSampler, in.uv).xyz * 2.0f - 1.0f);
    float3 w = pow(abs(nBase), 4.0f);
    w /= max(w.x + w.y + w.z, 0.0001f);
    float3 q = in.modelPosition / 0.26086956f * u.material.z;
    float4 dx = detailMap.sample(detailSampler, q.zy);
    float4 dy = detailMap.sample(detailSampler, q.xz);
    float4 dz = detailMap.sample(detailSampler, q.xy);
    float3 dn = w.x * float3(0, dx.y*2-1, dx.x*2-1)
              + w.y * float3(dy.x*2-1, 0, dy.y*2-1)
              + w.z * float3(dz.x*2-1, dz.y*2-1, 0);
    float pore = dot(w, float3(dx.a, dy.a, dz.a));
    float3 nModel = normalize(nBase + dn * u.material.y);
    float3x3 rot = rotation(u);
    float3 N = normalize(rot * nModel);
    float3 Ng = normalize(rot * nBase);
    float3 V = normalize(u.camera.xyz - in.worldPosition);
    float NoV = saturate(dot(N, V));
    float3 orm = ormMap.sample(atlasSampler, in.uv).rgb;
    float ao = pow(orm.r, u.effects.z);
    float roughness = clamp(orm.g * u.skin.w + u.material.x, 0.045f, 1.0f);
    constexpr float scales[9] = {0.175415039f, 0.161254883f, 0.156372070f, 0.157470703f,
                               0.056762695f, 0.055755615f, 0.067382813f, 0.056823730f, 0.060729980f};
    float3 sss = 0;
    for (int i = 0; i < 9; i++) sss += decodeTransfer(transfer[i].sample(atlasSampler, in.uv).rgb, scales[i]) * u.sh[i].rgb;
    sss = max(sss, 0.0f);
    float3 toCenter = in.center - in.modelPosition;
    float beadRadius = max(length(toCenter), 0.001f);
    float3 beadNormal = -toCenter / beadRadius;
    float3 viewModel = transpose(rot) * V;
    float3 outward = normalize(in.center - float3(0, 1.12f, 0));
    float3 sigma = -log(clamp(u.transmission.rgb, 0.002f, 0.999f)) / max(u.skin.z, 0.001f);
    float open = 0.3f + 0.7f * ao;
    float3 bead = 0;
    for (int i = 0; i < 3; i++) {
        float3 light = transpose(rot) * u.lightDirections[i].xyz;
        float nl = dot(beadNormal, light);
        float chord = 2.0f * beadRadius * max(-nl, 0.0f) + 0.10f;
        float past = 1.0f - smoothstep(-0.30f, 0.45f, nl);
        float reach = smoothstep(-0.45f, 0.20f, dot(outward, light));
        bead += u.lightColors[i].rgb * exp(-sigma * chord) * past * reach;
    }
    bead *= 0.07f * u.skin.y * open;
    float3 refracted = refract(-viewModel, nBase, 1.0f / 1.33f);
    float chordView = max(2.0f * dot(toCenter, refracted), 0.0f);
    float3 exitPoint = in.modelPosition + refracted * chordView;
    float leave = smoothstep(-0.15f, 0.45f, dot(normalize(exitPoint-float3(0,1.12f,0)), refracted))
                * smoothstep(0.30f, 0.85f, 1.0f-saturate(dot(outward,viewModel)))
                * smoothstep(0.12f,0.60f,ao);
    float3 through = studioEnvironment(rot*refracted, 0.6f, u) * exp(-sigma*(chordView+0.06f))
                   * leave * (0.25f+0.75f*in.mask.r) * 0.55f * u.effects.x;
    float sb = dot(toCenter, refracted);
    float seedHeight = sb*sb - (beadRadius*beadRadius - 0.085f*0.085f);
    float seedHit = smoothstep(0.0f, 0.085f*0.085f*0.9f, seedHeight) * step(0.0f,sb);
    float seedDistance = max(sb - sqrt(max(seedHeight,0.0f)),0.0f);
    float3 seedLight = irradiance(beadNormal,u) * (0.5f/M_PI_F)*open + bead*2;
    float3 seed = float3(0.80f,0.56f,0.30f)*seedLight*exp(-sigma*(seedDistance+0.03f))*seedHit*0.25f*u.effects.y;
    float3 glow = bead + through + seed;
    if (dot(u.innerColor.rgb, float3(1)) > 0) {
        float3 toLight = u.innerPosition.xyz - in.modelPosition;
        float d2 = max(dot(toLight,toLight),0.0001f);
        float facing = dot(nBase,toLight*rsqrt(d2));
        float flesh = max(u.innerPosition.w-in.mask.g*0.7f,0.0f)*(0.6f+0.8f*orm.b);
        float seedShadow = 1.0f-0.4f*smoothstep(0.80f,1.0f,in.mask.a);
        float3 crossed = exp(-sigma*flesh)*(0.30f+0.20f*max(-facing,0.0f))*seedShadow;
        float3 lit = albedo.sample(atlasSampler,in.uv).rgb * max(facing,0.0f)*smoothstep(0.3f,0.6f,in.mask.g)*0.14f;
        glow += u.innerColor.rgb*(crossed+lit)/(M_PI_F*(d2+0.03f));
    }
    float3 diffuse = sss*u.skin.x*(1.0f-0.35f*leave)+glow;
    float3 reflected = normalize(mix(reflect(-V,N), N, roughness*roughness));
    float4 brdfR = roughness*float4(-1,-0.0275f,-0.572f,0.022f)+float4(1,0.0425f,1.04f,-0.04f);
    float a004 = min(brdfR.x*brdfR.x,exp2(-9.28f*NoV))*brdfR.x+brdfR.y;
    float2 brdf = float2(-1.04f,1.04f)*a004+brdfR.zw;
    float occlusion = saturate(pow(NoV+ao,exp2(-16*roughness-1))-1+ao);
    float horizon = saturate(1+dot(reflected,Ng));
    occlusion *= horizon*horizon*smoothstep(-0.35f,0.15f,dot(transpose(rot)*reflected,outward));
    float3 specular = studioEnvironment(reflected,roughness,u)*(u.transmission.w*brdf.x+brdf.y)*occlusion*(0.775f+0.225f*pore)*u.material.w;
    float3 sheen = u.sheen.rgb*sss.r*u.sheen.w*pow(1-NoV,3.0f)*(0.4f+0.6f*ao);
    return float4(neutralToneMap(diffuse+specular+sheen),1);
}
fragment float4 stylesFragmentShader(BerryVertexOut in [[stage_in]], constant BerryUniforms &u [[buffer(1)]]) {
    float3 N = normalize(rotation(u)*in.normal);
    float3 V = normalize(u.camera.xyz-in.worldPosition);
    float3 base = mix(float3(0.25f,0.11f,0.03f), float3(0.10f,0.025f,0.01f), in.mask.g);
    float3 color = base*u.ambient.rgb;
    for (int i=0;i<3;i++) {
        float3 L = u.lightDirections[i].xyz;
        float diffuse = max(dot(N,L)*0.6f+0.4f,0.0f);
        float highlight = pow(max(dot(N,normalize(L+V)),0.0f),30.0f)*0.03f*u.surface.y;
        color += u.lightColors[i].rgb*(base*diffuse/M_PI_F+highlight);
    }
    return float4(neutralToneMap(color*u.surface.x),1);
}

struct FuzzVertexOut {
    float4 position [[position]];
    float3 color;
    float alpha;
    float across;
};
vertex FuzzVertexOut fuzzVertexShader(uint vertexID [[vertex_id]], uint instance [[instance_id]],
                                     device const float *strands [[buffer(0)]], constant BerryUniforms &u [[buffer(1)]]) {
    // Three camera-facing ribbon segments per original four-point strand.
    uint corners[6] = {0,1,2,1,3,2};
    uint corner = corners[vertexID%6];
    uint point = vertexID/6 + corner/2;
    float side = corner%2 == 0 ? -1.0f : 1.0f;
    uint offset = instance*2*18;
    float3 p = float3(strands[offset+point*3],strands[offset+point*3+1],strands[offset+point*3+2]);
    uint neighbor = point == 3 ? 2 : point+1;
    float3 other = float3(strands[offset+neighbor*3],strands[offset+neighbor*3+1],strands[offset+neighbor*3+2]);
    float4 clip = u.mvp*float4(p,1);
    float4 next = u.mvp*float4(other,1);
    float2 screenTangent = (next.xy/next.w-clip.xy/clip.w)*u.viewport.xy;
    if (point==3) screenTangent = -screenTangent;
    screenTangent /= max(length(screenTangent),0.00001f);
    float2 perpendicular = float2(-screenTangent.y,screenTangent.x);
    float radius = strands[offset+17]*(1-0.8f*pow(float(point)/3,1.5f))*u.viewport.z;
    float pixels = max(radius*u.viewport.y*2.0f/clip.w,0.15f);
    float width = max(pixels,u.surface.z);
    clip.xy += perpendicular*side*width/u.viewport.xy*clip.w;
    float3 normal = normalize(float3(strands[offset+12],strands[offset+13],strands[offset+14]));
    float3 N = normalize(rotation(u)*normal);
    float3 outward = normalize(p-float3(0,1.12f,0));
    float3 light = u.ambient.rgb;
    float3 V = normalize(u.camera.xyz-(u.model*float4(p,1)).xyz);
    for (int i=0;i<3;i++) {
        float3 L = u.lightDirections[i].xyz;
        float reach = smoothstep(-0.2f,0.35f,dot(outward,transpose(rotation(u))*L));
        float diffuse = saturate(dot(N,L)*0.5f+0.5f);
        float back = pow(max(dot(-V,L),0.0f),6.0f)*u.viewport.w;
        light += u.lightColors[i].rgb*(diffuse*0.12f+back*0.25f)*reach;
    }
    FuzzVertexOut out;
    out.position = clip;
    out.color = neutralToneMap(u.fuzz.rgb*light);
    out.alpha = min(pixels/width,1.0f)*u.fuzz.a;
    out.across = side;
    return out;
}
fragment float4 fuzzFragmentShader(FuzzVertexOut in [[stage_in]]) {
    float alpha = (1-smoothstep(0.2f,1.0f,abs(in.across)))*in.alpha;
    return float4(in.color,alpha);
}
