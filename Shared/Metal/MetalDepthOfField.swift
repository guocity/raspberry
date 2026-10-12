import Foundation
import CoreGraphics
import Metal
import simd

/// Native port of the viewer's half-resolution, depth-aware bokeh passes.
final class MetalDepthOfField {
    static let sceneSampleCount = 4
    private struct Uniforms {
        var focus: SIMD4<Float> // camera near/far, focus distance, focus range
        var blur: SIMD4<Float>  // full resolution, maximum full-res radius, enabled
        var exposure: SIMD4<Float>
    }
    private struct Targets {
        let scene, depth, multisampleColor, multisampleDepth: MTLTexture
        let half, bokeh, filled: MTLTexture
    }
    private let device: MTLDevice
    private let outputFormat: MTLPixelFormat
    private let prefilter, bokeh, fill, composite: MTLRenderPipelineState
    private var targets: Targets?

    init(device: MTLDevice, library: MTLLibrary, outputFormat: MTLPixelFormat) throws {
        self.device = device
        self.outputFormat = outputFormat
        func pipeline(_ fragment: String, format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = fragment
            descriptor.vertexFunction = library.makeFunction(name: "dofFullscreenVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        prefilter = try pipeline("dofPrefilterFragment", format: .rgba16Float)
        bokeh = try pipeline("dofBokehFragment", format: .rgba16Float)
        fill = try pipeline("dofFillFragment", format: .rgba16Float)
        composite = try pipeline("dofCompositeFragment", format: outputFormat)
    }

    func sceneRenderPass(size: CGSize, clearColor: MTLClearColor) throws -> MTLRenderPassDescriptor {
        let width = max(1, Int(size.width)), height = max(1, Int(size.height))
        if targets?.scene.width != width || targets?.scene.height != height {
            // Allocate only when the drawable dimensions change, not every frame.
            func texture(_ format: MTLPixelFormat, _ label: String, half: Bool = false, multisample: Bool = false) throws -> MTLTexture {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                    width: half ? (width + 1) / 2 : width, height: half ? (height + 1) / 2 : height, mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = [.renderTarget, .shaderRead]
                if multisample {
                    descriptor.textureType = .type2DMultisample
                    descriptor.sampleCount = Self.sceneSampleCount
                    descriptor.usage = .renderTarget
                    #if os(iOS)
                    // Keep MSAA attachments in tile memory; only the resolves survive.
                    descriptor.storageMode = .memoryless
                    #endif
                }
                guard let texture = device.makeTexture(descriptor: descriptor) else { throw PostError.unavailable }
                texture.label = label
                return texture
            }
            targets = try Targets(
                scene: texture(outputFormat, "DOF scene color"),
                depth: texture(.depth32Float, "DOF scene depth"),
                multisampleColor: texture(outputFormat, "Scene MSAA color", multisample: true),
                multisampleDepth: texture(.depth32Float, "Scene MSAA depth", multisample: true),
                half: texture(.rgba16Float, "DOF prefilter and circle of confusion", half: true),
                bokeh: texture(.rgba16Float, "DOF golden-angle bokeh", half: true),
                filled: texture(.rgba16Float, "DOF bokeh fill", half: true))
        }
        guard let targets else { throw PostError.unavailable }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.multisampleColor
        pass.colorAttachments[0].resolveTexture = targets.scene
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = clearColor
        pass.depthAttachment.texture = targets.multisampleDepth
        pass.depthAttachment.resolveTexture = targets.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .multisampleResolve
        pass.depthAttachment.depthResolveFilter = .min
        pass.depthAttachment.clearDepth = 1
        return pass
    }

    func encode(command: MTLCommandBuffer, output: MTLTexture, focusDistance: Float,
                focusRange: Float, blurAmount: Float, enabled: Bool, gain: Float = 1) throws {
        guard let targets else {
            throw PostError.unavailable
        }
        let useDOF = enabled && blurAmount > 0
        var uniforms = Uniforms(focus: SIMD4(0.1, 80, max(0.1, focusDistance), max(0.01, focusRange)),
            blur: SIMD4(Float(targets.scene.width), Float(targets.scene.height), max(0, blurAmount) * 0.0017 * Float(targets.scene.height), useDOF ? 1 : 0),
            exposure: SIMD4(gain, 0, 0, 0))
        func draw(_ pipeline: MTLRenderPipelineState, to target: MTLTexture, textures: [MTLTexture]) throws {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw PostError.unavailable }
            encoder.label = pipeline.label
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            for (index, texture) in textures.enumerated() { encoder.setFragmentTexture(texture, index: index) }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        if useDOF {
            try draw(prefilter, to: targets.half, textures: [targets.scene, targets.depth])
            try draw(bokeh, to: targets.bokeh, textures: [targets.half])
            try draw(fill, to: targets.filled, textures: [targets.bokeh])
        }
        // With DOF disabled, composite reads only the scene and scales it to the drawable.
        try draw(composite, to: output, textures: [targets.scene, targets.depth, targets.filled])
    }

    private enum PostError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Unable to create the Metal depth-of-field render targets." }
    }
}

/// Bound pixel work while retaining the drawable's aspect ratio.
enum BerryRenderQuality {
    static func sceneSize(drawable: CGSize, fast: Bool) -> CGSize {
        guard fast else { return drawable }
        let longest = max(drawable.width, drawable.height, 1)
        let scale = min(0.7, 1600 / longest)
        return CGSize(width: max(1, (drawable.width * scale).rounded()),
                      height: max(1, (drawable.height * scale).rounded()))
    }
}
