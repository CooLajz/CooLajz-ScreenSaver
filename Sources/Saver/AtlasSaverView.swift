import AppKit
import ScreenSaver

@objc(AtlasSaverView)
final class AtlasSaverView: ScreenSaverView {
    private var canvas: AtlasView?
    private var active = false
    private var idlePreview = false
    private var configurationWindow: NSWindow?
    private var lastSave = 0.0
    private var activity = 0.0
    private static weak var writer: AtlasSaverView?
    private lazy var poster: NSImage? = Bundle(for: AtlasSaverView.self).url(forResource: "Atlas-Poster",withExtension: "png").flatMap(NSImage.init(contentsOf:))
    var animationFrameCount: Int { canvas?.renderer.frameCount ?? 0 }

    override init?(frame: NSRect,isPreview: Bool) { super.init(frame: frame,isPreview: isPreview); prepare() }
    required init?(coder: NSCoder) { super.init(coder: coder); prepare() }
    private func prepare() {
        animationTimeInterval = 1.0/30; wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        do {
            let defaults = AtlasSettings.defaults
            let seed = defaults.string(forKey: "saver."+AtlasField.journeySeedKey).flatMap(UInt64.init)
                ?? defaults.string(forKey: AtlasField.journeySeedKey).flatMap(UInt64.init) ?? .random(in: 1...UInt64.max)
            let time = defaults.object(forKey: "saver."+AtlasField.journeyTimeKey) as? Double ?? defaults.double(forKey: AtlasField.journeyTimeKey)
            let shape = defaults.object(forKey: "saver."+AtlasField.journeyShapeTimeKey) as? Double
            let renderer = try AtlasRenderer(seed: seed,elapsed: time,shapeElapsed: shape)
            let canvas = AtlasView(frame: bounds,renderer: renderer)
            canvas.isPaused = true; canvas.autoresizingMask = [.width,.height]
            addSubview(canvas); self.canvas = canvas
        } catch {
            let label = NSTextField(wrappingLabelWithString: "Kresbu nelze spustit. \(error.localizedDescription)")
            label.textColor = .white; label.frame = bounds.insetBy(dx: 24,dy: 24)
            label.autoresizingMask = [.width,.height]; addSubview(label)
        }
    }
    override func startAnimation() {
        requestIdlePreview(false); canvas?.renderer.settings = .load()
        guard !active else { return }
        super.startAnimation(); active = true
        canvas?.animationPaused = false; canvas?.isPaused = true; canvas?.resetTiming()
        if !isPreview && (Self.writer == nil || ProcessInfo.processInfo.systemUptime-(Self.writer?.activity ?? 0)>2) { Self.writer = self }
    }
    override func stopAnimation() {
        if active { saveJourney() }
        active = false; canvas?.animationPaused = true
        if Self.writer === self { Self.writer = nil }
        super.stopAnimation()
    }
    override func animateOneFrame() {
        guard active else { return }
        canvas?.draw(); activity = ProcessInfo.processInfo.systemUptime
        if !isPreview && (Self.writer == nil || activity-(Self.writer?.activity ?? 0)>2) { Self.writer = self }
        if activity-lastSave>20 { saveJourney() }
    }
    private func saveJourney() {
        guard !isPreview,Self.writer === self,let renderer = canvas?.renderer,renderer.frameCount>0 else { return }
        let defaults = AtlasSettings.defaults
        defaults.set(String(renderer.seed),forKey: "saver."+AtlasField.journeySeedKey)
        defaults.set(renderer.elapsed,forKey: "saver."+AtlasField.journeyTimeKey)
        defaults.set(renderer.shapeElapsed,forKey: "saver."+AtlasField.journeyShapeTimeKey)
        lastSave = ProcessInfo.processInfo.systemUptime
    }
    func requestIdlePreview(_ requested: Bool) {
        idlePreview = requested; canvas?.isHidden = requested && !active; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard idlePreview && !active,let poster,poster.size.width>0,poster.size.height>0 else { return }
        let scale = min(bounds.width/poster.size.width,bounds.height/poster.size.height)
        let size = NSSize(width: poster.size.width*scale,height: poster.size.height*scale)
        poster.draw(in: NSRect(x: (bounds.width-size.width)/2,y: (bounds.height-size.height)/2,width: size.width,height: size.height))
    }
    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        let options = AtlasOptionsController(apply: { [weak self] settings in self?.canvas?.renderer.settings = settings },done: { [weak self] in
            guard let sheet = self?.configurationWindow else { return }
            sheet.sheetParent?.endSheet(sheet); sheet.orderOut(nil)
        })
        let sheet = NSWindow(contentViewController: options); sheet.title = "Atlas · Vzhled kresby"
        sheet.styleMask = [.titled,.closable]; sheet.isReleasedWhenClosed = false
        configurationWindow = sheet; return sheet
    }
}
