import Foundation

/// Analytic integration keeps the two-second wallpaper easing independent
/// of frame cadence. Retargeting preserves the current playback rate.
struct AtlasPlaybackEnvelope {
    private var start = 0.0, duration = 0.0, initial = 1.0
    private(set) var target = 1.0
    func rate(at time: Double) -> Double {
        guard duration>0 else { return target }
        let u = min(1,max(0,(time-start)/duration))
        return initial+(target-initial)*u*u*(3-2*u)
    }
    mutating func setPaused(_ paused: Bool,duration: Double,at time: Double) {
        let value = paused ? 0.0 : 1.0
        guard value != target || duration<=0 else { return }
        initial = rate(at: time); target = value; start = time; self.duration = max(0,duration)
    }
    private func integral(_ time: Double) -> Double {
        let elapsed = time-start
        guard duration>0 else { return elapsed*target }
        guard elapsed>0 else { return elapsed*initial }
        let u = min(1,elapsed/duration)
        return initial*min(elapsed,duration)+(target-initial)*duration*(u*u*u-0.5*u*u*u*u)+max(0,elapsed-duration)*target
    }
    func animationTime(from a: Double,to b: Double) -> Double { max(0,integral(b)-integral(a)) }
}

struct AtlasPauseState {
    var asleep = false, inactive = false, locked = false, saver = false
    var fullscreen = false, hidden = false, manual = false
    var urgent: Bool { asleep || inactive || locked || saver }
    var systemPaused: Bool { urgent || fullscreen || hidden }
    var paused: Bool { systemPaused || manual }
    var reason: String {
        if asleep { return "Displej spí" }
        if inactive { return "Neaktivní relace" }
        if locked { return "Mac je zamčený" }
        if saver { return "Běží systémový spořič" }
        if manual { return "Pozastaveno" }
        if fullscreen { return "Aplikace přes celou obrazovku" }
        if hidden { return "Náhled není viditelný" }
        return "Živé pozadí"
    }
}
