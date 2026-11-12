import AppKit
import MetalKit

enum AtlasError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        if case .unavailable(let message) = self { return message }
        return nil
    }
}

/// Independent of the ornament speed and shape duration. Time only advances
/// while frames are displayed, so the next appearance cannot expire in sleep.
struct AtlasClock {
    private(set) var elapsed = 0.0
    private struct Appearance {
        let start: Double
        let duration: Double
        let date: Bool
        var end: Double { start+duration }
    }
    private var active: Appearance?
    private var exit: (start: Double, blend: Float)?
    private static let exitDuration = 1.6
    private var cycle = 0
    private var waitingSince = 0.0
    private var plannedSettings: AtlasClockSettings?
    private var deadline = 0.0
    private var minute: Int64?
    private var digits = SIMD2<UInt32>.zero
    private var previous = SIMD2<UInt32>.zero
    private var changedAt = 0.0

    func presentation() -> (blend: Float, date: Bool) {
        guard let active else { return (0,false) }
        if let exit {
            let progress = min(1,(elapsed-exit.start)/Self.exitDuration)
            return (exit.blend*Float(1-AtlasField.smooth(progress)),active.date)
        }
        let age = elapsed-active.start, remaining = active.end-elapsed
        let ramp = min(3.4,active.duration*0.25)
        return (Float(AtlasField.smooth(max(0,min(1,age/ramp,remaining/ramp)))),active.date)
    }

    private mutating func endAppearanceIfNeeded() {
        guard let active else { return }
        let end = exit.map { $0.start+Self.exitDuration } ?? active.end
        guard elapsed >= end else { return }
        self.active = nil
        exit = nil
        waitingSince = end
        plannedSettings = nil
        cycle += 1
    }

    mutating func advance(_ delta: Double,seed: UInt64,settings: AtlasClockSettings) {
        if !settings.enabled, exit == nil, let active, elapsed < active.end {
            let blend = presentation().blend
            if blend > 0 { exit = (elapsed,blend) }
            else { self.active = nil; plannedSettings = nil }
        }
        elapsed += delta
        endAppearanceIfNeeded()
        if !settings.enabled {
            if active == nil { waitingSince = elapsed; plannedSettings = nil }
            return
        }
        guard active == nil else { return }
        let field = AtlasField(seed: seed)
        if plannedSettings != settings {
            deadline = waitingSince+settings.earliest+(settings.latest-settings.earliest)*field.unit(cycle,0x13a1)
            plannedSettings = settings
        }
        if elapsed >= deadline {
            active = Appearance(start: elapsed,duration: settings.duration,date: field.unit(cycle,0x13a2)<0.44)
        }
    }

    mutating func showNow(settings: AtlasClockSettings) {
        guard settings.enabled, active == nil else { return }
        active = Appearance(start: elapsed,duration: settings.duration,date: true)
    }

    static func encode(_ date: Date, timeZone: TimeZone = .current) -> SIMD2<UInt32> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour,.minute,.day,.month,.year],from: date)
        func pack(_ value: Int,count: Int) -> UInt32 {
            var n = max(0,value), result: UInt32 = 0
            for i in 0..<count {
                result |= UInt32(n%10) << (4*i)
                n /= 10
            }
            return result
        }
        return SIMD2(pack((c.hour ?? 0)*100+(c.minute ?? 0),count: 4),
                     pack((c.day ?? 1)*1_000_000+(c.month ?? 1)*10_000+(c.year ?? 2000)%10_000,count: 8))
    }

    mutating func apply(to u: inout AtlasUniforms,
                        preview: (instant: Date, showsDate: Bool, blend: Float)?) {
        let moment = presentation()
        let blend = preview?.blend ?? moment.blend
        guard blend > 0 else { minute = nil; return }
        let now = preview?.instant ?? Date()
        let currentMinute = Int64(floor(now.timeIntervalSince1970/60))
        if minute != currentMinute {
            let next = Self.encode(now)
            previous = minute == nil ? next : digits
            digits = next; minute = currentMinute; changedAt = elapsed
        }
        let phase = (elapsed*0.39).truncatingRemainder(dividingBy: 2 * .pi)
        let glyphBlend = AtlasField.smooth(min(1,(elapsed-changedAt)/0.55))
        u.clock = SIMD4(blend,(preview?.showsDate ?? moment.date) ? 1 : 0,Float(glyphBlend),Float(phase))
        u.clockDigits = SIMD4(previous.x,previous.y,digits.x,digits.y)
    }
}

