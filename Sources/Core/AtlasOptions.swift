import AppKit

/// Shared controls for the companion app, legacy saver and extension host.
final class AtlasOptionsController: NSViewController {
    private let apply: (AtlasSettings) -> Void
    private let done: (() -> Void)?
    private var labels: [Int:NSTextField] = [:]
    private var sliders: [Int:NSSlider] = [:]
    private var settings = AtlasSettings.load()
    private var clockSwitch: NSSwitch?
    private var clockControls: [NSView] = []
    private let titles = ["Rychlost","Délka tvaru","Doznívání","Světelnost","Síla čáry","Záře","Nejdříve","Nejpozději","Jak dlouho"]
    private var values: [Double] {
        [settings.speedControlValue,settings.shapeDuration,settings.trail,settings.luminosity,settings.lineWidth,settings.glow,
         settings.clock.earliest,settings.clock.latest,settings.clock.duration]
    }
    init(apply: @escaping (AtlasSettings) -> Void,done: (() -> Void)? = nil) {
        self.apply = apply; self.done = done
        super.init(nibName: nil,bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) není podporováno") }
    override func loadView() {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        let title = NSTextField(labelWithString: "Vzhled kresby"); title.font = .systemFont(ofSize: 17,weight: .semibold)
        stack.addArrangedSubview(title)
        let note = NSTextField(wrappingLabelWithString: "Rychlost ovládá vlákna a rotaci. Délka tvaru určuje odstup proměn. Světelnost a záře fungují i při pozastavení.")
        note.preferredMaxLayoutWidth = 286; note.textColor = .secondaryLabelColor; stack.addArrangedSubview(note)
        let ranges = [AtlasSettings.speedControlRange,AtlasSettings.shapeDurationRange,0.15...3,0.35...2.5,0.4...1.2,0...1,
                      AtlasClockSettings.delayRange,AtlasClockSettings.delayRange,AtlasClockSettings.durationRange]
        for (index,value) in values.enumerated() {
            if index == 6 {
                let heading = NSTextField(labelWithString: "Zobrazovat hodiny")
                heading.font = .systemFont(ofSize: 13,weight: .semibold)
                let toggle = NSSwitch()
                toggle.target = self; toggle.action = #selector(toggleClock(_:))
                toggle.setAccessibilityLabel("Zobrazovat hodiny")
                clockSwitch = toggle
                let row = NSStackView(views: [heading,toggle]); row.spacing = 12; row.alignment = .centerY
                stack.addArrangedSubview(row)
                let hint = NSTextField(wrappingLabelWithString: "Náhodný odstup mezi zobrazeními.")
                hint.preferredMaxLayoutWidth = 286; hint.textColor = .secondaryLabelColor
                hint.font = .systemFont(ofSize: 11)
                stack.addArrangedSubview(hint); clockControls.append(hint)
            }
            let label = NSTextField(labelWithString: text(index,value)); labels[index] = label
            let slider = NSSlider(value: value,minValue: ranges[index].lowerBound,maxValue: ranges[index].upperBound,target: self,action: #selector(change(_:)))
            slider.tag = index; slider.isContinuous = true; slider.setAccessibilityLabel(titles[index])
            sliders[index] = slider
            if index < 6 {
                slider.widthAnchor.constraint(equalToConstant: 286).isActive = true
                stack.addArrangedSubview(label); stack.addArrangedSubview(slider)
            } else {
                label.widthAnchor.constraint(equalToConstant: 152).isActive = true
                slider.widthAnchor.constraint(equalToConstant: 126).isActive = true
                let row = NSStackView(views: [label,slider]); row.spacing = 8; row.alignment = .centerY
                stack.addArrangedSubview(row); clockControls.append(row)
            }
        }
        if done != nil {
            let button = NSButton(title: "Hotovo",target: self,action: #selector(finish)); button.keyEquivalent = "\r"
            stack.addArrangedSubview(button)
        }
        view = NSView(frame: NSRect(x: 0,y: 0,width: 334,height: done == nil ? 650 : 690))
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor,constant: 24),stack.trailingAnchor.constraint(equalTo: view.trailingAnchor,constant: -24),stack.topAnchor.constraint(equalTo: view.topAnchor,constant: 22),stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor,constant: -22)])
        preferredContentSize = view.frame.size
        refreshControls()
    }
    func reload() {
        settings = .load()
        refreshControls()
    }
    private func refreshControls() {
        clockSwitch?.state = settings.clock.enabled ? .on : .off
        clockControls.forEach { $0.isHidden = !settings.clock.enabled }
        for (index,value) in values.enumerated() { sliders[index]?.doubleValue = value; labels[index]?.stringValue = text(index,value) }
    }
    private func text(_ index: Int,_ value: Double) -> String {
        let detail: String
        switch index {
        case 0: detail = String(format: "%.1f×",value)
        case 1: detail = String(format: "≈ %.0f s",value)
        case 2: detail = String(format: "%.2f s",value)
        case 6,7,8:
            let seconds = Int(value.rounded()), minutes = seconds/60, rest = seconds%60
            detail = minutes == 0 ? "\(rest) s" : (rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s")
        case 4: detail = String(format: "%.2f",value)
        default: detail = "\(Int(value*100)) %"
        }
        return "\(titles[index]) · \(detail)"
    }
    @objc private func change(_ slider: NSSlider) {
        let v = slider.doubleValue
        switch slider.tag {
        case 0: settings.speed = AtlasSettings.speed(forControl: v)
        case 1: settings.shapeDuration = v
        case 2: settings.trail = v
        case 3: settings.luminosity = v
        case 4: settings.lineWidth = v
        case 5: settings.glow = v
        case 6:
            settings.clock.earliest = (v/5).rounded()*5
            settings.clock.latest = max(settings.clock.latest,settings.clock.earliest)
        case 7:
            settings.clock.latest = (v/5).rounded()*5
            settings.clock.earliest = min(settings.clock.earliest,settings.clock.latest)
        case 8: settings.clock.duration = v.rounded()
        default: return
        }
        settings = settings.validated; settings.save(); apply(settings)
        refreshControls()
    }
    @objc private func toggleClock(_ sender: NSSwitch) {
        settings.clock.enabled = sender.state == .on
        settings.save(); apply(settings); refreshControls()
    }
    @objc private func finish() { done?() }
}
