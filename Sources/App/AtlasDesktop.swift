import AppKit
import ServiceManagement

private final class AtlasDesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One renderer moves between the preview and a passive desktop surface.
/// Only window metadata is read; no screen recording or accessibility access.
final class AtlasDesktopController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let canvas: AtlasView
    private let preview: NSWindow
    private var desktop: AtlasDesktopWindow?
    private var status: NSStatusItem?
    private var timer: Timer?
    private var observers: [(NotificationCenter,NSObjectProtocol)] = []
    private var presentation: NSKeyValueObservation?
    private var outsideClick: Any?
    private var state = AtlasPauseState()
    private var lastApplied: (Bool,Bool,Bool)?
    var onOptions: (() -> Void)?
    var onPause: (() -> Void)?
    var onNew: (() -> Void)?
    var onShow: (() -> Void)?
    var isActive: Bool { desktop != nil }
    init(canvas: AtlasView,preview: NSWindow) {
        self.canvas = canvas; self.preview = preview
        super.init()
        AtlasSettings.defaults.register(defaults: ["pauseForFullScreen":true])
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.didstart","com.apple.screensaver.didstop","com.apple.screenIsLocked","com.apple.screenIsUnlocked"] {
            distributed.addObserver(self,selector: #selector(idleStateChanged(_:)),name: Notification.Name(name),object: nil,suspensionBehavior: .deliverImmediately)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name,kind,value) in [(NSWorkspace.screensDidSleepNotification,0,true),(NSWorkspace.screensDidWakeNotification,0,false),(NSWorkspace.willSleepNotification,0,true),(NSWorkspace.didWakeNotification,0,false),(NSWorkspace.sessionDidResignActiveNotification,1,true),(NSWorkspace.sessionDidBecomeActiveNotification,1,false)] {
            observe(workspace,name) { [weak self] _ in
                guard let self else { return }
                if kind == 0 { self.state.asleep = value } else { self.state.inactive = value }
                self.refresh()
            }
        }
        observe(workspace,NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.refresh() }
        observe(workspace,NSWorkspace.didActivateApplicationNotification) { [weak self] _ in self?.refresh() }
        observe(.default,NSWindow.didChangeOcclusionStateNotification) { [weak self] _ in self?.refresh() }
        observe(.default,NSApplication.didChangeScreenParametersNotification) { [weak self] _ in self?.updateScreen() }
        presentation = NSApp.observe(\.currentSystemPresentationOptions,options: [.new]) { [weak self] _,_ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refreshSession()
    }
    private func observe(_ center: NotificationCenter,_ name: Notification.Name,_ block: @escaping (Notification)->Void) {
        let token = center.addObserver(forName: name,object: nil,queue: .main,using: block)
        observers.append((center,token))
    }
    @objc private func idleStateChanged(_ note: Notification) {
        switch note.name.rawValue {
        case "com.apple.screensaver.didstart": state.saver = true
        case "com.apple.screensaver.didstop": state.saver = false
        case "com.apple.screenIsLocked": state.locked = true
        case "com.apple.screenIsUnlocked": state.locked = false; state.saver = false
        default: return
        }
        refresh()
    }
    func start() {
        guard desktop == nil, !preview.styleMask.contains(.fullScreen), let screen = NSScreen.screens.first else { return }
        let window = AtlasDesktopWindow(contentRect: screen.frame,styleMask: .borderless,backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false; window.backgroundColor = .black; window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow))+1)
        window.collectionBehavior = [.canJoinAllSpaces,.stationary,.ignoresCycle]
        window.ignoresMouseEvents = true; window.isExcludedFromWindowsMenu = true
        desktop = window
        preview.orderOut(nil); canvas.removeFromSuperview(); preview.contentView = NSView()
        canvas.pauseTransitionDuration = 2
        window.contentView = canvas; canvas.frame = NSRect(origin: .zero,size: screen.frame.size)
        canvas.autoresizingMask = [.width,.height]; canvas.resetTiming()
        installStatus(); NSApp.setActivationPolicy(.accessory); window.orderFrontRegardless()
        AtlasSettings.defaults.set(true,forKey: "liveWallpaper.v1")
        let timer = Timer(timeInterval: 1,repeats: true) { [weak self] _ in self?.refreshSession() }
        timer.tolerance = 0.2; RunLoop.main.add(timer,forMode: .common); self.timer = timer
        lastApplied = nil; refresh()
    }
    func stop() {
        guard desktop != nil else { return }
        timer?.invalidate(); timer = nil
        canvas.removeFromSuperview(); desktop?.contentView = nil; desktop?.close(); desktop = nil
        preview.contentView = canvas; canvas.frame = NSRect(origin: .zero,size: preview.contentLayoutRect.size)
        canvas.pauseTransitionDuration = 0; canvas.resetTiming()
        if let status { NSStatusBar.system.removeStatusItem(status) }; status = nil
        removeOutsideClick(); AtlasSettings.defaults.set(false,forKey: "liveWallpaper.v1")
        NSApp.setActivationPolicy(.regular); preview.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        lastApplied = nil; refresh()
    }
    private func updateScreen() {
        guard let desktop, let screen = NSScreen.screens.first else { refresh(); return }
        desktop.setFrame(screen.frame,display: true); refresh()
    }
    private func refreshSession() {
        if let session = CGSessionCopyCurrentDictionary() as? [String:Any] {
            state.locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
            if let console = session[kCGSessionOnConsoleKey as String] as? Bool { state.inactive = !console }
        }
        refresh()
    }
    private func coverage() -> (saver: Bool,fullscreen: Bool) {
        guard let screen = (desktop ?? preview).screen ?? NSScreen.screens.first,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else { return (false,false) }
        let display = CGDisplayBounds(number.uint32Value)
        var full = false
        for info in windows {
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber, pidNumber.int32Value != ProcessInfo.processInfo.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int, layer>=0,
                  let raw = info[kCGWindowBounds as String] as? [String:Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary),rect.insetBy(dx: -2,dy: -2).contains(display),
                  (info[kCGWindowAlpha as String] as? Double ?? 1)>0 else { continue }
            if layer>=CGWindowLevelForKey(.screenSaverWindow) { return (true,full) }
            if NSRunningApplication(processIdentifier: pidNumber.int32Value)?.activationPolicy == .regular { full = true }
        }
        return (false,full)
    }
    func refresh() {
        var decision = state
        let covered = !state.asleep && !state.inactive && !state.locked ? coverage() : (saver:false,fullscreen:false)
        decision.saver = decision.saver || covered.saver
        decision.manual = canvas.animationPaused
        decision.fullscreen = isActive && AtlasSettings.defaults.bool(forKey: "pauseForFullScreen")
            && (desktop?.isOnActiveSpace == false || NSApp.currentSystemPresentationOptions.contains(.fullScreen) || covered.fullscreen)
        decision.hidden = NSApp.isHidden || (!isActive && (preview.isMiniaturized || !preview.occlusionState.contains(.visible)))
        let systemPause = decision.systemPaused
        let applied = (systemPause,decision.urgent,isActive)
        if lastApplied == nil || lastApplied!.0 != applied.0 || lastApplied!.1 != applied.1 || lastApplied!.2 != applied.2 {
            canvas.setPlaybackSuspended(systemPause,immediate: decision.urgent)
            lastApplied = applied
            NSLog("Atlas: přehrávání %@, %@, snímek %d",decision.paused ? "pozastaveno" : "běží",decision.reason,canvas.renderer.frameCount)
        }
        status?.button?.toolTip = "Atlas · \(decision.reason)"
        status?.menu?.items.first?.title = "Atlas · \(decision.reason)"
    }
    private func installStatus() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles",accessibilityDescription: "Atlas")
        item.button?.image?.isTemplate = true
        let menu = NSMenu(); menu.delegate = self
        let title = menu.addItem(withTitle: "Atlas · Živé pozadí",action: nil,keyEquivalent: ""); title.isEnabled = false
        for (title,action) in [("Upravit kresbu…",#selector(options)),("Pozastavit / pokračovat",#selector(pause)),("Pozastavit při celé obrazovce",#selector(toggleFullscreenPause)),("Nová kresba",#selector(newJourney)),("Návrat do okna",#selector(show)),("Nastavení systémového spořiče…",#selector(openSaver)),("Spouštět po přihlášení",#selector(toggleLogin))] {
            let entry = menu.addItem(withTitle: title,action: action,keyEquivalent: ""); entry.target = self
        }
        menu.addItem(.separator()); let quit = menu.addItem(withTitle: "Ukončit Atlas",action: #selector(NSApplication.terminate(_:)),keyEquivalent: "q"); quit.target = NSApp
        item.menu = menu; status = item
    }
    @objc private func options() { onOptions?() }
    @objc private func pause() { onPause?(); refresh() }
    @objc private func newJourney() { onNew?() }
    @objc private func show() { onShow?() }
    @objc private func openSaver() { AtlasInstallation.openSettings() }
    @objc private func toggleFullscreenPause() {
        AtlasSettings.defaults.set(!AtlasSettings.defaults.bool(forKey: "pauseForFullScreen"),forKey: "pauseForFullScreen"); refresh()
    }
    @objc private func toggleLogin() {
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
            else {
                guard AtlasInstallation.isInstalled else { throw AtlasError.unavailable("Nejprve přesuňte aplikaci do složky Aplikace a znovu ji otevřete.") }
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch { NSApp.activate(ignoringOtherApps: true); NSAlert(error: error).runModal() }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(pause) { menuItem.state = canvas.animationPaused ? .on : .off }
        if menuItem.action == #selector(toggleFullscreenPause) { menuItem.state = AtlasSettings.defaults.bool(forKey: "pauseForFullScreen") ? .on : .off }
        if menuItem.action == #selector(toggleLogin) { menuItem.state = SMAppService.mainApp.status == .enabled ? .on : SMAppService.mainApp.status == .requiresApproval ? .mixed : .off }
        return true
    }
    func menuWillOpen(_ menu: NSMenu) {
        removeOutsideClick()
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown,.rightMouseDown,.otherMouseDown]) { [weak menu] _ in DispatchQueue.main.async { menu?.cancelTracking() } }
    }
    func menuDidClose(_ menu: NSMenu) { removeOutsideClick() }
    private func removeOutsideClick() { if let outsideClick { NSEvent.removeMonitor(outsideClick) }; outsideClick = nil }
    deinit {
        timer?.invalidate(); removeOutsideClick()
        for (center,token) in observers { center.removeObserver(token) }
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
