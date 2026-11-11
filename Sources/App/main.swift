import AppKit
import MetalKit

final class AtlasApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    private var window: NSWindow!
    private var canvas: AtlasView!
    private var renderer: AtlasRenderer!
    private var settingsPopover: NSPopover?
    private var pauseItem: NSToolbarItem?
    private var desktop: AtlasDesktopController!
    private var optionsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let defaults = AtlasSettings.defaults
            let seed = defaults.string(forKey: AtlasField.journeySeedKey).flatMap(UInt64.init) ?? .random(in: 1...UInt64.max)
            renderer = try AtlasRenderer(seed: seed, elapsed: defaults.double(forKey: AtlasField.journeyTimeKey),
                                         shapeElapsed: defaults.object(forKey: AtlasField.journeyShapeTimeKey) as? Double)
            canvas = AtlasView(frame: NSRect(x: 0,y: 0,width: 1200,height: 750), renderer: renderer)
            window = NSWindow(contentRect: canvas.frame, styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            window.title = "Atlas — CooLajz ScreenSaver"
            window.subtitle = "Jemná světelná kresba"
            window.contentView = canvas
            window.contentMinSize = NSSize(width: 640,height: 400)
            window.backgroundColor = .black
            window.appearance = NSAppearance(named: .darkAqua)
            window.collectionBehavior = [.fullScreenPrimary]
            window.delegate = self
            window.isReleasedWhenClosed = false
            let toolbar = NSToolbar(identifier: "AtlasToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact
            canvas.failureHandler = { [weak self] error in self?.show(error) }
            desktop = AtlasDesktopController(canvas: canvas,preview: window)
            desktop.onOptions = { [weak self] in self?.presentOptions() }
            desktop.onPause = { [weak self] in self?.togglePause() }
            desktop.onNew = { [weak self] in self?.newJourney() }
            desktop.onShow = { [weak self] in self?.showWindow() }
            installMenus()
            window.center(); window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if AtlasSettings.defaults.bool(forKey: "liveWallpaper.v1") { desktop.start() }
            else { desktop.refresh() }
            AtlasInstallation.register()
            NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: NSApplication.didHideNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(resume), name: NSApplication.didUnhideNotification, object: nil)
            // Persist a small mathematical cursor; never save a screen bitmap.
            Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.saveJourney() }
        } catch {
            show(error); NSApp.terminate(nil)
        }
    }

    private func installMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "O aplikaci Atlas", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ukončit Atlas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let artItem = NSMenuItem(); main.addItem(artItem)
        let art = NSMenu(title: "Kresba"); artItem.submenu = art
        let pause = art.addItem(withTitle: "Pozastavit / pokračovat", action: #selector(togglePause), keyEquivalent: " ")
        pause.keyEquivalentModifierMask = []
        let new = art.addItem(withTitle: "Nová kresba", action: #selector(newJourney), keyEquivalent: "n")
        new.keyEquivalentModifierMask = []
        let full = art.addItem(withTitle: "Celá obrazovka", action: #selector(fullscreen), keyEquivalent: "f")
        full.keyEquivalentModifierMask = []
        let escape = art.addItem(withTitle: "Opustit celou obrazovku", action: #selector(leaveFullscreen), keyEquivalent: "\u{1b}")
        escape.keyEquivalentModifierMask = []
        art.addItem(.separator())
        art.addItem(withTitle: "Živé pozadí plochy",action: #selector(toggleWallpaper),keyEquivalent: "")
        art.addItem(withTitle: "Nastavení systémového spořiče…",action: #selector(openSaverSettings),keyEquivalent: "")
        art.addItem(.separator())
        art.addItem(withTitle: "Uložit snímek…", action: #selector(saveSnapshot), keyEquivalent: "s")
        NSApp.mainMenu = main
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("pause"), .init("new"), .init("settings"), .init("desktop"), .init("full")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        let config: (String,String,Selector)
        switch id.rawValue {
        case "pause": config = ("pause", "Pozastavit kresbu (mezerník)", #selector(togglePause)); pauseItem = item
        case "new": config = ("shuffle", "Začít novou kresbu (N)", #selector(newJourney))
        case "settings": config = ("slider.horizontal.3", "Upravit kresbu", #selector(options(_:)))
        case "desktop": config = ("desktopcomputer", "Živé pozadí plochy", #selector(toggleWallpaper))
        case "full": config = ("arrow.up.left.and.arrow.down.right", "Celá obrazovka (F)", #selector(fullscreen))
        default: return nil
        }
        item.image = NSImage(systemSymbolName: config.0, accessibilityDescription: config.1)
        item.label = config.1; item.toolTip = config.1
        item.target = self; item.action = config.2
        return item
    }

    @objc private func togglePause() {
        canvas.animationPaused.toggle()
        desktop?.refresh()
        pauseItem?.image = NSImage(systemSymbolName: canvas.animationPaused ? "play" : "pause", accessibilityDescription: canvas.animationPaused ? "Pokračovat v kresbě" : "Pozastavit kresbu")
    }
    @objc private func newJourney() { renderer.restart(); saveJourney() }
    @objc private func fullscreen() { if !desktop.isActive { window.toggleFullScreen(nil) } }
    @objc private func leaveFullscreen() { if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) } }
    @objc private func suspend() { desktop?.refresh() }
    @objc private func resume() { desktop?.refresh() }
    func windowDidMiniaturize(_ notification: Notification) { suspend() }
    func windowDidDeminiaturize(_ notification: Notification) { resume() }
    func windowWillClose(_ notification: Notification) { if !desktop.isActive { saveJourney(); NSApp.terminate(nil) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !desktop.isActive }
    func applicationShouldHandleReopen(_ sender: NSApplication,hasVisibleWindows: Bool) -> Bool { showWindow(); return false }
    @objc private func toggleWallpaper() {
        settingsPopover?.close(); optionsWindow?.close(); optionsWindow = nil
        if desktop.isActive { showWindow() } else { desktop.start() }
    }
    private func showWindow() {
        optionsWindow?.close(); optionsWindow = nil
        if desktop.isActive { desktop.stop() }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        desktop.refresh()
    }
    @objc private func openSaverSettings() { AtlasInstallation.openSettings() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleWallpaper) { item.state = desktop.isActive ? .on : .off; return !window.styleMask.contains(.fullScreen) }
        if item.action == #selector(fullscreen) { return !desktop.isActive }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { saveJourney() }

    private func saveJourney() {
        guard let renderer else { return }
        AtlasSettings.defaults.set(String(renderer.seed), forKey: AtlasField.journeySeedKey)
        AtlasSettings.defaults.set(renderer.elapsed, forKey: AtlasField.journeyTimeKey)
        AtlasSettings.defaults.set(renderer.shapeElapsed, forKey: AtlasField.journeyShapeTimeKey)
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Atlas"
        alert.informativeText = "CooLajz ScreenSaver · plynulé proměny tvarů\n\nKruhy, hvězdice, mnohoúhelníky, osmičky, trojlisty, čtyřlisty, astroidy a zaoblené čtverce se proměňují jako jeden celek. Sestava se průběžně otáčí. Jemný ornament se rozvíjí za obrys a vrací dovnitř.\n\nMezerník: pozastavení · N: nová kresba · F: celá obrazovka"
        alert.addButton(withTitle: "Zavřít"); alert.runModal()
    }
    private func show(_ error: Error) { let alert = NSAlert(error: error); alert.runModal() }

    @objc private func options(_ sender: NSToolbarItem) { presentOptions() }
    private func presentOptions() {
        if settingsPopover?.isShown == true { settingsPopover?.close(); return }
        let controller = AtlasOptionsController { [weak self] settings in
            guard let self else { return }
            self.renderer.settings = settings
            if self.canvas.isPaused { self.canvas.draw() }
        }
        if desktop.isActive {
            optionsWindow?.close()
            let panel = NSWindow(contentViewController: controller)
            panel.title = "Atlas · Vzhled kresby"; panel.styleMask = [.titled,.closable]
            panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named: .darkAqua)
            optionsWindow = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let popover = NSPopover(); popover.contentViewController = controller; popover.behavior = .transient
            _ = controller.view; popover.contentSize = controller.preferredContentSize
            settingsPopover = popover
            popover.show(relativeTo: NSRect(x: canvas.bounds.width-120,y: canvas.bounds.height-1,width: 1,height: 1),of: canvas,preferredEdge: .minY)
        }
    }

    @objc private func saveSnapshot() {
        let wasPaused = canvas.animationPaused
        canvas.animationPaused = true
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Atlas.png"; panel.allowedContentTypes = [.png]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            defer { self.canvas.animationPaused = wasPaused }
            guard response == .OK, let url = panel.url else { return }
            do {
                let texture = try self.renderer.makeSnapshotTarget(width: max(1,Int(self.canvas.drawableSize.width)),height: max(1,Int(self.canvas.drawableSize.height)))
                try self.renderer.render(target: texture,delta: 0,wait: true)
                let data = AtlasRenderer.snapshot(texture).representation(using: .png,properties: [:])!
                try data.write(to: url)
            } catch { self.show(error) }
        }
    }
}

if CommandLine.arguments.contains("--morph-preview") {
    do { try AtlasChecks.preview(); exit(0) }
    catch { fputs("Náhled selhal: \(error)\n",stderr); exit(1) }
}
if CommandLine.arguments.contains("--lighting-check") {
    do { try AtlasChecks.lighting(); exit(0) }
    catch { fputs("Kontrola světla selhala: \(error)\n",stderr); exit(1) }
}
if CommandLine.arguments.contains("--timing-check") {
    do { try AtlasChecks.timing(); exit(0) }
    catch { fputs("Kontrola časování selhala: \(error)\n",stderr); exit(1) }
}
if CommandLine.arguments.contains("--render-check") || CommandLine.arguments.contains("--geometry-gallery") {
    do { try AtlasChecks.run(gallery: CommandLine.arguments.contains("--geometry-gallery")); exit(0) }
    catch { fputs("Kontrola selhala: \(error)\n",stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AtlasApp()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
