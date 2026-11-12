import AppKit
import ScreenSaver
import ObjectiveC

func check(_ condition: @autoclosure ()->Bool,_ message: String) {
    precondition(condition(),message)
}
for (control, speed) in [(1.0, 6.0), (5.0, 12.0), (10.0, 24.0)] {
    check(abs(AtlasSettings.speed(forControl: control)-speed)<0.000001,"Nesprávný převod stupnice rychlosti.")
    check(abs(AtlasSettings(speed: speed).speedControlValue-control)<0.000001,"Uložené tempo má nesprávnou polohu ovladače.")
}
var previousSpeed = 0.0
for tick in 0...900 {
    let control = 1+Double(tick)/100
    let speed = AtlasSettings.speed(forControl: control)
    check(speed>previousSpeed,"Stupnice rychlosti není rostoucí.")
    check(abs(AtlasSettings(speed: speed).speedControlValue-control)<0.000001,"Převod rychlosti mění uložené tempo.")
    previousSpeed = speed
}
check(AtlasSettings(speed: 0.3).validated.speed == 6,"Staré pomalé nastavení nepřešlo na nové minimum.")
check(AtlasSettings(speed: 12).validated.speed == 12,"Staré tempo se při načtení změnilo.")
check(AtlasSettings(speed: .nan).validated.speed == 6,"Neplatné tempo nemá výchozí hodnotu.")
print("Nová stupnice 1–10×, zachování tempa a převody 6/12/24 prošly.")

_ = NSApplication.shared
for fps in [30,60,120,144] {
    var playback = AtlasPlaybackEnvelope()
    playback.setPaused(true,duration: 2,at: 0)
    var elapsed = 0.0
    for frame in 0..<fps*4 {
        elapsed += playback.animationTime(from: Double(frame)/Double(fps),to: Double(frame+1)/Double(fps))
        playback.setPaused(true,duration: 2,at: Double(frame+1)/Double(fps))
    }
    check(abs(elapsed-1)<0.000001 && playback.rate(at: 4) == 0,"Brzdění závisí na frekvenci snímků nebo se stále obnovuje.")
    playback.setPaused(false,duration: 2,at: 4)
    check(playback.rate(at: 4) == 0,"Obnovení přehrávání má skok.")
    check(abs(playback.animationTime(from: 4,to: 6)-1)<0.000001,"Rozjezd neposouvá čas plynule.")
    playback.setPaused(true,duration: 2,at: 7)
    let rate = playback.rate(at: 7.4)
    playback.setPaused(false,duration: 2,at: 7.4)
    check(abs(playback.rate(at: 7.4)-rate)<0.000001,"Změna směru brzdění má skok.")
    playback.setPaused(true,duration: 0,at: 7.5)
    check(playback.rate(at: 7.5) == 0 && playback.animationTime(from: 7.5,to: 20) == 0,"Urgentní pauza stále posouvá animaci.")
}
for flag in 0..<7 {
    var state = AtlasPauseState()
    switch flag {
    case 0: state.asleep = true
    case 1: state.inactive = true
    case 2: state.locked = true
    case 3: state.saver = true
    case 4: state.fullscreen = true
    case 5: state.hidden = true
    default: state.manual = true
    }
    check(state.paused,"Důvod pauzy nezastavil přehrávání.")
    check(state.urgent == (flag<4),"Nesprávná priorita okamžité pauzy.")
}
var combined = AtlasPauseState(); combined.fullscreen = true; combined.manual = true
combined.manual = false
check(combined.systemPaused && combined.paused,"Ruční pokračování obešlo pauzu při celé obrazovce.")
combined.manual = true; combined.fullscreen = false
check(combined.paused && !combined.systemPaused,"Návrat z celé obrazovky zrušil ruční pauzu.")
print("Pauzy, priority a dvousekundové brzdění při 30–144 Hz prošly.")

guard let service = NSClassFromString("NSServiceViewController") else { fatalError("Služba ViewBridge není dostupná.") }
check(AtlasExtensionViewController.isSubclass(of: service),"Nesprávná nadtřída spořiče.")
check(AtlasConfigurationViewController.isSubclass(of: service),"Nesprávná nadtřída konfigurace.")
check(class_getInstanceMethod(AtlasConfigurationViewController.self,NSSelectorFromString("configureSheetDidEnd")) != nil,"Chybí ukončení voleb rozšíření.")
for name in ["AtlasExtension","AtlasExtensionViewController","AtlasConfigurationViewController"] { check(NSClassFromString(name) != nil,"Chybí třída rozšíření.") }
print("Rozšíření splňuje runtime rozhraní ViewBridge.")

let options = AtlasOptionsController(apply: { _ in },done: {})
_ = options.view; options.view.layoutSubtreeIfNeeded()
let stack = options.view.subviews.first as! NSStackView
check(stack.fittingSize.height+44<=options.preferredContentSize.height,"Volby přesahují rozměry panelu.")
let clockSliders = stack.arrangedSubviews.compactMap { $0 as? NSStackView }.flatMap { $0.arrangedSubviews }.compactMap { $0 as? NSSlider }
check(stack.arrangedSubviews.filter { $0 is NSSlider }.count == 6 && clockSliders.map(\.tag) == [6,7,8]
      && stack.arrangedSubviews.compactMap { $0 as? NSStackView }.flatMap { $0.arrangedSubviews }.contains { $0 is NSSwitch },
      "Chybí ovladač kresby nebo časování hodin.")

// Exercise actual Metal/ScreenSaverView lifecycle without writing user cursors.
let saver = AtlasSaverView(frame: NSRect(x: 0,y: 0,width: 640,height: 400),isPreview: true)!
let window = NSWindow(contentRect: saver.frame,styleMask: [.titled],backing: .buffered,defer: false)
window.isReleasedWhenClosed = false; window.contentView = saver; window.orderFrontRegardless()
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
saver.startAnimation()
for _ in 0..<20 { saver.animateOneFrame() }
let count = saver.animationFrameCount
check(count>0,"Systémový spořič nevykreslil první snímek.")
saver.startAnimation(); check(saver.animationFrameCount == count,"Opakovaný start resetoval obraz.")
saver.stopAnimation(); saver.requestIdlePreview(true)
for _ in 0..<10 { saver.animateOneFrame() }
check(saver.animationFrameCount == count,"Zastavený spořič pokračuje ve vykreslování.")
let sheetA = saver.configureSheet!, sheetB = saver.configureSheet!
check(sheetA !== sheetB && saver.hasConfigureSheet,"Volby spořiče nelze otevřít opakovaně.")
saver.startAnimation(); saver.animateOneFrame()
check(saver.animationFrameCount>count,"Spořič po zastavení nepokračuje.")
saver.stopAnimation(); window.orderOut(nil)
print("Metal lifecycle, opakovaný start/stop, klid a opakované volby prošly.")
