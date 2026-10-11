import MetalKit
import SwiftUI
import simd
import UIKit

struct BerryMetalView: UIViewRepresentable {
    @ObservedObject var settings: BerrySettings
    var paused: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb
        // The scene is antialiased offscreen; the final DOF composite needs one sample.
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.preferredFramesPerSecond = 60
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "berry-canvas"
        view.isOpaque = false
        view.backgroundColor = .clear
        do {
            let renderer = try MetalBerryRenderer(view: view, settings: settings)
            context.coordinator.renderer = renderer
            view.delegate = renderer
            let rotate = UIPanGestureRecognizer(target: renderer, action: #selector(renderer.rotate(_:)))
            rotate.maximumNumberOfTouches = 1
            view.addGestureRecognizer(rotate)
            let pan = UIPanGestureRecognizer(target: renderer, action: #selector(renderer.pan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = renderer
            view.addGestureRecognizer(pan)
            let pinch = UIPinchGestureRecognizer(target: renderer, action: #selector(renderer.zoom(_:)))
            pinch.delegate = renderer
            view.addGestureRecognizer(pinch)
            let reset = UITapGestureRecognizer(target: renderer, action: #selector(renderer.reset))
            reset.numberOfTapsRequired = 2
            view.addGestureRecognizer(reset)
        } catch {
            DispatchQueue.main.async { settings.renderError = error.localizedDescription }
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) { view.isPaused = paused }
    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.renderer = nil
    }
    final class Coordinator { var renderer: MetalBerryRenderer? }
}

final class MetalBerryRenderer: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
    private struct Mesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let count: Int
    }
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let skinPipeline: MTLRenderPipelineState
    private let stylesPipeline: MTLRenderPipelineState
    private let fuzzPipeline: MTLRenderPipelineState
    private let postProcessing: MetalDepthOfField
    private let depth: MTLDepthStencilState
    private let fuzzDepth: MTLDepthStencilState
    private let berry: Mesh
    private let styles: Mesh
    private let strands: MTLBuffer
    private let strandCount: Int
    private let textures: [MTLTexture]
    private let settings: BerrySettings
    private let camera: BerryOrbitCamera
    private var lastTime = CACurrentMediaTime()
    private var resetID: UUID
    private let reel: BerryReel
    private var reelFrame: BerryReel.Frame?

    init(view: MTKView, settings: BerrySettings) throws {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { throw RendererError.unavailable }
        self.device = device
        self.queue = queue
        self.settings = settings
        self.resetID = settings.resetCamera
        let size = view.drawableSize.width > 0 ? view.drawableSize : UIScreen.main.bounds.size
        camera = BerryOrbitCamera(aspect: Double(size.width / max(1, size.height)), reducedMotion: UIAccessibility.isReduceMotionEnabled)
        reel = BerryReel(data: try BerryReelData.load())
        postProcessing = try MetalDepthOfField(device: device, library: library, outputFormat: view.colorPixelFormat)
        let descriptor = MTLVertexDescriptor()
        let formats: [MTLVertexFormat] = [.float3, .float3, .float2, .float4, .float3]
        for (index, offset) in [0, 12, 24, 32, 48].enumerated() {
            descriptor.attributes[index].format = formats[index]
            descriptor.attributes[index].offset = offset
            descriptor.attributes[index].bufferIndex = 0
        }
        descriptor.layouts[0].stride = 60
        func pipeline(_ vertex: String, _ fragment: String, fuzz: Bool = false) throws -> MTLRenderPipelineState {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = library.makeFunction(name: vertex)
            p.fragmentFunction = library.makeFunction(name: fragment)
            p.vertexDescriptor = fuzz ? nil : descriptor
            p.colorAttachments[0].pixelFormat = view.colorPixelFormat
            p.depthAttachmentPixelFormat = .depth32Float
            p.rasterSampleCount = MetalDepthOfField.sceneSampleCount
            if fuzz {
                let color = p.colorAttachments[0]!
                color.isBlendingEnabled = true
                color.sourceRGBBlendFactor = .sourceAlpha
                color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.sourceAlphaBlendFactor = .one
                color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: p)
        }
        skinPipeline = try pipeline("berryVertexShader", "berryFragmentShader")
        stylesPipeline = try pipeline("berryVertexShader", "stylesFragmentShader")
        fuzzPipeline = try pipeline("fuzzVertexShader", "fuzzFragmentShader", fuzz: true)
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .less
        d.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: d) else { throw RendererError.unavailable }
        self.depth = depth
        d.isDepthWriteEnabled = false
        guard let fuzzDepth = device.makeDepthStencilState(descriptor: d) else { throw RendererError.unavailable }
        self.fuzzDepth = fuzzDepth
        berry = try Self.loadMesh("berry", device: device)
        styles = try Self.loadMesh("styles", device: device)
        let fuzz = try Self.asset("fuzz", extension: "strands")
        guard fuzz.count >= 8, String(data: fuzz.prefix(4), encoding: .utf8) == "RBFZ" else { throw RendererError.invalidAsset("fuzz") }
        strandCount = Int(Self.word(fuzz, 4))
        guard strandCount > 0, fuzz.count == 8 + strandCount * 72,
              let buffer = fuzz.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!.advanced(by: 8), length: fuzz.count - 8, options: .storageModeShared) }) else {
            throw RendererError.invalidAsset("fuzz")
        }
        strands = buffer
        textures = try ["albedo", "normal_os", "ao_rough_thick", "detail_normal"]
            .appending(contentsOf: (0..<9).map { "transfer_sh\($0)" })
            .map { try Self.loadTexture($0, device: device) }
        super.init()
    }

    @objc func rotate(_ gesture: UIPanGestureRecognizer) {
        settings.reelPlaying = false
        if gesture.state == .began { camera.beginPan() }
        if gesture.state == .changed {
            let delta = gesture.translation(in: gesture.view), speed = gesture.velocity(in: gesture.view)
            camera.drag(delta: SIMD2(Double(delta.x), Double(delta.y)), speed: SIMD2(Double(speed.x), Double(speed.y)), height: Double(gesture.view?.bounds.height ?? 1))
        }
        if gesture.state == .ended || gesture.state == .cancelled { camera.endPan(cancelled: gesture.state == .cancelled) }
        gesture.setTranslation(.zero, in: gesture.view)
    }
    @objc func pan(_ gesture: UIPanGestureRecognizer) {
        settings.reelPlaying = false
        if gesture.state == .began { camera.beginTranslation() }
        if gesture.state == .changed {
            let delta = gesture.translation(in: gesture.view)
            camera.translate(delta: SIMD2(Double(delta.x), Double(delta.y)), height: Double(gesture.view?.bounds.height ?? 1))
        }
        if gesture.state == .ended || gesture.state == .cancelled { camera.endTranslation() }
        gesture.setTranslation(.zero, in: gesture.view)
    }
    @objc func zoom(_ gesture: UIPinchGestureRecognizer) {
        settings.reelPlaying = false
        if gesture.state == .began { camera.beginPinch() }
        if gesture.state == .changed { camera.zoom(scale: Double(gesture.scale)) }
        if gesture.state == .ended || gesture.state == .cancelled { camera.endPinch() }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // A two-finger translation and a pinch must work together rather than
        // having the pan recognizer consume all two-finger touches.
        (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
            || (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
    }
    @objc func reset() { settings.reelPlaying = false; camera.goHome() }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        let dt = min(now - lastTime, 0.1)
        lastTime = now
        camera.setAspect(Double(view.drawableSize.width / view.drawableSize.height))
        if resetID != settings.resetCamera {
            resetID = settings.resetCamera
            settings.reelPlaying = false
            reset()
        }
        if settings.reelPlaying {
            if !reel.active { camera.cancelIntro(); reel.start(angle: camera.angleDegrees) }
            reelFrame = reel.update(dt: dt, aspect: Double(view.drawableSize.width / view.drawableSize.height))
            if settings.reelShotName != reelFrame?.preset { settings.reelShotName = reelFrame?.preset }
            if !reel.active { settings.reelPlaying = false }
        } else {
            reel.stop()
            reelFrame = nil
            if settings.reelShotName != nil { settings.reelShotName = nil }
            camera.autoRotate = settings.spinning
            camera.update(dt: dt)
        }
        var uniforms = makeUniforms(size: view.drawableSize)
        let background = reelFrame.map { Self.rgb($0.look.environment.background) * $0.look.environment.backgroundIntensity }
            ?? Self.rgb(settings.backgroundColor)
        let pass: MTLRenderPassDescriptor
        do {
            pass = try postProcessing.sceneRenderPass(size: view.drawableSize,
                clearColor: MTLClearColor(red: Double(background.x), green: Double(background.y), blue: Double(background.z), alpha: 1))
        } catch {
            settings.renderError = error.localizedDescription
            return
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setDepthStencilState(depth)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<BerryUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BerryUniforms>.stride, index: 1)
        for (index, texture) in textures.enumerated() { encoder.setFragmentTexture(texture, index: index) }
        func drawMesh(_ mesh: Mesh, pipeline: MTLRenderPipelineState) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.count, indexType: .uint32,
                                          indexBuffer: mesh.indices, indexBufferOffset: 0)
        }
        drawMesh(berry, pipeline: skinPipeline)
        drawMesh(styles, pipeline: stylesPipeline)
        if settings.fuzzVisible {
            encoder.setRenderPipelineState(fuzzPipeline)
            encoder.setDepthStencilState(fuzzDepth)
            encoder.setVertexBuffer(strands, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 18, instanceCount: strandCount / 2)
        }
        encoder.endEncoding()
        do {
            try postProcessing.encode(command: command, output: drawable.texture,
                focusDistance: reelFrame.map { $0.focus + $0.look.post.focusOffset } ?? (camera.distance + settings.focusOffset),
                focusRange: reelFrame?.look.post.focusRange ?? settings.focusRange,
                blurAmount: reelFrame?.blur ?? settings.blurAmount,
                enabled: reelFrame?.look.post.dof ?? settings.depthOfField,
                gain: reelFrame.map { $0.gain * $0.look.post.exposure } ?? 1)
        } catch {
            settings.renderError = error.localizedDescription
            return
        }
        command.present(drawable)
        command.commit()
    }

    private func makeUniforms(size: CGSize) -> BerryUniforms {
        if let frame = reelFrame { return makeReelUniforms(frame, size: size) }
        if let look = settings.referenceLook {
            let frame = BerryReel.Frame(index: 0, preset: settings.preset.rawValue, position: camera.position, target: camera.target,
                roll: 0, fov: 20, lightTurn: camera.lightTurn, gain: 1, focus: camera.distance, blur: settings.blurAmount, look: look)
            return makeReelUniforms(frame, size: size, adjustments: settings)
        }
        var u = BerryUniforms()
        let aspect = Float(size.width / size.height)
        let fov: Float = 20 * .pi / 180
        let rotation = matrix_identity_float4x4
        u.model = Self.translation(SIMD3(0, -1.12, 0))
        u.camera = SIMD4(camera.position, 1)
        u.mvp = Self.perspective(fov, aspect: aspect) * Self.lookAt(eye: camera.position, target: camera.target, roll: 0) * u.model
        let angle = settings.keyAzimuth * .pi / 180
        let baseDirections = [simd_normalize(SIMD3(sin(angle), 0.55, cos(angle))),
                          simd_normalize(SIMD3<Float>(-0.8, 0.2, 0.6)),
                          simd_normalize(SIMD3<Float>(0.2, 0.65, -1))]
        let lightRotation = Self.rotation(camera.lightTurn, axis: SIMD3(0, 1, 0))
        let directions = baseDirections.map { direction -> SIMD3<Float> in
            let result = lightRotation * SIMD4(direction, 0)
            return SIMD3(result.x, result.y, result.z)
        }
        let colors = [Self.rgb(settings.keyColor) * settings.keyIntensity,
                      SIMD3<Float>(0.65, 0.75, 1) * (settings.ambientIntensity * 2),
                      (settings.preset == .neon ? SIMD3<Float>(1, 0.1, 0.5) : SIMD3<Float>(1, 0.9, 0.85)) * (settings.preset == .backlit ? 4 : 1.4)]
        u.lightDirections = (SIMD4(directions[0], 0), SIMD4(directions[1], 0), SIMD4(directions[2], 0))
        u.lightColors = (SIMD4(colors[0], 0), SIMD4(colors[1], 0), SIMD4(colors[2], 0))
        // Project broad studio lights into SH9, in the berry's model space.
        var sh = [SIMD4<Float>](repeating: .zero, count: 9)
        sh[0] = SIMD4<Float>(repeating: settings.ambientIntensity * 3.544908)
        let inverse = simd_float3x3(
            SIMD3(rotation.columns.0.x, rotation.columns.0.y, rotation.columns.0.z),
            SIMD3(rotation.columns.1.x, rotation.columns.1.y, rotation.columns.1.z),
            SIMD3(rotation.columns.2.x, rotation.columns.2.y, rotation.columns.2.z)).transpose
        for i in 0..<3 {
            let l = inverse * directions[i]
            let basis: [Float] = [0.282095, 0.488603*l.y, 0.488603*l.z, 0.488603*l.x,
                                 1.092548*l.x*l.y, 1.092548*l.y*l.z, 0.315392*(3*l.z*l.z-1),
                                 1.092548*l.x*l.z, 0.546274*(l.x*l.x-l.y*l.y)]
            let a: Float = 0.32
            let c = cos(a)
            let irradiance = 2 / (sin(a)*sin(a))
            let bands = [irradiance*(1-c), irradiance*0.5*(1-c*c), irradiance*0.5*(c-c*c*c)]
            for j in 0..<9 { sh[j] += SIMD4(colors[i], 0) * basis[j] * bands[j == 0 ? 0 : j < 4 ? 1 : 2] }
        }
        u.sh = (sh[0], sh[1], sh[2], sh[3], sh[4], sh[5], sh[6], sh[7], sh[8])
        u.skin = SIMD4(settings.sss, settings.beadGlow, settings.transDepth, settings.roughness)
        u.innerPosition = SIMD4(0, 1.15, 0, settings.innerWall)
        u.innerColor = SIMD4(Self.rgb(settings.innerColor) * settings.innerIntensity * 1.5, 0)
        u.transmission = SIMD4(Self.rgb(settings.transColor), 0.0255)
        u.viewport = SIMD4(Float(size.width), Float(size.height), 1.4, settings.backlightHalo)
        u.ambient = SIMD4<Float>(repeating: settings.ambientIntensity)
        return u
    }

    private func makeReelUniforms(_ frame: BerryReel.Frame, size: CGSize, adjustments: BerrySettings? = nil) -> BerryUniforms {
        var u = BerryUniforms()
        u.model = Self.translation(SIMD3(0, -1.12, 0))
        u.camera = SIMD4(frame.position, 1)
        u.mvp = Self.perspective(frame.fov * .pi / 180, aspect: Float(size.width / size.height))
            * Self.lookAt(eye: frame.position, target: frame.target, roll: frame.roll) * u.model
        let look = frame.look
        let lights = [look.lights.key, look.lights.fill, look.lights.rim]
        let turn = Self.rotation(frame.lightTurn, axis: SIMD3(0, 1, 0))
        var directions = [SIMD4<Float>](), colors = [SIMD4<Float>]()
        let ambient = Self.rgb(look.environment.ambientColor) * (adjustments?.ambientIntensity ?? look.environment.ambientIntensity)
        var sh = [SIMD4<Float>](repeating: .zero, count: 9)
        sh[0] = SIMD4(ambient * 3.544908, 0)
        sh[1] = SIMD4(ambient * (4 * .pi / 3 * look.environment.ambientGradient * 0.488603), 0)
        for (index, light) in lights.enumerated() {
            let azimuth = (index == 0 ? (adjustments?.keyAzimuth ?? light.azimuth) : light.azimuth) * .pi / 180
            let elevation = light.elevation * .pi / 180
            let rotated = turn * SIMD4(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation), 0)
            let direction = SIMD3(rotated.x, rotated.y, rotated.z)
            let color = index == 0 && adjustments != nil
                ? Self.rgb(adjustments!.keyColor) * adjustments!.keyIntensity : Self.rgb(light.color) * light.intensity
            let angle = max(2, light.size) * .pi / 180
            directions.append(SIMD4(direction, angle))
            colors.append(SIMD4(color, light.stretch))
            let x = direction.x, y = direction.y, z = direction.z
            let basis: [Float] = [0.282095, 0.488603*y, 0.488603*z, 0.488603*x,
                1.092548*x*y, 1.092548*y*z, 0.315392*(3*z*z-1), 1.092548*x*z, 0.546274*(x*x-y*y)]
            let c = cos(angle), irradiance = 2 / (sin(angle) * sin(angle))
            let bands = [irradiance*(1-c), irradiance*0.5*(1-c*c), irradiance*0.5*(c-c*c*c)]
            for j in 0..<9 { sh[j] += SIMD4(color, 0) * basis[j] * bands[j == 0 ? 0 : j < 4 ? 1 : 2] }
        }
        u.lightDirections = (directions[0], directions[1], directions[2])
        u.lightColors = (colors[0], colors[1], colors[2])
        u.sh = (sh[0], sh[1], sh[2], sh[3], sh[4], sh[5], sh[6], sh[7], sh[8])
        u.skin = SIMD4(look.skin.sss, look.skin.beadGlow, look.skin.transDepth, look.skin.roughnessScale)
        u.innerPosition = SIMD4(0, look.lights.inner.height, 0, look.lights.inner.wall)
        u.innerColor = SIMD4(Self.rgb(look.lights.inner.color) * look.lights.inner.intensity * 1.5, 0)
        u.transmission = SIMD4(Self.rgb(look.skin.transColor), pow((look.skin.ior - 1) / (look.skin.ior + 1), 2))
        u.viewport = SIMD4(Float(size.width), Float(size.height), look.fuzz.width, look.fuzz.backlight)
        u.ambient = SIMD4(ambient, 1)
        u.material = SIMD4(look.skin.roughnessBias, look.skin.detailStrength, look.skin.detailScale, look.skin.specular)
        u.sheen = SIMD4(Self.rgb(look.skin.sheenColor), look.skin.sheen)
        u.effects = SIMD4(look.skin.seeThrough, look.skin.seed, look.skin.aoPower, look.environment.reflectionIntensity)
        u.fuzz = SIMD4(Self.rgb(look.fuzz.color), look.fuzz.opacity)
        u.surface = SIMD4(look.styles.brightness, look.styles.specular / 0.5, look.fuzz.minPixels, look.environment.ambientGradient)
        if let adjustments {
            u.skin = SIMD4(adjustments.sss, adjustments.beadGlow, adjustments.transDepth, adjustments.roughness)
            u.innerPosition.w = adjustments.innerWall
            u.innerColor = SIMD4(Self.rgb(adjustments.innerColor) * adjustments.innerIntensity * 1.5, 0)
            u.transmission = SIMD4(Self.rgb(adjustments.transColor), u.transmission.w)
            u.viewport.w = adjustments.backlightHalo
        }
        return u
    }

    private static func asset(_ name: String, extension ext: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "NativeAssets") else {
            throw RendererError.invalidAsset(name)
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    private static func word(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }
    private static func loadMesh(_ name: String, device: MTLDevice) throws -> Mesh {
        let data = try asset(name, extension: "mesh")
        guard data.count >= 16, String(data: data.prefix(4), encoding: .utf8) == "RBRY", word(data, 4) == 1 else { throw RendererError.invalidAsset(name) }
        let vertexBytes = Int(word(data, 8)) * 60
        let count = Int(word(data, 12))
        guard vertexBytes > 0, count > 0, data.count == 16 + vertexBytes + count * 4 else { throw RendererError.invalidAsset(name) }
        return try data.withUnsafeBytes { bytes in
            guard let vertices = device.makeBuffer(bytes: bytes.baseAddress!.advanced(by: 16), length: vertexBytes, options: .storageModeShared),
                  let indices = device.makeBuffer(bytes: bytes.baseAddress!.advanced(by: 16 + vertexBytes), length: count * 4, options: .storageModeShared) else { throw RendererError.unavailable }
            return Mesh(vertices: vertices, indices: indices, count: count)
        }
    }
    private static func loadTexture(_ name: String, device: MTLDevice) throws -> MTLTexture {
        let data = try asset(name, extension: "texture")
        guard data.count >= 16, String(data: data.prefix(4), encoding: .utf8) == "RBAT" else { throw RendererError.invalidAsset(name) }
        let width = Int(word(data, 4)), height = Int(word(data, 8)), levels = Int(word(data, 12))
        guard width > 0, height > 0, levels > 0 else { throw RendererError.invalidAsset(name) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: name == "albedo" ? .astc_4x4_srgb : .astc_4x4_ldr,
                                                                  width: width, height: height, mipmapped: true)
        descriptor.mipmapLevelCount = levels
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RendererError.unavailable }
        var offset = 16
        for level in 0..<levels {
            guard offset + 4 <= data.count else { throw RendererError.invalidAsset(name) }
            let count = Int(word(data, offset)); offset += 4
            let w = max(1, width >> level), h = max(1, height >> level)
            let row = ((w + 3) / 4) * 16
            guard count == row * ((h + 3) / 4), offset + count <= data.count else { throw RendererError.invalidAsset(name) }
            data.withUnsafeBytes { bytes in
                texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: level,
                                withBytes: bytes.baseAddress!.advanced(by: offset), bytesPerRow: row)
            }
            offset += count
        }
        guard offset == data.count else { throw RendererError.invalidAsset(name) }
        return texture
    }
    private static func rgb(_ color: Color) -> SIMD3<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ value: CGFloat) -> Float { Float(value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)) }
        return SIMD3(linear(r), linear(g), linear(b))
    }
    private static func rgb(_ hex: String) -> SIMD3<Float> {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        let channels = [Float((value >> 16) & 255), Float((value >> 8) & 255), Float(value & 255)]
        func linear(_ byte: Float) -> Float {
            let value = byte / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return SIMD3(linear(channels[0]), linear(channels[1]), linear(channels[2]))
    }
    private static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, roll: Float) -> simd_float4x4 {
        let z = simd_normalize(eye - target)
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), z))
        let up = simd_cross(z, right)
        let x = right * cos(roll) + up * sin(roll)
        let y = up * cos(roll) - right * sin(roll)
        return simd_float4x4(SIMD4(x.x, y.x, z.x, 0), SIMD4(x.y, y.y, z.y, 0), SIMD4(x.z, y.z, z.z, 0),
            SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1))
    }
    private static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4; m.columns.3 = SIMD4(t, 1); return m
    }
    private static func rotation(_ angle: Float, axis: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(simd_quatf(angle: angle, axis: axis)) }
    private static func perspective(_ fov: Float, aspect: Float) -> simd_float4x4 {
        let y = 1 / tan(fov / 2), near: Float = 0.1, far: Float = 80
        return simd_float4x4(SIMD4(y / aspect, 0, 0, 0), SIMD4(0, y, 0, 0),
                             SIMD4(0, 0, far / (near - far), -1), SIMD4(0, 0, near * far / (near - far), 0))
    }
    private enum RendererError: LocalizedError {
        case unavailable, invalidAsset(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Metal is unavailable on this device."
            case .invalidAsset(let name): return "Unable to load the bundled \(name) asset."
            }
        }
    }
}

private extension Array {
    func appending(contentsOf elements: [Element]) -> [Element] { self + elements }
}
