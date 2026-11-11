import AppKit
import MetalKit

final class AtlasView: MTKView, MTKViewDelegate {
    let renderer: AtlasRenderer
    private var lastTime: CFTimeInterval?
    private var envelope = AtlasPlaybackEnvelope()
    private var systemPaused = false
    var pauseTransitionDuration = 0.0
    var animationPaused = false {
        didSet { if oldValue != animationPaused { updatePlayback() } }
    }
    var failureHandler: ((Error) -> Void)?

    init(frame: NSRect, renderer: AtlasRenderer) {
        self.renderer = renderer
        super.init(frame: frame, device: renderer.device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        clearColor = MTLClearColorMake(0,0,0,1)
        preferredFramesPerSecond = 30
        enableSetNeedsDisplay = false
        delegate = self
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) není podporováno") }
    func resetTiming() { lastTime = nil }
    func setPlaybackSuspended(_ paused: Bool,immediate: Bool = false) {
        systemPaused = paused; updatePlayback(immediate: immediate)
    }
    private func updatePlayback(immediate: Bool = false) {
        let paused = animationPaused || systemPaused
        let duration = immediate ? 0 : pauseTransitionDuration
        let wasStopped = isPaused
        envelope.setPaused(paused,duration: duration,at: CACurrentMediaTime())
        if duration<=0 || (!paused && wasStopped) { lastTime = nil }
        isPaused = paused && (duration<=0 || envelope.rate(at: CACurrentMediaTime()) == 0)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { lastTime = nil }

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable else { return }
        let now = CACurrentMediaTime()
        let elapsed = min(1.0/15,max(0,lastTime.map { now - $0 } ?? 1.0/30))
        let delta = envelope.animationTime(from: now-elapsed,to: now)
        do {
            if try renderer.render(target: drawable.texture, delta: delta,
                                   backing: Double(window?.backingScaleFactor ?? 1), drawable: drawable) {
                lastTime = now
                if envelope.target == 0 && envelope.rate(at: now) == 0 { isPaused = true }
            }
        } catch {
            animationPaused = true
            updatePlayback(immediate: true)
            failureHandler?(error)
            NSLog("Atlas: %@", error.localizedDescription)
        }
    }
}
