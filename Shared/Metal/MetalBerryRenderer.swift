import MetalKit
import simd

public class MetalBerryRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    
    // Meshes & Textures
    public var berryMesh: MTKMesh?
    public var ormTexture: MTLTexture?
    public var normalTexture: MTLTexture?
    public var shTextures: [MTLTexture] = []
    
    private var uniforms = BerryUniforms()
    public var settings: BerrySettings
    
    public init(device: MTLDevice, settings: BerrySettings) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.settings = settings
        super.init()
        buildPipeline()
    }
    
    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else { return }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "berryVertexShader")
        descriptor.fragmentFunction = library.makeFunction(name: "berryFragmentShader")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float
        
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle aspect ratio update
    }
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipeline = pipelineState else { return }
        
        // Update uniforms
        uniforms.sss = settings.sss
        uniforms.beadGlow = settings.beadGlow
        uniforms.innerWall = settings.innerWall
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BerryUniforms>.stride, index: 0)
        
        if let mesh = berryMesh {
            for (index, element) in mesh.vertexBuffers.enumerated() {
                encoder.setVertexBuffer(element.buffer, offset: element.offset, index: index)
            }
            for submesh in mesh.submeshes {
                encoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                             indexCount: submesh.indexCount,
                                             indexType: submesh.indexType,
                                             indexBuffer: submesh.indexBuffer.buffer,
                                             indexBufferOffset: submesh.indexBuffer.offset)
            }
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
