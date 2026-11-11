import AppKit
import ScreenSaver

@objc(AtlasExtension)
final class AtlasExtension: ScreenSaverExtension {}

@objc(AtlasExtensionViewController)
final class AtlasExtensionViewController: ScreenSaverViewController {
    override func loadView() {
        view = AtlasSaverView(frame: NSRect(x: 0,y: 0,width: 640,height: 400),isPreview: false)!
    }
    override func startAnimation() {
        (view as? AtlasSaverView)?.requestIdlePreview(false)
        super.startAnimation()
    }
    override func stopAnimation() {
        super.stopAnimation()
        // Only an explicit host stop may show the poster. Real playback
        // starts directly in Metal without flashing the idle thumbnail.
        (view as? AtlasSaverView)?.requestIdlePreview(true)
    }
}

@objc(AtlasConfigurationViewController)
final class AtlasConfigurationViewController: ScreenSaverConfigurationViewController {
    private var options: AtlasOptionsController?
    override func loadView() {
        let options = AtlasOptionsController(apply: { _ in },done: { [weak self] in self?.configureSheetDidEnd() })
        self.options = options; view = options.view; preferredContentSize = options.preferredContentSize
    }
    override func configureSheetWillPresent() { super.configureSheetWillPresent(); options?.reload() }
    override func viewWillAppear() { super.viewWillAppear(); options?.reload() }
}
