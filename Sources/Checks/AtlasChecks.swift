import AppKit
import AVFoundation
import Metal
import simd

enum AtlasChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw AtlasError.unavailable(message) }
    }

    /// Render the actual Metal animation, rather than interpolating stills.
    static func preview() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments.last!).standardizedFileURL
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("morph-preview.mp4")
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let width = 1280, height = 800, fps: Int32 = 30
        let writer = try AVAssetWriter(outputURL: output,fileType: .mp4)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let input = AVAssetWriterInput(mediaType: .video,outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,AVVideoWidthKey: width,AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000,AVVideoMaxKeyFrameIntervalKey: 60],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                       AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                       AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,kCVPixelBufferHeightKey as String: height])
        try require(writer.canAdd(input),"Video vstup se nepodařilo připravit.")
        writer.add(input)
        try require(writer.startWriting(),writer.error?.localizedDescription ?? "Záznam videa se nepodařilo zahájit.")
        writer.startSession(atSourceTime: .zero)
        let settings = AtlasSettings()
        let renderer = try AtlasRenderer(settings: settings,seed: 0xA71A520261022)
        let texture = try renderer.makeSnapshotTarget(width: width,height: height)
        // Match the native preview's 30 Hz history. At the preferred 6x tempo
        // the saved 58 seconds cover 348 seconds of the mathematical score.
        for frame in 0..<58*Int(fps) {
            try autoreleasepool {
                try renderer.render(target: texture,delta: 1.0/Double(fps),wait: true)
                let deadline = Date().addingTimeInterval(10)
                while !input.isReadyForMoreMediaData && writer.status == .writing && Date()<deadline { usleep(1000) }
                try require(input.isReadyForMoreMediaData,"Video kodér přestal přijímat snímky.")
                guard let pool = adaptor.pixelBufferPool else { throw AtlasError.unavailable("Paměť pro video není dostupná.") }
                var buffer: CVPixelBuffer?
                try require(CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer) == kCVReturnSuccess,"Video snímek se nepodařilo vytvořit.")
                guard let buffer else { throw AtlasError.unavailable("Chybí paměť video snímku.") }
                CVBufferSetAttachment(buffer,kCVImageBufferColorPrimariesKey,kCVImageBufferColorPrimaries_ITU_R_709_2,.shouldPropagate)
                CVBufferSetAttachment(buffer,kCVImageBufferTransferFunctionKey,kCVImageBufferTransferFunction_sRGB,.shouldPropagate)
                CVBufferSetAttachment(buffer,kCVImageBufferYCbCrMatrixKey,kCVImageBufferYCbCrMatrix_ITU_R_709_2,.shouldPropagate)
                CVPixelBufferLockBaseAddress(buffer,[])
                texture.getBytes(CVPixelBufferGetBaseAddress(buffer)!,bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                 from: MTLRegionMake2D(0,0,width,height),mipmapLevel: 0)
                CVPixelBufferUnlockBaseAddress(buffer,[])
                try require(adaptor.append(buffer,withPresentationTime: CMTime(value: Int64(frame),timescale: fps)),writer.error?.localizedDescription ?? "Video snímek se nepodařilo uložit.")
            }
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        try require(finished.wait(timeout: .now()+30) == .success && writer.status == .completed,writer.error?.localizedDescription ?? "Dokončení videa selhalo.")
        print("58 s náhledu při rychlosti \(settings.speed)×: \(output.path)")
    }

    static func lighting() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.last!).standardizedFileURL
        try FileManager.default.createDirectory(at: output,withIntermediateDirectories: true)
        let legacy = Data(#"{"speed":1.2,"trail":0.8,"density":96,"lineWidth":0.5,"glow":0.35}"#.utf8)
        let migrated = try JSONDecoder().decode(AtlasSettings.self,from: legacy).validated
        try require(migrated.glow == 1 && migrated.speed == 6 && migrated.trail == 0.8 && migrated.lineWidth == 0.5,"Migrace změnila polohu nastavení.")
        let restored = try JSONDecoder().decode(AtlasSettings.self,from: JSONEncoder().encode(migrated))
        try require(restored.glow == migrated.glow && restored.luminosity == migrated.luminosity,"Opakované načtení znovu převedlo záři.")

        let seed: UInt64 = 0xA71A520261022
        for (name,second,width,height,backing) in [("45s",45,1440,900,1.0),("120s-retina",120,1920,1200,2.0)] {
            var settings = AtlasSettings(speed: 1,shapeDuration: 24); settings.glow = 0
            let renderer = try AtlasRenderer(settings: settings,seed: seed,elapsed: Double(second-3))
            let target = try renderer.makeSnapshotTarget(width: width,height: height)
            for _ in 0..<90 { try renderer.render(target: target,delta: 1.0/30,backing: backing,wait: true) }
            let time = renderer.elapsed, count = renderer.frameCount
            func capture(_ suffix: String) throws -> [UInt8] {
                try renderer.render(target: target,delta: 0,backing: backing,wait: true)
                let image = AtlasRenderer.snapshot(target)
                try image.representation(using: .png,properties: [:])!.write(to: output.appendingPathComponent("\(name)-\(suffix).png"))
                return Array(UnsafeBufferPointer(start: image.bitmapData!,count: image.bytesPerRow*height))
            }
            func energy(_ bytes: [UInt8]) -> Double {
                var sum: Double = 0
                for i in stride(from: 0,to: bytes.count,by: 4) { sum += Double(bytes[i])+Double(bytes[i+1])+Double(bytes[i+2]) }
                return sum
            }
            let off = try capture("glow-0")
            renderer.settings.glow = 1
            let on = try capture("glow-100")
            var halo = 0
            for i in stride(from: 0,to: off.count,by: 4) {
                let a = max(off[i],max(off[i+1],off[i+2]))
                let b = max(on[i],max(on[i+1],on[i+2]))
                if a < 8 && b > 18 { halo += 1 }
            }
            try require(energy(on)>energy(off)*1.08,"Záře nemá dostatečně viditelný vliv.")
            try require(halo>width*height/1000,"Záře nevytváří samostatné světlo kolem vláken.")
            renderer.settings.glow = 0
            let offAgain = try capture("glow-0-again")
            try require(off == offAgain,"Změna záře změnila uloženou kresbu.")
            renderer.settings.luminosity = 0.35
            let low = try capture("light-35")
            renderer.settings.luminosity = 2.5
            let high = try capture("light-250")
            try require(energy(high)>energy(low)*1.3,"Světelnost nemá dostatečně viditelný vliv.")
            renderer.settings = AtlasSettings()
            let normal = try capture("default")
            var dark = 0
            for i in stride(from: 0,to: normal.count,by: 4) {
                if max(normal[i],max(normal[i+1],normal[i+2])) <= 8 { dark += 1 }
            }
            try require(dark>width*height*3/10,"Světlo příliš zaplnilo černé pozadí.")
            try require(renderer.elapsed == time && renderer.frameCount == count,"Úprava světla při pozastavení posunula animaci.")
            print("\(name): záře 0→100 % zvýšila světelný součet o \(Int((energy(on)/energy(off)-1)*100)) %, samostatné halo \(halo) pixelů; návrat na 0 % je pixelově shodný.")
        }
        print("Světelnost, záře, změny při pozastavení a zachování nastavení prošly.")
    }
    static func timing() throws {
        let legacy = Data(#"{"speed":6,"trail":0.8,"density":96,"lineWidth":0.5,"glow":0.7,"luminosity":1.5}"#.utf8)
        let migrated = try JSONDecoder().decode(AtlasSettings.self,from: legacy).validated
        try require(migrated.shapeDuration == AtlasSettings.defaultShapeDuration && migrated.speed == 6 && migrated.trail == 0.8 && migrated.glow == 0.7 && migrated.luminosity == 1.5,"Nový ovladač změnil uložený vzhled.")
        var custom = migrated; custom.shapeDuration = 40
        let restored = try JSONDecoder().decode(AtlasSettings.self,from: JSONEncoder().encode(custom))
        try require(restored.shapeDuration == 40,"Délka tvaru se neobnovila z nastavení.")
        custom.shapeDuration = .nan
        try require(custom.validated.shapeDuration == AtlasSettings.defaultShapeDuration,"Neplatná délka tvaru nemá výchozí hodnotu.")
        custom.shapeDuration = 100
        try require(custom.validated.shapeDuration == 40,"Délka tvaru překročila rozsah ovladače.")

        let seed: UInt64 = 0xA71A520261022
        let renderer = try AtlasRenderer(settings: migrated,seed: seed,elapsed: 27,shapeElapsed: 37)
        let target = try renderer.makeSnapshotTarget(width: 640,height: 400)
        for _ in 0..<30 { try renderer.render(target: target,delta: 1.0/30,wait: true) }
        try require(abs(renderer.elapsed-33)<0.00001 && abs(renderer.shapeElapsed-40)<0.00001,"Oddělené hodiny se neposouvají správně.")
        try require(AtlasField.transition(time: renderer.shapeElapsed).blend>0.1,"Kontrola změny tempa neprobíhá uvnitř proměny.")
        let before = AtlasRenderer.snapshot(target)
        let bytes = Array(UnsafeBufferPointer(start: before.bitmapData!,count: before.bytesPerRow*before.pixelsHigh))
        renderer.settings.shapeDuration = 40
        try renderer.render(target: target,delta: 0,wait: true)
        let after = AtlasRenderer.snapshot(target)
        try require(bytes == Array(UnsafeBufferPointer(start: after.bitmapData!,count: after.bytesPerRow*after.pixelsHigh)),"Změna délky tvaru při pozastavení přeskočila v kresbě.")
        try require(abs(renderer.elapsed-33)<0.00001 && abs(renderer.shapeElapsed-40)<0.00001,"Změna posuvníku posunula čas.")
        for _ in 0..<60 { try renderer.render(target: target,delta: 1.0/30,wait: true) }
        try require(abs(renderer.elapsed-45)<0.00001 && abs(renderer.shapeElapsed-41.2)<0.00001,"Delší setrvání zpomalilo i vnitřní kresbu.")
        renderer.settings.speed = 24
        for _ in 0..<30 { try renderer.render(target: target,delta: 1.0/30,wait: true) }
        try require(abs(renderer.elapsed-69)<0.00001 && abs(renderer.shapeElapsed-41.8)<0.00001,"Rychlost vláken ovlivnila délku tvaru.")

        let field = AtlasField(seed: seed)
        let a = field.uniforms(time: 0,delta: 0,width: 900,height: 900,settings: migrated,shapeTime: 0)
        let b = field.uniforms(time: 6,delta: 0,width: 900,height: 900,settings: migrated,shapeTime: 3)
        try require(a.sourceShape == b.sourceShape && a.morph.x == 0 && b.morph.x == 0,"Obrys se během setrvání proměňuje.")
        try require(a.phase != b.phase,"Setrvání zastavilo ornament.")
        // The hold-to-morph join must be as continuous as the profile join.
        for node in 0..<40 {
            var low = Double(node)*24-12, high = Double(node+1)*24+12
            for _ in 0..<50 {
                let mid = (low+high)/2, transition = AtlasField.transition(time: mid)
                if Double(transition.node)+transition.progress<Double(node)+0.2 { low = mid } else { high = mid }
            }
            let boundary = (low+high)/2
            let l = field.uniforms(time: 200,delta: 0,width: 1600,height: 900,settings: migrated,shapeTime: boundary-0.001)
            let r = field.uniforms(time: 200,delta: 0,width: 1600,height: 900,settings: migrated,shapeTime: boundary+0.001)
            for layer in 0..<AtlasField.strandCount { for sample in 0..<24 {
                let angle = Double(sample)*2 * .pi/24
                try require(simd_length(AtlasField.point(angle,layer: layer,uniforms: l)-AtlasField.point(angle,layer: layer,uniforms: r))<0.00001,"Přechod ze setrvání do morphingu má skok.")
            } }
        }
        renderer.restart()
        try require(renderer.elapsed == 0 && renderer.shapeElapsed == 0,"Nová kresba neobnovila oba časové průběhy.")
        print("Nezávislé tempo vláken a tvarů, návaznost setrvání, migrace nastavení a pixelově shodná změna posuvníku při pozastavení prošly.")
    }

    /// Angular power of the generated ornament on the same fixed circle.
    /// Magnitudes discard global rotation; normalization discards global scale.
    /// Color, outline changes and outside excursions are deliberately excluded.
    static func intrinsicSpectrum(field: AtlasField,time: Double) -> [Double] {
        var u = field.uniforms(time: time,delta: 0,width: 900,height: 900,settings: AtlasSettings())
        u.sourceShape = SIMD4(0,5,1,0); u.targetShape = u.sourceShape
        u.sourceFrame = SIMD4(1,1,0,0); u.targetFrame = u.sourceFrame
        u.morph.x = 0; u.orbit = .zero; u.layout = SIMD4(1,0,0,0)
        var real = [Double](repeating: 0,count: 24), imaginary = real, total = 0.0
        for layer in 1..<AtlasField.strandCount { for sample in 0..<192 {
            let p = AtlasField.point(Double(sample)*2 * .pi/192,layer: layer,uniforms: u)
            let r2 = simd_length_squared(p), a = atan2(p.y,p.x)
            total += r2
            for m in 1...24 {
                real[m-1] += r2*cos(Double(m)*a); imaginary[m-1] += r2*sin(Double(m)*a)
            }
        } }
        return zip(real,imaginary).map { hypot($0.0,$0.1)/total }
    }

    static func checkRotation(output: URL) throws {
        var holds = 0, sameAfterHold = 0, reverseAfterHold = 0, movingJoins = 0, reversals = 0
        var minimumPeak = Double.infinity, maximumSpeed = 0.0, positive = false, negative = false
        var csv = "seed,node,start_seconds,duration_seconds,angle_radians,turn_radians,mode\n"
        for seed: UInt64 in [0xA71A520261022,0x123456789abcdef,0xc001a12] {
            let field = AtlasField(seed: seed)
            var time = 0.0
            for node in 0..<128 {
                let state = field.rotation(time: time), span = state.interval
                try require(span.node == node && span.duration>0,"Rotace přeskočila interval nebo začala znovu.")
                let a = field.rotationAnchor(node: node), b = field.rotationAnchor(node: node+1)
                let turn = AtlasField.angularDifference(b-a)
                csv += "\(seed),\(node),\(span.start/6),\(span.duration/6),\(a),\(turn),\(turn == 0 ? "hold" : "move")\n"
                if turn == 0 {
                    holds += 1
                    let l = field.rotation(time: span.start+span.duration*0.2)
                    let r = field.rotation(time: span.start+span.duration*0.8)
                    try require(l.angle == r.angle && l.velocity == 0 && r.velocity == 0,"Rotace během klidového úseku neudrží stejný úhel.")
                    let u = field.uniforms(time: span.start+span.duration*0.2,delta: 0,width: 900,height: 900,settings: AtlasSettings(),shapeTime: 0)
                    let v = field.uniforms(time: span.start+span.duration*0.8,delta: 0,width: 900,height: 900,settings: AtlasSettings(),shapeTime: 0)
                    try require(u.layout == v.layout && u.phase != v.phase,"Klid rotace zastavil vnitřní kresbu nebo posunul hlavní obrys.")
                    if node>0 {
                        let before = AtlasField.angularDifference(a-field.rotationAnchor(node: node-1))
                        let after = AtlasField.angularDifference(field.rotationAnchor(node: node+2)-b)
                        if before*after>0 { sameAfterHold += 1 }
                        if before*after<0 { reverseAfterHold += 1 }
                    }
                } else {
                    var peak = 0.0
                    for sample in 0..<16 {
                        let t = span.start+span.duration*(Double(sample)+0.5)/16
                        let value = field.rotation(time: t), epsilon = 0.001
                        let l = field.rotation(time: t-epsilon), r = field.rotation(time: t+epsilon)
                        let numerical = AtlasField.angularDifference(r.angle-l.angle)/(2*epsilon)
                        try require(abs(numerical-value.velocity)<0.000001,"Úhel rotace nenavazuje na vypočtenou rychlost.")
                        try require(value.velocity*turn>=0 && abs(value.velocity)<0.06,"Rotace má prudké přetočení nebo překročila rychlostní mez.")
                        peak = max(peak,abs(value.velocity))
                        positive = positive || value.velocity>0.001
                        negative = negative || value.velocity < -0.001
                    }
                    minimumPeak = min(minimumPeak,peak); maximumSpeed = max(maximumSpeed,peak)
                }
                let boundary = span.start+span.duration, epsilon = 0.001
                let l = field.rotation(time: boundary-epsilon), c = field.rotation(time: boundary), r = field.rotation(time: boundary+epsilon)
                try require(abs(AtlasField.angularDifference(r.angle-l.angle))<0.00013 && abs(l.velocity-r.velocity)<0.000001,"Rotace má skok v úhlu nebo rychlosti.")
                try require(abs((c.velocity-l.velocity)/epsilon)<0.0001 && abs((r.velocity-c.velocity)/epsilon)<0.0001,"Rotace má trhavé zrychlení na spoji.")
                let next = AtlasField.angularDifference(field.rotationAnchor(node: node+2)-b)
                if turn*next<0 {
                    reversals += 1
                    try require(abs(c.velocity)<0.000001,"Změna směru neprošla klidem.")
                } else if turn*next>0 {
                    movingJoins += 1
                    try require(c.velocity*turn>0,"Rotace při změně tempa zbytečně zastavila.")
                }
                time = boundary+0.000001
            }
        }
        try require(positive && negative && holds>10 && reversals>10 && movingJoins>10,"Rotaci chybí změny směru, klidové úseky nebo plynulé pokračování.")
        try require(sameAfterHold>2 && reverseAfterHold>2,"Rotace po zastavení předepisuje stále stejný směr.")
        try require(minimumPeak<0.004 && maximumSpeed>0.018,"Tempo rotace se dostatečně nemění.")
        try csv.write(to: output.appendingPathComponent("rotation-timing.csv"),atomically: true,encoding: .utf8)
        print("Rotace: oba směry, \(holds) klidových úseků; po klidu \(sameAfterHold)× stejný směr a \(reverseAfterHold)× opačný. \(movingJoins) spojů pokračuje v pohybu. Rychlosti úseků \(String(format: "%.1f–%.1f",minimumPeak*6*180 / .pi,maximumSpeed*6*180 / .pi)) °/s při 6×; návaznost úhlu, rychlosti a zrychlení prošla.")
    }

    static func checkExcursion(field: AtlasField,output: URL) throws {
        var time = 0.0, durations = [Double](), offSeconds = 0.0, holdSeconds = 0.0
        var csv = "node,start_seconds,duration_seconds,from,to,mode\n"
        for node in 0..<160 {
            let span = field.excursionTransition(time: time)
            try require(span.node == node,"Průběh rozvíjení přeskočil interval nebo začal znovu.")
            let a = field.excursionAnchor(node: node), b = field.excursionAnchor(node: node+1)
            let seconds = span.duration/AtlasSettings.defaultSpeed
            let off = a == .zero && b == .zero, held = a == b
            if off { offSeconds += seconds }
            else if held { holdSeconds += seconds }
            else { durations.append(seconds) }
            csv += "\(node),\(span.start/AtlasSettings.defaultSpeed),\(seconds),\(a.x),\(b.x),\(off ? "off" : held ? "hold" : "move")\n"
            let boundary = span.start+span.duration
            let left = field.excursion(time: boundary-0.0001), right = field.excursion(time: boundary+0.0001)
            try require(simd_length(left-right)<0.00001,"Změna rychlosti rozvíjení má skok.")
            if held {
                try require(field.excursion(time: span.start+span.duration*0.2) == field.excursion(time: span.start+span.duration*0.8),"Rozvíjení se během setrvání stále pohybuje.")
            }
            for f in [0.0,0.25,0.5,0.75,1.0] { for layer in 1..<AtlasField.strandCount {
                let orbit = field.excursion(time: span.start+span.duration*f)
                let weight = AtlasField.excursionWeight(Double(layer-1)/Double(AtlasField.strandCount-2),orbit: orbit)
                try require(weight.isFinite && weight>=0 && weight<=1,"Rozvíjení překročilo bezpečný rozsah.")
            } }
            time = boundary+0.000001
        }
        let mean = durations.reduce(0,+)/Double(durations.count)
        let variation = sqrt(durations.reduce(0) { $0+pow($1-mean,2) }/Double(durations.count))/mean
        try require(durations.min()!<3 && durations.max()!>15 && variation>0.65,"Rychlost rozvíjení zůstává příliš pravidelná.")
        try require(offSeconds>30 && holdSeconds>20,"Chybí vypnuté rozvíjení nebo setrvání bez radiálního pohybu.")
        var fitLow = Float.infinity, fitHigh = -Float.infinity
        for second in stride(from: 0,through: 7200,by: 7) {
            let u = field.uniforms(time: Double(second),delta: 0,width: 900,height: 900,settings: AtlasSettings(),shapeTime: 0)
            fitLow = min(fitLow,u.layout.x); fitHigh = max(fitHigh,u.layout.x)
        }
        try require(fitHigh-fitLow<0.000001,"Hlavní obrys stále mění měřítko podle rozvíjení vláken.")
        try csv.write(to: output.appendingPathComponent("excursion-timing.csv"),atomically: true,encoding: .utf8)
        print("Rozvíjení: přesuny \(String(format: "%.1f–%.1f",durations.min()!,durations.max()!)) s při 6×; variabilita délky \(String(format: "%.2f",variation)); vypnuto \(Int(offSeconds)) s a setrvání \(Int(holdSeconds)) s ve vzorku \(Int(time/6)) s. Měřítko stejného hlavního tvaru zůstává stálé.")
    }

    static func clock(output: URL) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let instant = calendar.date(from: DateComponents(year: 2026,month: 11,day: 12,hour: 21,minute: 37))!
        try require(AtlasClock.encode(instant) == SIMD2(0x2137,0x12112026),"Hodiny nerozložily místní čas a datum.")
        let utc = TimeZone(secondsFromGMT: 0)!
        let plusTwo = TimeZone(secondsFromGMT: 7200)!
        try require(AtlasClock.encode(Date(timeIntervalSince1970: 82800),timeZone: utc) == SIMD2(0x2300,0x01011970)
                    && AtlasClock.encode(Date(timeIntervalSince1970: 82800),timeZone: plusTwo) == SIMD2(0x0100,0x02011970),
                    "Změna místního dne nepřevedla datum.")
        let seed: UInt64 = 0xA71A520261022
        let defaults = AtlasClockSettings()
        let saved = try JSONDecoder().decode(AtlasSettings.self,from: Data(#"{"speed":6,"luminosity":1.2}"#.utf8))
        try require(saved.clock == defaults && saved.luminosity == 1.2,"Původní nastavení se nenačetlo s výchozími hodinami.")
        var edited = saved
        edited.clock = AtlasClockSettings(earliest: 50,latest: 78,duration: 24)
        let roundTrip = try JSONDecoder().decode(AtlasSettings.self,from: JSONEncoder().encode(edited))
        try require(roundTrip.clock == edited.clock,"Časování hodin se neobnovilo z uložených voleb.")
        for options in [defaults,edited.clock,AtlasClockSettings(earliest: 30,latest: 30,duration: 8)] {
            var clock = AtlasClock(), starts = [Double](), ends = [Double](), dates = Set<Bool>(), previous: Float = 0
            let step = 0.05
            while ends.count<12 && clock.elapsed<(options.latest+options.duration+1)*12 {
                clock.advance(step,seed: seed,settings: options)
                let moment = clock.presentation()
                try require(abs(moment.blend-previous)<0.06,"Hodiny při příchodu nebo odchodu přeskočily.")
                if moment.blend>0 && previous==0 { starts.append(clock.elapsed); dates.insert(moment.date) }
                if moment.blend==0 && previous>0 { ends.append(clock.elapsed) }
                previous = moment.blend
            }
            try require(starts.count == 12 && ends.count == 12 && dates.count == 2,"Chybí plánované zobrazení času nebo data.")
            for i in ends.indices {
                let wait = starts[i]-(i == 0 ? 0 : ends[i-1])
                try require(wait >= options.earliest-step && wait <= options.latest+2*step+0.0001
                            && abs(ends[i]-starts[i]-options.duration)<=step+0.0001,
                            "Odstup nebo délka zobrazení neodpovídají uloženým mezím.")
            }
        }
        var manual = AtlasClock()
        manual.showNow(settings: edited.clock); manual.advance(0.2,seed: seed,settings: edited.clock)
        let immediate = manual.presentation()
        try require(immediate.blend>0 && immediate.date,"Ruční zobrazení neotevřelo čas s datem.")
        manual.showNow(settings: defaults)
        try require(manual.presentation().blend==immediate.blend,"Opakovaný příkaz přerušil probíhající proměnu.")
        manual.advance(16,seed: seed,settings: defaults)
        try require(manual.presentation().blend>0,"Změna nastavení zkrátila právě běžící zobrazení.")
        manual.advance(23.7+defaults.earliest-16,seed: seed,settings: defaults)
        try require(manual.presentation().blend==0,"Automatické hodiny přišly příliš brzy po ručním zobrazení.")
        var switched = AtlasClock()
        var disabled = edited.clock; disabled.enabled = false
        switched.showNow(settings: disabled)
        switched.advance(600,seed: seed,settings: disabled)
        try require(switched.presentation().blend==0,"Vypnuté hodiny se přesto zobrazily.")
        switched.advance(0.05,seed: seed,settings: edited.clock)
        try require(switched.presentation().blend==0,"Při zapnutí se neobnovila čekací doba.")
        switched.showNow(settings: edited.clock)
        switched.advance(4,seed: seed,settings: edited.clock)
        try require(switched.presentation().blend==1,"Ruční zobrazení po zapnutí nefunguje.")
        switched.advance(0.5,seed: seed,settings: disabled)
        try require(switched.presentation().blend>0 && switched.presentation().blend<1,"Vypnutí hodin nemá plynulý odchod.")
        switched.advance(1.2,seed: seed,settings: disabled)
        try require(switched.presentation().blend==0,"Vypnuté hodiny se nerozpletly zpět do kresby.")
        for (name,width,height,showsDate) in [("cas-a-datum",1440,900,true),("cas",1440,900,false),("datum-na-vysku",720,1100,true)] {
            let renderer = try AtlasRenderer(settings: AtlasSettings(),seed: seed)
            let target = try renderer.makeSnapshotTarget(width: width,height: height)
            for frame in 0..<162 {
                let age = Double(frame)/30
                let blend = Float(AtlasField.smooth(min(1,age/3.4)))
                let current = frame>=141 ? instant.addingTimeInterval(60) : instant
                try renderer.render(target: target,delta: 1.0/30,wait: true,clockPreview: (current,showsDate,blend))
                if showsDate && width>height && frame==66 {
                    try inspect(texture: target,renderer: renderer,output: output,name: "formovani-hodin",checkOccupancy: false)
                }
            }
            try inspect(texture: target,renderer: renderer,output: output,name: name,checkOccupancy: false)
        }
        print("Hodiny: nepravidelné vstupy, místní čas, přechod přes půlnoc a vykreslení obou řádků prošly.")
    }

    static func run(gallery: Bool = false) throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.last!).standardizedFileURL
        try FileManager.default.createDirectory(at: output,withIntermediateDirectories: true)
        let seed: UInt64 = 0xA71A520261022
        let field = AtlasField(seed: seed), referenceSettings = AtlasSettings(speed: 1,shapeDuration: 24)
        try checkRotation(output: output)
        try checkExcursion(field: field,output: output)
        for aspect in [1.0,16.0/9,21.0/9,9.0/16] {
            // Cover a day of score time, not just the opening moments.
            for minute in stride(from: 0,through: 1440,by: 7) {
                let u = field.uniforms(time: Double(minute*60),delta: 0,width: Int(aspect*900),height: 900,settings: referenceSettings)
                for layer in 0..<AtlasField.strandCount {
                    if !AtlasField.isOpen(u.sourceShape) && !AtlasField.isOpen(u.targetShape) {
                        try require(simd_length(AtlasField.point(0,layer: layer,uniforms: u)-AtlasField.point(2 * .pi,layer: layer,uniforms: u))<0.00001,"Uzavřené vlákno má mezeru.")
                    }
                    for sample in 0..<48 {
                        let p = AtlasField.point(Double(sample)*2 * .pi/48,layer: layer,uniforms: u)
                        try require(p.x.isFinite && p.y.isFinite && abs(p.x)<aspect && abs(p.y)<1,"Kresba opustila dostupnou plochu.")
                    }
                }
            }
        }
        var kinds = Set<Int>()
        for node in 0..<200 {
            let shape = field.descriptor(node: node), frame = AtlasField.frame(shape: shape,aspect: 16.0/9)
            kinds.insert(Int(shape.x))
            if shape.x == 5 {
                for a in [Double.pi/2,Double.pi*1.5] {
                    try require(simd_length(AtlasField.outline(a,shape: shape))<0.000001,"Osmička nemá společný střed.")
                }
                continue
            }
            if shape.x >= 9 {
                if AtlasField.isOpen(shape) {
                    try require(!AtlasField.isOpen(field.descriptor(node: node-1)),"Otevřené motivy následují hned po sobě.")
                    var u = field.uniforms(time: Double(node*24),delta: 0,width: 1600,height: 900,settings: referenceSettings)
                    u.sourceShape = shape; u.targetShape = shape; u.sourceFrame = frame; u.targetFrame = frame
                    for layer in 0..<AtlasField.strandCount {
                        try require(simd_length(AtlasField.point(0,layer: layer,uniforms: u)-AtlasField.point(2 * .pi,layer: layer,uniforms: u))>0.15,"Otevřený motiv spojil konce.")
                    }
                }
                continue
            }
            for outside: Float in [0,1] {
                var u = field.uniforms(time: Double(node*24),delta: 0,width: 1600,height: 900,settings: referenceSettings)
                u.sourceShape = shape; u.targetShape = shape; u.sourceFrame = frame; u.targetFrame = frame
                u.layout = SIMD4(1,0,0,0); u.orbit = SIMD4(outside,0,0,0)
                for layer in 1..<AtlasField.strandCount { for sample in 0..<32 {
                    let p = AtlasField.point(Double(sample)*2 * .pi/32,layer: layer,uniforms: u)
                    let raw = (p-SIMD2(Double(frame.z),Double(frame.w)))/SIMD2(Double(frame.x),Double(frame.y))
                    let ratio = simd_length(raw)/simd_length(AtlasField.outline(atan2(raw.y,raw.x),shape: shape))
                    try require(outside == 0 ? ratio<0.995 : ratio>1.06,"Vlákna nepřešla celá přes hlavní obrys.")
                } }
            }
        }
        try require(kinds.count == AtlasField.profileCount,"Generátor nevyužívá celou paletu profilů.")
        var minimumMotion = Double.infinity
        for second in stride(from: 0,through: 3600,by: 7) {
            var a = field.uniforms(time: Double(second),delta: 0,width: 900,height: 900,settings: referenceSettings)
            var b = field.uniforms(time: Double(second)+0.25,delta: 0,width: 900,height: 900,settings: referenceSettings)
            for isNext in [false,true] {
                if isNext {
                    b.sourceShape = SIMD4(0,5,1,0); b.targetShape = b.sourceShape
                    b.sourceFrame = SIMD4(1,1,0,0); b.targetFrame = b.sourceFrame
                    b.morph.x = 0; b.orbit = .zero; b.layout = SIMD4(1,0,0,0)
                } else {
                    a.sourceShape = SIMD4(0,5,1,0); a.targetShape = a.sourceShape
                    a.sourceFrame = SIMD4(1,1,0,0); a.targetFrame = a.sourceFrame
                    a.morph.x = 0; a.orbit = .zero; a.layout = SIMD4(1,0,0,0)
                }
            }
            var sum = 0.0
            for layer in 1..<AtlasField.strandCount { for sample in 0..<24 {
                let phi = Double(sample)*2 * .pi/24
                sum += simd_length_squared(AtlasField.point(phi,layer: layer,uniforms: a)-AtlasField.point(phi,layer: layer,uniforms: b))
            } }
            let motion = sqrt(sum/Double((AtlasField.strandCount-1)*24))
            minimumMotion = min(minimumMotion,motion)
            try require(motion>0.0006,"Vnitřní ornament zamrzl i po odečtení rotace a morphingu.")
        }
        print("Nejmenší vnitřní pohyb za 0,25 s: \(String(format: "%.4f",minimumMotion)).")
        // Both independently evolving clocks must join without a point jump.
        for motif in [false,true] { for node in 1...100 {
            func index(_ t: Double) -> Int { motif ? field.motifTransition(time: t).node : AtlasField.transition(time: t).node }
            var low = 0.0, high = Double(node)*80+200
            for _ in 0..<50 { let mid = (low+high)/2; if index(mid)<node { low = mid } else { high = mid } }
            let boundary = (low+high)/2
            let a = field.uniforms(time: boundary-0.0001,delta: 0,width: 1600,height: 900,settings: referenceSettings)
            let b = field.uniforms(time: boundary+0.0001,delta: 0,width: 1600,height: 900,settings: referenceSettings)
            for layer in 0..<AtlasField.strandCount { for sample in 0..<32 {
                let phi = Double(sample)*2 * .pi/32
                try require(simd_length(AtlasField.point(phi,layer: layer,uniforms: a)-AtlasField.point(phi,layer: layer,uniforms: b))<0.006,"Při změně profilu nebo harmonické struktury vlákno přeskočilo.")
            } }
        } }
        var spectra = [[Double]](), dominant = Set<Int>(), differences = [Double]()
        for minute in 0..<60 {
            // One real hour at the approved 6x tempo, all on the same circle.
            let spectrum = intrinsicSpectrum(field: field,time: Double(minute*360))
            if let previous = spectra.last {
                differences.append(sqrt(zip(spectrum,previous).reduce(0) { $0+pow($1.0-$1.1,2) }))
            }
            dominant.insert(spectrum.indices.max(by: { spectrum[$0]<spectrum[$1] })!+1)
            spectra.append(spectrum)
        }
        let meanDifference = differences.reduce(0,+)/Double(differences.count)
        try require(dominant.count>=4 && meanDifference>0.04,"Ornament na stejném tvaru se mění převážně jen rotací nebo měřítkem.")
        let csv = spectra.enumerated().map { String($0.offset)+","+$0.element.map { String(format: "%.8f",$0) }.joined(separator: ",") }.joined(separator: "\n")
        try csv.write(to: output.appendingPathComponent("intrinsic-hour.csv"),atomically: true,encoding: .utf8)
        print("Stejný kruh během hodiny: \(dominant.count) dominantních úhlových struktur; průměrná změna spektra bez vlivu barvy, natočení a měřítka \(String(format: "%.4f",meanDifference)).")
        print("Otevřené a uzavřené profily, meze plochy během 24 hodin skóre a návaznost nezávislých proměn prošly.")
        if gallery {
            try clock(output: output)
            let names = ["stuha","vlocka","uzel","srdce","spirala"]
            for (index,name) in names.enumerated() {
                guard let node = (1..<200).first(where: { Int(field.descriptor(node: $0).x) == 9+index }) else {
                    throw AtlasError.unavailable("Chybí cílový profil pro náhled.")
                }
                var low = 0.0, high = Double(node)*24+12
                for _ in 0..<48 {
                    let mid = (low+high)*0.5
                    if AtlasField.transition(time: mid).node < node { low = mid } else { high = mid }
                }
                let r = try AtlasRenderer(settings: referenceSettings,seed: seed,elapsed: high*6,shapeElapsed: high)
                let target = try r.makeSnapshotTarget(width: 1440,height: 900)
                for _ in 0..<100 { try r.render(target: target,delta: 1.0/30,wait: true) }
                try inspect(texture: target,renderer: r,output: output,name: "novy-\(name)",checkOccupancy: true)
            }
            for second in [3,1800,10800,21600] {
                let settings = AtlasSettings()
                let start = max(0,Double(second)-3*settings.speed)
                let r = try AtlasRenderer(settings: settings,seed: seed,elapsed: start)
                let target = try r.makeSnapshotTarget(width: 1000,height: 1000)
                let frames = Int(((Double(second)-start)/settings.speed*30).rounded())
                for _ in 0..<frames { try r.render(target: target,delta: 1.0/30,wait: true,referenceCircle: true) }
                try inspect(texture: target,renderer: r,output: output,name: "fixed-circle-\(second)s",checkOccupancy: false)
            }
            for second in [1,24,60,120,240,600,900,1800,3600,7200,14400,21600] {
                let r = try AtlasRenderer(settings: referenceSettings,seed: seed,elapsed: Double(max(0,second-3)))
                let target = try r.makeSnapshotTarget(width: 1440,height: 900)
                for _ in 0..<min(90,second*30) { try r.render(target: target,delta: 1.0/30,wait: true) }
                try inspect(texture: target,renderer: r,output: output,name: "generative-\(second)s",checkOccupancy: true)
            }
            return
        }
        let renderer = try AtlasRenderer(settings: referenceSettings,seed: seed)
        let texture = try renderer.makeSnapshotTarget(width: 1440,height: 900)
        let frames = [360,1350,3600,9000,27000]
        for frame in 1...frames.last! {
            try renderer.render(target: texture,delta: 1.0/30,wait: true)
            if frames.contains(frame) { try inspect(texture: texture,renderer: renderer,output: output,name: "atlas-\(frame/30)s",checkOccupancy: true) }
        }
        for (name,width,height) in [("ultrawide",1920,720),("portrait",720,1280)] {
            // Find an actual longitudinal target among generated profiles.
            var selected = 1
            for node in 1..<200 { if field.descriptor(node: node).x == 4 { selected = node; break } }
            var low = 0.0, high = Double(selected)*30+200
            for _ in 0..<50 { let mid = (low+high)/2; if AtlasField.transition(time: mid).node<selected { low = mid } else { high = mid } }
            let r = try AtlasRenderer(settings: referenceSettings,seed: seed,elapsed: max(0,high-3))
            let target = try r.makeSnapshotTarget(width: width,height: height)
            for _ in 0..<90 { try r.render(target: target,delta: 1.0/30,wait: true) }
            try inspect(texture: target,renderer: r,output: output,name: "atlas-\(name)",checkOccupancy: true)
        }
        for speed in [AtlasSettings.defaultSpeed,AtlasSettings.speedRange.upperBound] {
            let fast = try AtlasRenderer(settings: AtlasSettings(speed: speed),seed: seed)
            let target = try fast.makeSnapshotTarget(width: 1440,height: 900)
            for _ in 0..<180 { try fast.render(target: target,delta: 1.0/60,wait: true) }
            try require(abs(fast.elapsed-3*speed)<0.0001,"Rychlost \(speed)× neposouvá animaci správně.")
            try inspect(texture: target,renderer: fast,output: output,name: "atlas-speed-\(Int(speed))",checkOccupancy: true)
        }
        print("Metal: 15 minut kreslení a tempa 1× i 10× prošla; výstup: \(output.path)")
    }

    private static func inspect(texture: MTLTexture,renderer: AtlasRenderer,output: URL,name: String,checkOccupancy: Bool,checkBothAxes: Bool = false) throws {
        let image = AtlasRenderer.snapshot(texture)
        let width = image.pixelsWide, height = image.pixelsHigh, pixels = image.bitmapData!
        var lit = 0, bright = 0, dark = 0
        var minX = width, maxX = 0, minY = height, maxY = 0
        var sectors = [Int](repeating: 0,count: 12)
        for y in 0..<height { for x in 0..<width {
            let offset = (y*width+x)*4
            let value = max(pixels[offset],max(pixels[offset+1],pixels[offset+2]))
            if value > 12 {
                lit += 1; sectors[min(2,y*3/height)*4+min(3,x*4/width)] += 1
                minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
            }
            if value > 180 { bright += 1 }
            if value <= 8 { dark += 1 }
        } }
        let coverage = Double(lit)/Double(width*height)
        let reachX = Double(maxX-minX+1)/Double(width), reachY = Double(maxY-minY+1)/Double(height)
        print("\(name): kresba \(String(format: "%.1f",coverage*100)) %, jasná jádra \(String(format: "%.2f",Double(bright)/Double(width*height)*100)) %, černé pozadí \(String(format: "%.1f",Double(dark)/Double(width*height)*100)) %, oblasti \(sectors.filter{$0>30}.count)/12")
        try image.representation(using: .png,properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))
        if checkOccupancy {
            try require(coverage > 0.005,"Kresba je prázdná.")
            // Bloom intentionally lights pixels beyond the fine core lines.
            // Guard actual near-black negative space rather than counting the
            // halo as if its whole area were thick geometry.
            try require(dark>width*height*3/10,"Světlo příliš zaplnilo černé pozadí.")
            // A rectangle rotated across a portrait/ultrawide viewport can
            // occupy one row/column while still spanning its available axis.
            // Separately check a longitudinal stage reaches both screen axes.
            // Interpolating opposite lobes can temporarily fold a profile
            // inward. Stable framing deliberately avoids zooming into that
            // fold; keep the stronger reach check for settled landmarks.
            let blend = AtlasField.transition(time: renderer.shapeElapsed).blend
            let minimumReach = blend>0.02 && blend<0.98 ? 0.45 : 0.55
            try require(sectors.filter{$0>30}.count >= 4 && max(reachX,reachY)>minimumReach,"Obrazec je příliš malý pro dostupnou plochu.")
            if checkBothAxes { try require(min(reachX,reachY)>0.65,"Podélná fáze nevyužívá obě osy plochy.") }
        }
    }
}
