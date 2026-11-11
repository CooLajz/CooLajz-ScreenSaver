import AppKit

/// Shared controls for the companion app, legacy saver and extension host.
final class AtlasOptionsController: NSViewController {
    private let apply: (AtlasSettings) -> Void
    private let done: (() -> Void)?
    private var labels: [Int:NSTextField] = [:]
    private var sliders: [Int:NSSlider] = [:]
    private var settings = AtlasSettings.load()
    private let titles = ["Rychlost","Délka tvaru","Doznívání","Světelnost","Síla čáry","Záře"]
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
        let values = [settings.speedControlValue,settings.shapeDuration,settings.trail,settings.luminosity,settings.lineWidth,settings.glow]
        let ranges = [AtlasSettings.speedControlRange,AtlasSettings.shapeDurationRange,0.15...3,0.35...2.5,0.4...1.2,0...1]
        for index in 0..<values.count {
            let label = NSTextField(labelWithString: text(index,values[index])); labels[index] = label; stack.addArrangedSubview(label)
            let slider = NSSlider(value: values[index],minValue: ranges[index].lowerBound,maxValue: ranges[index].upperBound,target: self,action: #selector(change(_:)))
            slider.tag = index; slider.isContinuous = true; slider.setAccessibilityLabel(titles[index])
            sliders[index] = slider
            slider.widthAnchor.constraint(equalToConstant: 286).isActive = true; stack.addArrangedSubview(slider)
        }
        if done != nil {
            let button = NSButton(title: "Hotovo",target: self,action: #selector(finish)); button.keyEquivalent = "\r"
            stack.addArrangedSubview(button)
        }
        view = NSView(frame: NSRect(x: 0,y: 0,width: 334,height: done == nil ? 510 : 550))
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor,constant: 24),stack.trailingAnchor.constraint(equalTo: view.trailingAnchor,constant: -24),stack.topAnchor.constraint(equalTo: view.topAnchor,constant: 22),stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor,constant: -22)])
        preferredContentSize = view.frame.size
    }
    func reload() {
        settings = .load()
        let values = [settings.speedControlValue,settings.shapeDuration,settings.trail,settings.luminosity,settings.lineWidth,settings.glow]
        for (index,value) in values.enumerated() { sliders[index]?.doubleValue = value; labels[index]?.stringValue = text(index,value) }
    }
    private func text(_ index: Int,_ value: Double) -> String {
        let detail: String
        switch index {
        case 0: detail = String(format: "%.1f×",value)
        case 1: detail = String(format: "≈ %.0f s",value)
        case 2: detail = String(format: "%.2f s",value)
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
        default: settings.glow = v
        }
        settings = settings.validated; settings.save(); apply(settings)
        labels[slider.tag]?.stringValue = text(slider.tag,v)
    }
    @objc private func finish() { done?() }
}
