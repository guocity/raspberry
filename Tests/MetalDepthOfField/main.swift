// Offscreen GPU regression: compile alongside Shared/Metal/MetalDepthOfField.swift.
// Pass the compiled DepthOfField.metallib as the first argument.
import Foundation
import Metal
import simd

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    fatalError("A Metal GPU is required")
}
let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
let post = try MetalDepthOfField(device: device, library: library, outputFormat: .bgra8Unorm_srgb)
let fixture = try device.makeLibrary(source: """
#include <metal_stdlib>
using namespace metal;
struct Vertex { float4 position [[position]]; float2 uv; };
struct Pixel { float4 color [[color(0)]]; float depth [[depth(any)]]; };
vertex Vertex testVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * 2 - 1, 0, 1), float2(p.x, 1 - p.y)};
}
fragment Pixel testFragment(Vertex in [[stage_in]]) {
    // Identical high-frequency details at two different depths, with a colored
    // orientation marker. The top half is in focus at 8; the bottom is at 10.
    float checker = fmod(floor(in.position.x / 2) + floor(in.position.y / 2), 2.0f);
    float3 tint = in.uv.y < 0.5f ? float3(1, 0.1f, 0.1f) : float3(0.1f, 0.1f, 1);
    float z = in.uv.y < 0.5f ? 8.0f : 10.0f;
    return {float4(tint * (0.15f + checker * 0.85f), 1), (80.0f - 0.1f * 80.0f / z) / (80.0f - 0.1f)};
}
""", options: nil)
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = fixture.makeFunction(name: "testVertex")
descriptor.fragmentFunction = fixture.makeFunction(name: "testFragment")
descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
descriptor.depthAttachmentPixelFormat = .depth32Float
descriptor.rasterSampleCount = MetalDepthOfField.sceneSampleCount
let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
let depthDescriptor = MTLDepthStencilDescriptor()
depthDescriptor.isDepthWriteEnabled = true
depthDescriptor.depthCompareFunction = .always
let depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!

func render(width: Int, height: Int, focus: Float = 8, enabled: Bool = true, amount: Float = 3, fast: Bool = false) throws -> [UInt8] {
    let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
    outputDescriptor.storageMode = .shared
    outputDescriptor.usage = .renderTarget
    let output = device.makeTexture(descriptor: outputDescriptor)!
    let command = queue.makeCommandBuffer()!
    let pass = try post.sceneRenderPass(size: BerryRenderQuality.sceneSize(drawable: CGSize(width: Double(width), height: Double(height)), fast: fast), clearColor: MTLClearColorMake(0, 0, 0, 1))
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(pipeline)
    encoder.setDepthStencilState(depthState)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    try post.encode(command: command, output: output, focusDistance: focus, focusRange: 1.6, blurAmount: amount, enabled: enabled)
    command.commit()
    command.waitUntilCompleted()
    if let error = command.error { throw error }
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    output.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    return pixels
}

func contrast(_ pixels: [UInt8], width: Int, height: Int, top: Bool) -> Double {
    let rows = top ? (height/8..<height*3/8) : (height*5/8..<height*7/8)
    let channel = top ? 2 : 0 // BGRA: red top, blue bottom
    var differences = 0.0, count = 0.0
    for y in rows {
        for x in width/8..<width*7/8-1 {
            let offset = (y * width + x) * 4 + channel
            differences += abs(Double(pixels[offset]) - Double(pixels[offset + 4]))
            count += 1
        }
    }
    return differences / count
}

for (width, height) in [(440, 956), (257, 511)] {
    let sharp = try render(width: width, height: height, enabled: false)
    let dof = try render(width: width, height: height)
    let pulled = try render(width: width, height: height, focus: 10)
    let zeroBlur = try render(width: width, height: height, amount: 0)
    precondition(sharp == zeroBlur, "Zero blur must preserve the unblurred image exactly")
    let topSharp = contrast(sharp, width: width, height: height, top: true)
    let bottomSharp = contrast(sharp, width: width, height: height, top: false)
    let topDOF = contrast(dof, width: width, height: height, top: true)
    let bottomDOF = contrast(dof, width: width, height: height, top: false)
    precondition(topDOF > topSharp * 0.98, "The focal plane must keep full-resolution detail")
    precondition(bottomDOF < bottomSharp * 0.5, "Out-of-focus detail must visibly blur")
    precondition(contrast(pulled, width: width, height: height, top: true) < topSharp * 0.5, "Focus pull must blur the previous focal plane")
    precondition(contrast(pulled, width: width, height: height, top: false) > bottomSharp * 0.98, "Focus pull must sharpen the new focal plane")
    let topPixel = (height/4 * width + width/4) * 4
    let bottomPixel = (height*3/4 * width + width/4) * 4
    precondition(dof[topPixel + 2] > dof[topPixel] && dof[bottomPixel] > dof[bottomPixel + 2], "Composite must preserve Metal's top-left orientation")
    let upscaled = try render(width: width, height: height, enabled: false, fast: true)
    precondition(upscaled[topPixel + 2] > upscaled[topPixel] && upscaled[bottomPixel] > upscaled[bottomPixel + 2], "Fast rendering must preserve orientation when upscaling")
    precondition(stride(from: 3, to: upscaled.count, by: 4).allSatisfy { upscaled[$0] == 255 }, "Upscaling must cover the entire drawable")
    let restored = try render(width: width, height: height, enabled: false)
    precondition(restored == sharp, "Turning off fast rendering must restore full detail")
    print("PASS \(width)×\(height): focal detail \(topDOF / topSharp), blurred detail \(bottomDOF / bottomSharp); focus pull, zero blur, and orientation")
}
print("Metal depth-of-field GPU checks passed")