/// Both the preview and the actual screen saver use this renderer. The shared
/// parametric geometry, crisp strokes and fading history stay on the GPU.
final class AtlasRenderer {
    let device: MTLDevice
    var settings: AtlasSettings
    private(set) var seed: UInt64
    private(set) var elapsed: Double
    private(set) var shapeElapsed: Double
    private(set) var frameCount = 0
    private let queue: MTLCommandQueue
    private let advance: MTLComputePipelineState
    private let fade: MTLRenderPipelineState
    private let lines: MTLRenderPipelineState
    private let display: MTLRenderPipelineState
    private let bloomExtract: MTLRenderPipelineState
    private let bloomBlur: MTLRenderPipelineState
    private let black: MTLTexture
    private let segments: MTLBuffer
    private var textures: [MTLTexture] = []
    private var bloomTextures: [MTLTexture] = []
    private var textureIndex = 0
    private var needsClear = true
    private var clock = AtlasClock()
    private let available = DispatchSemaphore(value: 2)

    init(settings: AtlasSettings = .load(), seed: UInt64 = .random(in: 1...UInt64.max), elapsed: Double = 0, shapeElapsed: Double? = nil) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw AtlasError.unavailable("Metal není na tomto počítači dostupný.")
        }
        self.device = device; self.queue = queue; self.settings = settings.validated
        self.seed = seed; self.elapsed = elapsed
        self.shapeElapsed = shapeElapsed ?? elapsed
        let library = try device.makeLibrary(source: AtlasShaders.source, options: nil)
        guard let kernel = library.makeFunction(name: "advance") else {
            throw AtlasError.unavailable("Výpočet kresby se nepodařilo připravit.")
        }
        advance = try device.makeComputePipelineState(function: kernel)
        func pipeline(vertex: String, fragment: String, format: MTLPixelFormat, additive: Bool = false) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            if additive {
                d.colorAttachments[0].isBlendingEnabled = true
                d.colorAttachments[0].sourceRGBBlendFactor = .one
                d.colorAttachments[0].destinationRGBBlendFactor = .one
                d.colorAttachments[0].sourceAlphaBlendFactor = .zero
                d.colorAttachments[0].destinationAlphaBlendFactor = .one
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        fade = try pipeline(vertex: "fullVertex", fragment: "fadeFragment", format: .rgba16Float)
        lines = try pipeline(vertex: "lineVertex", fragment: "lineFragment", format: .rgba16Float, additive: true)
        display = try pipeline(vertex: "fullVertex", fragment: "displayFragment", format: .bgra8Unorm)
        bloomExtract = try pipeline(vertex: "fullVertex", fragment: "bloomExtract", format: .rgba16Float)
        bloomBlur = try pipeline(vertex: "fullVertex", fragment: "bloomBlur", format: .rgba16Float)
        guard let segments = device.makeBuffer(length: 288 * 8 * AtlasField.strandCount * 32, options: .storageModePrivate) else {
            throw AtlasError.unavailable("Paměť pro kresbu se nepodařilo vytvořit.")
        }
        self.segments = segments
        let empty = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,width: 1,height: 1,mipmapped: false)
        empty.usage = .shaderRead; empty.storageMode = .shared
        guard let black = device.makeTexture(descriptor: empty) else {
            throw AtlasError.unavailable("Texturu pro světelné efekty se nepodařilo vytvořit.")
        }
        let zeros = [UInt16](repeating: 0,count: 4)
        zeros.withUnsafeBytes { black.replace(region: MTLRegionMake2D(0,0,1,1),mipmapLevel: 0,withBytes: $0.baseAddress!,bytesPerRow: 8) }
        self.black = black
    }

    private func prepareBloom(width: Int,height: Int) throws {
        let w = max(1,(width+3)/4), h = max(1,(height+3)/4)
        guard bloomTextures.first?.width != w || bloomTextures.first?.height != h else { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,width: w,height: h,mipmapped: false)
        d.usage = [.shaderRead,.renderTarget]; d.storageMode = .private
        let allocated = (0..<4).compactMap { _ in device.makeTexture(descriptor: d) }
        guard allocated.count == 4 else { throw AtlasError.unavailable("Paměť pro světelnou záři se nepodařilo vytvořit.") }
        bloomTextures = allocated
    }

    private func bloomPass(command: MTLCommandBuffer,source: MTLTexture,target: MTLTexture,
                           pipeline: MTLRenderPipelineState,step: SIMD2<Float>? = nil) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source,index: 0)
        if var step { encoder.setFragmentBytes(&step,length: MemoryLayout<SIMD2<Float>>.stride,index: 0) }
        encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func prepare(width: Int, height: Int) throws {
        guard textures.first?.width != width || textures.first?.height != height else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]; descriptor.storageMode = .private
        guard let a = device.makeTexture(descriptor: descriptor), let b = device.makeTexture(descriptor: descriptor) else {
            throw AtlasError.unavailable("Obrazovou paměť se nepodařilo vytvořit.")
        }
        textures = [a,b]; textureIndex = 0; needsClear = true
    }

    func showClockNow() { clock.showNow(settings: settings.clock.validated) }

    func restart() {
        seed = .random(in: 1...UInt64.max); elapsed = 0; shapeElapsed = 0; clock = AtlasClock(); needsClear = true
    }

    @discardableResult
    func render(target: MTLTexture, delta: Double, backing: Double = 1,
                drawable: CAMetalDrawable? = nil, wait: Bool = false, referenceCircle: Bool = false,
                clockPreview: (instant: Date, showsDate: Bool, blend: Float)? = nil) throws -> Bool {
        guard available.wait(timeout: wait ? .now()+5 : .now()) == .success else {
            if wait { throw AtlasError.unavailable("GPU neodpovědělo včas.") }
            return false
        }
        var submitted = false
        defer { if !submitted { available.signal() } }
        try prepare(width: target.width, height: target.height)
        guard let command = queue.makeCommandBuffer() else { return false }
        let step = min(1.0/15, max(0, delta))
        let appearance = settings.validated
        let end = elapsed+step*appearance.speed
        // Integrate instead of multiplying the accumulated time by the
        // slider value: live changes cannot jump to a different profile.
        // A nominal profile interval is 24 units of this independent clock.
        let shapeEnd = shapeElapsed+step*24/appearance.shapeDuration
        let field = AtlasField(seed: seed)
        var uniforms = field.uniforms(time: end, delta: step, width: target.width, height: target.height, settings: appearance, shapeTime: shapeEnd)
        if referenceCircle {
            // Diagnostic comparison only: preserve the generated ornament,
            // fixing outline, outer rotation, scale and radial excursion.
            uniforms.sourceShape = SIMD4(0,5,1,0); uniforms.targetShape = uniforms.sourceShape
            uniforms.sourceFrame = SIMD4(1,1,0,0); uniforms.targetFrame = uniforms.sourceFrame
            uniforms.morph.x = 0; uniforms.orbit = .zero; uniforms.layout = SIMD4(0.93,0,0,0)
        }
        var nextClock = clock
        if !referenceCircle {
            nextClock.advance(step,seed: seed,settings: appearance.clock)
            nextClock.apply(to: &uniforms,preview: clockPreview)
        }
        uniforms.style.x *= Float(backing)
        let byteCount = MemoryLayout<AtlasUniforms>.stride
        let drawsGeometry = step > 0 || needsClear
        var history = textures[textureIndex]
        if drawsGeometry {
            guard let compute = command.makeComputeCommandEncoder() else { return false }
            compute.setComputePipelineState(advance)
            compute.setBuffer(segments, offset: 0, index: 0)
            compute.setBytes(&uniforms, length: byteCount, index: 1)
            let group = advance.threadExecutionWidth
            compute.dispatchThreadgroups(MTLSize(width: (settings.density*8*AtlasField.strandCount+group-1)/group, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: group, height: 1, depth: 1))
            compute.endEncoding()
            let destination = textures[1-textureIndex]
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = destination
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,1)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
            if !needsClear {
                encoder.setRenderPipelineState(fade)
                encoder.setFragmentTexture(history, index: 0)
                encoder.setFragmentBytes(&uniforms, length: byteCount, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            encoder.setRenderPipelineState(lines)
            encoder.setVertexBuffer(segments, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: byteCount, index: 1)
            encoder.setFragmentBytes(&uniforms, length: byteCount, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: settings.density*8*AtlasField.strandCount)
            encoder.endEncoding()
            history = destination
        }
        var near = black, far = black
        if uniforms.tint.z > 0 {
            try prepareBloom(width: target.width,height: target.height)
            let extracted = bloomTextures[0], temporary = bloomTextures[1]
            near = bloomTextures[2]; far = bloomTextures[3]
            // Two Gaussian scales: a close colored halo and a much softer outer
            // radiance. All four textures are quarter-size and reused per frame.
            let scale = max(0.75,Float(backing)*0.7)
            let dx = scale/Float(near.width), dy = scale/Float(near.height)
            guard bloomPass(command: command,source: history,target: extracted,pipeline: bloomExtract),
                  bloomPass(command: command,source: extracted,target: temporary,pipeline: bloomBlur,step: SIMD2(dx,0)),
                  bloomPass(command: command,source: temporary,target: near,pipeline: bloomBlur,step: SIMD2(0,dy)),
                  bloomPass(command: command,source: near,target: temporary,pipeline: bloomBlur,step: SIMD2(dx*3,0)),
                  bloomPass(command: command,source: temporary,target: far,pipeline: bloomBlur,step: SIMD2(0,dy*3)) else { return false }
        }
        let presentation = MTLRenderPassDescriptor()
        presentation.colorAttachments[0].texture = target
        presentation.colorAttachments[0].loadAction = .dontCare
        presentation.colorAttachments[0].storeAction = .store
        guard let output = command.makeRenderCommandEncoder(descriptor: presentation) else { return false }
        output.setRenderPipelineState(display)
        output.setFragmentTexture(history, index: 0)
        output.setFragmentTexture(near, index: 1)
        output.setFragmentTexture(far, index: 2)
        output.setFragmentBytes(&uniforms,length: byteCount,index: 0)
        output.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        output.endEncoding()
        let semaphore = available
        command.addCompletedHandler { completed in
            if completed.status == .error { NSLog("Atlas: %@", completed.error?.localizedDescription ?? "Chyba GPU") }
            semaphore.signal()
        }
        if let drawable { command.present(drawable) }
        command.commit(); submitted = true
        if wait {
            command.waitUntilCompleted()
            if let error = command.error { throw error }
        }
        if drawsGeometry {
            textureIndex = 1-textureIndex; needsClear = false
            elapsed = end; shapeElapsed = shapeEnd; clock = nextClock; frameCount += 1
        }
        return true
    }

    func makeSnapshotTarget(width: Int, height: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = .renderTarget; d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { throw AtlasError.unavailable("Snímek se nepodařilo připravit.") }
        return texture
    }

    static func snapshot(_ texture: MTLTexture) -> NSBitmapImageRep {
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: texture.width, pixelsHigh: texture.height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: texture.width*4, bitsPerPixel: 32)!
        texture.getBytes(image.bitmapData!, bytesPerRow: texture.width*4,
                         from: MTLRegionMake2D(0,0,texture.width,texture.height), mipmapLevel: 0)
        // Metal output is BGRA, NSBitmapImageRep expects RGBA.
        let bytes = image.bitmapData!
        for i in stride(from: 0, to: texture.width*texture.height*4, by: 4) {
            let blue = bytes[i]; bytes[i] = bytes[i+2]; bytes[i+2] = blue
        }
        return image.retagging(with: .sRGB) ?? image
    }
}
