import Foundation
import simd

/// Independently evolving harmonic fields mapped through open and closed profiles.
/// Counter-derived targets and incommensurate phases have no playlist reset.
struct AtlasField {
    let seed: UInt64
    static let strandCount = 14
    static let profileCount = 14

    // One arm of the dendrite, ordered along its perimeter. The two root
    // points meet the neighboring arms after a 60° rotation.
    static let snowflakeArm: [SIMD2<Double>] = {
        let half = [SIMD2(0.10,-0.10/sqrt(3.0)), SIMD2(0.41,-0.055),
                    SIMD2(0.66,-0.30), SIMD2(0.70,-0.27), SIMD2(0.54,-0.048),
                    SIMD2(0.73,-0.033), SIMD2(0.88,-0.16), SIMD2(0.91,-0.13),
                    SIMD2(0.83,-0.028)]
        return half + [SIMD2(1,0)] + half.reversed().map { SIMD2($0.x,-$0.y) }
    }()

    static func isOpen(_ shape: SIMD4<Float>) -> Bool { shape.x == 9 || shape.x == 13 }

    static func rotate(_ p: SIMD2<Double>,_ angle: Double) -> SIMD2<Double> {
        SIMD2(p.x*cos(angle)-p.y*sin(angle),p.x*sin(angle)+p.y*cos(angle))
    }
    static let journeySeedKey = "morphJourneySeed.v1"
    static let journeyTimeKey = "morphJourneyTime.v1"
    static let journeyShapeTimeKey = "morphJourneyShapeTime.v1"

    struct Transition {
        let node: Int
        let progress: Double
        let blend: Double
    }

    static func hash(_ input: UInt64) -> UInt64 {
        var x = input &+ 0x9e3779b97f4a7c15
        x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
        x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
        return x ^ (x >> 31)
    }

    static func transition(time: Double) -> Transition {
        let t = time.isFinite ? max(0,time) : 0
        let clock = t/24+0.13*sin(t*sqrt(2)/61)+0.09*sin(t*sqrt(3)/103)
        let node = Int(floor(clock)), f = clock-Double(node)
        // Keep the profile recognizable briefly; its rotation and ornament
        // still advance on their own clock. Quintic easing joins the hold
        // and the following morph with zero first and second derivatives.
        return Transition(node: node,progress: f,blend: smooth(max(0,(f-0.2)/0.8)))
    }

    static func smooth(_ f: Double) -> Double { f*f*f*(f*(f*6-15)+10) }

    func motifTransition(time: Double) -> Transition {
        let t = max(0,time)
        let clock = t/67+0.16*sin(t*sqrt(5)/157)+0.11*sin(t*sqrt(7)/239)+unit(0,0xb0)
        let node = Int(floor(clock)), f = clock-Double(node)
        return Transition(node: node,progress: f,blend: Self.smooth(f))
    }

    func unit(_ counter: Int,_ channel: UInt64) -> Double {
        Double(Self.hash(seed ^ (UInt64(max(0,counter)) &* 0xd1342543de82ef95) ^ channel)>>11)/9007199254740992
    }

    func descriptor(node: Int) -> SIMD4<Float> {
        if node == 0 { return SIMD4(0,5,1,0) }
        let family = Int(unit(node,0x10)*13)
        let sides = Float(3+Int(unit(node,0x20)*7))
        let depth = Float(unit(node,0x30))
        // Separate channels preserve the original palette's proportions.
        // Space open profiles apart so the change in silhouette feels special.
        let opening = unit(node,0x91)
        if opening < 0.12 && unit(node-1,0x91) >= 0.12 {
            if unit(node,0x92) < 0.68 { return SIMD4(9,0,0.19+0.12*depth,0) }
            return SIMD4(13,1.13+0.45*depth,0.23+0.15*depth,Float(unit(node,0x93))*2 * .pi)
        }
        let alternate = unit(node,0x94)
        if alternate < 0.085 { return SIMD4(10,0,0.70+0.30*depth,-.pi/2) }
        if alternate < 0.17 { return SIMD4(11,unit(node,0x95)<0.65 ? 3 : 5,0.19+0.11*depth,Float(unit(node,0x96))*2 * .pi) }
        if alternate < 0.24 { return SIMD4(12,0,0.78+0.22*depth,0) }
        // kind, profile order, profile parameter, orientation. These are
        // generated targets, not a repeating list of shape presets.
        switch family {
        case 0: return SIMD4(0,5,1,0)
        case 1,2: return SIMD4(1,max(4,sides),0.32+depth*0.34,-.pi/2)
        case 3: return SIMD4(2,4,1,.pi/4)
        case 4: return SIMD4(3,4,0.72+depth*0.65,.pi/4)
        case 5: return SIMD4(2,3,1,-.pi/2)
        case 6: return SIMD4(2,sides,1,-.pi/2)
        case 7: return SIMD4(4,4,0.72+depth*0.65,0)
        case 8,9: return SIMD4(5,Float(unit(node,0x40)*0.4-0.2),0.38+depth*0.28,family == 8 ? 0 : .pi/2)
        case 10: return SIMD4(6,min(8,sides),0.18+depth*0.22,-.pi/2)
        case 11: return SIMD4(7,4,2.8+depth*3.6,0)
        default: return SIMD4(8,4,1,0)
        }
    }

    func harmonics(node: Int) -> SIMD4<Float> {
        let order = 2+Int(unit(node,0xa1)*7)
        let a = unit(node,0xa2)<0.5 ? 1 : -1
        let b = unit(node,0xa3)<0.5 ? 2 : -2
        let c = unit(node,0xa4)<0.5 ? 3 : -3
        return SIMD4(Float(1+a*order),Float(1+b*order),Float(1+c*order),Float(order))
    }

    struct MotionInterval {
        let node: Int
        let start: Double
        let duration: Double
        let progress: Double
    }

    struct RotationState {
        let angle: Double
        let velocity: Double
        let interval: MotionInterval
    }

    static func angularDifference(_ delta: Double) -> Double { atan2(sin(delta),cos(delta)) }

    func rotationAnchor(node: Int) -> Double {
        let held = node & 1 != 0 && unit(node/2,0xe0)<0.35
        let n = held ? node-1 : node
        return n<=0 ? 0 : unit(n,0xe1)*2 * .pi
    }

    /// Angle-dependent minimum durations bound angular speed. The remaining
    /// time is distributed unevenly, independently of the excursion clock.
    func rotationDurations(block: Int) -> SIMD8<Double> {
        var durations = SIMD8<Double>(repeating: 0), weights = durations
        var minimum = 0.0, total = 0.0
        for i in 0..<8 {
            let node = block*8+i
            let delta = Self.angularDifference(rotationAnchor(node: node+1)-rotationAnchor(node: node))
            durations[i] = 6+2.2*abs(delta)/0.06
            weights[i] = exp(log(16)*unit(node,0xe2))
            minimum += durations[i]; total += weights[i]
        }
        // Even eight maximum half-turns leave a positive time budget.
        return durations+weights*((1024-minimum)/total)
    }

    /// A C2 angular spline on the circle. Shared endpoint velocities keep
    /// same-direction turns moving through a node; reversals ease to rest.
    /// Repeated anchors create real holds without prescribing the next sign.
    func rotation(time: Double) -> RotationState {
        let t = max(0,time), block = Int(floor(t/1024))
        let durations = rotationDurations(block: block)
        var start = Double(block)*1024, index = 7
        for i in 0..<8 {
            if t<start+durations[i] || i == 7 { index = i; break }
            start += durations[i]
        }
        let node = block*8+index, duration = durations[index]
        let u = min(1,max(0,(t-start)/duration))
        let interval = MotionInterval(node: node,start: start,duration: duration,progress: u)
        let a = rotationAnchor(node: node), b = rotationAnchor(node: node+1)
        let delta = Self.angularDifference(b-a)
        if delta == 0 { return RotationState(angle: a,velocity: 0,interval: interval) }
        let previousDuration = index>0 ? durations[index-1] : (block>0 ? rotationDurations(block: block-1)[7] : duration)
        let nextDuration = index<7 ? durations[index+1] : rotationDurations(block: block+1)[0]
        let before = node>0 ? Self.angularDifference(a-rotationAnchor(node: node-1))/previousDuration : 0
        let after = Self.angularDifference(rotationAnchor(node: node+2)-b)/nextDuration
        let secant = delta/duration
        func tangent(_ x: Double,_ y: Double) -> Double {
            x*y>0 ? (x>0 ? 1 : -1)*0.9*min(abs(x),abs(y)) : 0
        }
        let v0 = tangent(before,secant), v1 = tangent(secant,after)
        let u2 = u*u, u3 = u2*u, u4 = u3*u, u5 = u4*u
        let h0 = u-6*u3+8*u4-3*u5, h1 = -4*u3+7*u4-3*u5
        let position = a+delta*Self.smooth(u)+duration*(v0*h0+v1*h1)
        let velocity = secant*30*u2*(1-u)*(1-u)
            + v0*(1-18*u2+32*u3-15*u4)+v1*(-12*u2+28*u3-15*u4)
        return RotationState(angle: position,velocity: velocity,interval: interval)
    }

    /// Random-access trajectory with unequal segment lengths. Each block
    /// continues from the previous target; its boundary never resets motion.
    /// Fixed-size blocks bound CPU work even after many days of playback.
    func excursionTransition(time: Double) -> MotionInterval {
        let t = max(0,time), block = Int(floor(t/480))
        var weights = SIMD8<Double>(repeating: 0), total = 0.0
        for i in 0..<8 {
            let weight = exp(log(64)*unit(block*8+i,0xd0))
            weights[i] = weight; total += weight
        }
        var start = Double(block)*480
        for i in 0..<8 {
            let duration = 4+448*weights[i]/total
            if t<start+duration || i == 7 {
                return MotionInterval(node: block*8+i,start: start,duration: duration,
                                      progress: min(1,max(0,(t-start)/duration)))
            }
            start += duration
        }
        preconditionFailure("Průběh rozvíjení nemá interval.")
    }

    func excursionAnchor(node: Int) -> SIMD4<Float> {
        // Repeated targets give genuine holds, including completely disabled
        // excursions. All ornament phases continue throughout these holds.
        let held = node & 1 != 0 && unit(node/2,0xd1)<0.5
        let n = held ? node-1 : node
        if n == 0 || unit(n,0xd2)<0.32 { return .zero }
        return SIMD4(Float(0.12+0.88*unit(n,0xd3)),
                     Float((unit(n,0xd4)-0.5)*0.36),
                     Float((unit(n,0xd5)-0.5)*0.32),0)
    }

    func excursion(time: Double) -> SIMD4<Float> {
        let transition = excursionTransition(time: time)
        let a = excursionAnchor(node: transition.node), b = excursionAnchor(node: transition.node+1)
        if a == b { return a }
        let blend = Float(Self.smooth(transition.progress))
        return a*(1-blend)+b*blend
    }

    /// Adjacent strands remain a coherent bundle, with a smooth radial
    /// gradient instead of a simultaneous full-strength expansion.
    static func excursionWeight(_ q: Double,orbit: SIMD4<Float>) -> Double {
        smooth(min(1,max(0,Double(orbit.x)+Double(orbit.y)*(2*q-1)+Double(orbit.z)*sin(q * .pi))))
    }

    /// C2 soft limit above the outline: preserve inner detail, reserve space
    /// for outer strands, and keep the camera independent of the excursion.
    static func projectedRadius(_ radius: Double) -> Double {
        let excess = max(0,radius-1)
        return radius<=1 ? radius : 1+excess/sqrt(1+excess*excess/0.16)
    }

    static func outline(_ angle: Double,shape: SIMD4<Float>,tiltPhase: Double = 0) -> SIMD2<Double> {
        let kind = Int(shape.x)
        let unit = SIMD2(cos(angle),sin(angle))
        if kind == 5 {
            let p = SIMD2(cos(angle),Double(shape.z)*sin(2*angle)*(1+Double(shape.y)*cos(angle)))
            let a = Double(shape.w)
            return SIMD2(p.x*cos(a)-p.y*sin(a),p.x*sin(a)+p.y*cos(a))
        }
        if kind == 10 {
            let count = snowflakeArm.count-1
            let position = (angle/(2 * .pi)).truncatingRemainder(dividingBy: 1)
            let ring = (position < 0 ? position+1 : position)*6
            let arm = min(5,Int(ring)), along = (ring-Double(arm))*Double(count)
            let edge = min(count-1,Int(along)), f = along-Double(edge)
            var p = snowflakeArm[edge]*(1-f)+snowflakeArm[edge+1]*f
            // Depth affects the branches, while the root junction stays exact.
            p.y *= 1-(1-Double(shape.z))*min(1,max(0,(p.x-0.10)*4))
            return rotate(p,Double(arm)*(.pi/3)+Double(shape.w))
        }
        if kind == 11 {
            let a = angle*Double(shape.y), b = 2*angle, depth = Double(shape.z)
            let r = 0.68+depth*cos(a), tilt = 0.54+0.48*sin(tiltPhase+Double(shape.w))
            return SIMD2(r*cos(b), r*sin(b)*cos(tilt)+depth*sin(a)*sin(tilt))
        }
        if kind == 12 {
            let x = unit.y*unit.y*unit.y*Double(shape.z)
            let y = (13*unit.x-5*cos(2*angle)-2*cos(3*angle)-cos(4*angle)+2)/16
            return SIMD2(-x,y)
        }
        var radius = 1.0
        if kind == 6 {
            radius = 1-Double(shape.z)+Double(shape.z)*cos(Double(shape.y)*(angle-Double(shape.w)))
        } else if kind == 7 {
            let n = Double(shape.z)
            radius = pow(pow(abs(unit.x),n)+pow(abs(unit.y),n),-1/n)
        } else if kind == 8 {
            radius = pow(pow(abs(unit.x),2.0/3)+pow(abs(unit.y),2.0/3),-1.5)
        } else if kind == 1 || kind == 2 || kind == 3 {
            let star = kind == 1
            let count = Int(shape.y)*(star ? 2 : 1)
            let step = 2 * Double.pi/Double(count)
            let position = (angle-Double(shape.w))/step
            let edge = Int(floor(position)), delta = (position-floor(position))*step
            let a = star && edge & 1 != 0 ? Double(shape.z) : 1
            let b = star && edge & 1 == 0 ? Double(shape.z) : 1
            radius = a*b*sin(step)/(b*sin(step-delta)+a*sin(delta))
        }
        return unit*radius
    }

    static func frame(shape: SIMD4<Float>,aspect: Double) -> SIMD4<Float> {
        let kind = Int(shape.x)
        var low = SIMD2<Double>(repeating: -1), high = SIMD2<Double>(repeating: 1)
        if kind == 9 {
            return SIMD4(Float(aspect/1.12),Float(min(1,aspect)),0,0)
        } else if kind == 12 {
            high = SIMD2(1,1.05); low = -high
        } else if kind == 13 {
            high = SIMD2(repeating: 1.12); low = -high
        } else if kind == 5 {
            let c = abs(cos(Double(shape.w))), s = abs(sin(Double(shape.w)))
            let h = Double(shape.z)*(1+abs(Double(shape.y)))
            high = SIMD2(c+h*s,s+h*c); low = -high
        } else if kind == 1 || kind == 2 || kind == 3 {
            low = SIMD2(repeating: Double.infinity); high = -low
            let count = Int(shape.y)*(kind == 1 ? 2 : 1)
            for index in 0..<count {
                let angle = Double(shape.w)+Double(index)*2 * .pi/Double(count)
                let radius = kind == 1 && index & 1 != 0 ? Double(shape.z) : 1
                let p = SIMD2(cos(angle),sin(angle))*radius
                low = simd_min(low,p); high = simd_max(high,p)
            }
        }
        let centre = (low+high)*0.5, extent = (high-low)*0.5
        var scale: SIMD2<Double>
        if kind == 3 || kind == 4 {
            let ratio = max(1.25,max(aspect,1/aspect)*Double(shape.z))
            let target = aspect >= 1 ? SIMD2(min(aspect,ratio),min(1,aspect/ratio)) : SIMD2(min(aspect,1/ratio),min(1,aspect*ratio))
            scale = target/extent
        } else {
            scale = SIMD2(repeating: min(aspect/extent.x,1/extent.y))
        }
        let shift = -centre*scale
        return SIMD4(Float(scale.x),Float(scale.y),Float(shift.x),Float(shift.y))
    }

    /// Conservative bounds of the whole ornament after rotation. Size follows
    /// the current profiles, leaving room for the outside strands as they grow.
    static func bounds(shape: SIMD4<Float>,frame: SIMD4<Float>,rotation: Double,radius: Double,phase: Double = 0) -> (low: SIMD2<Double>,high: SIMD2<Double>) {
        let c = cos(rotation), s = sin(rotation)
        func rotate(_ p: SIMD2<Double>) -> SIMD2<Double> { SIMD2(p.x*c-p.y*s,p.x*s+p.y*c) }
        let shift = rotate(SIMD2(Double(frame.z),Double(frame.w)))
        if shape.x == 13 {
            // Bound the spiral with 24 chords. A 0.03 pad encloses their
            // curvature (max |p''| / (8 * 24²)); the other pads cover
            // harmonic drift and the widest spread of the filaments.
            let scale = SIMD2(Double(frame.x),Double(frame.y))
            let start = Double(shape.w)+0.32*sin(phase)
            let sweep = 2 * Double.pi*Double(shape.y), inner = Double(shape.z)
            var low = SIMD2<Double>(repeating: .infinity), high = -low
            for i in 0...24 {
                let f = Double(i)/24, a = start+sweep*f, r = inner+(1-inner)*f
                let p = rotate(SIMD2(cos(a),sin(a))*r*scale)
                low = simd_min(low,p); high = simd_max(high,p)
            }
            let margin = abs(rotate(SIMD2(0,0.17)*scale)) + SIMD2(repeating: 0.14*max(scale.x,scale.y))
            return (low+shift-margin,high+shift+margin)
        }
        if shape.x == 0 || shape.x == 4 || shape.x == 6 || shape.x == 10 || shape.x == 11 {
            // Orthogonal projection cannot enlarge the torus enclosing
            // sphere.
            let envelope = shape.x == 11 ? radius*(0.68+Double(shape.z)) : radius
            let x = Double(frame.x)*envelope, y = Double(frame.y)*envelope
            let extent = SIMD2(sqrt(x*x*c*c+y*y*s*s),sqrt(x*x*s*s+y*y*c*c))
            return (shift-extent,shift+extent)
        }
        if shape.x == 8 {
            // The astroid lies inside the diamond joining its four tips.
            let x = Double(frame.x)*radius, y = Double(frame.y)*radius
            let extent = SIMD2(max(abs(x*c),abs(y*s)),max(abs(x*s),abs(y*c)))
            return (shift-extent,shift+extent)
        }
        if shape.x == 5 {
            let angle = Double(shape.w), h = Double(shape.z)*(1+abs(Double(shape.y)))
            let scale = SIMD2(Double(frame.x),Double(frame.y))*radius
            let a = rotate(SIMD2(cos(angle),sin(angle))*scale)
            let b = rotate(SIMD2(-sin(angle),cos(angle))*scale*h)
            // cos²(phi)+sin²(2phi) <= 25/16. Intersect this enclosing
            // ellipse with the axis box to avoid wasting the figure's area.
            let squared: SIMD2<Double> = a*a+b*b
            let ellipse = SIMD2(sqrt(squared.x),sqrt(squared.y))*1.25
            let extent = simd_min(abs(a)+abs(b),ellipse)
            return (shift-extent,shift+extent)
        }
        var low = SIMD2<Double>(repeating: .infinity), high = -low
        if shape.x == 7 || shape.x >= 9 {
            let extent: SIMD2<Double>
            switch Int(shape.x) {
            case 9: extent = SIMD2(1.12,0.68)/radius
            case 12: extent = SIMD2(1,1.05)
            default: extent = SIMD2(repeating: 1)
            }
            for x in [-1.0,1.0] { for y in [-1.0,1.0] {
                let p = rotate(SIMD2(x*extent.x*radius*Double(frame.x),y*extent.y*radius*Double(frame.y)))+shift
                low = simd_min(low,p); high = simd_max(high,p)
            } }
            return (low,high)
        }
        let count = Int(shape.y)*(shape.x == 1 ? 2 : 1)
        for index in 0..<count {
            let a = Double(shape.w)+Double(index)*2 * .pi/Double(count)
            let r = radius*(shape.x == 1 && (index & 1) != 0 ? Double(shape.z) : 1)
            let p = rotate(SIMD2(cos(a)*r*Double(frame.x),sin(a)*r*Double(frame.y)))+shift
            low = simd_min(low,p); high = simd_max(high,p)
        }
        return (low,high)
    }

    func uniforms(time: Double, delta: Double, width: Int, height: Int,
                  settings: AtlasSettings, shapeTime: Double? = nil) -> AtlasUniforms {
        let aspect = Float(width) / Float(max(1, height))
        let t = max(0,time)
        let offset = Double(Self.hash(seed) % 4096)/4096 * 2 * .pi
        func angle(_ value: Double) -> Float { Float(value.truncatingRemainder(dividingBy: 2 * .pi)) }
        let transition = Self.transition(time: shapeTime ?? t)
        let source = descriptor(node: transition.node), target = descriptor(node: transition.node+1)
        // Rotation can rest independently while the ornament keeps moving.
        let rotation = Double(angle(self.rotation(time: t).angle))
        let ornament = t*0.14+0.20*sin(t*0.16)+0.10*sin(t/71)+offset
        func wave(_ rate: Double,_ channel: UInt64) -> Double { 0.5+0.5*sin(t*rate+unit(0,channel)*2 * .pi) }
        let orbit = excursion(time: t)
        let motif = motifTransition(time: t)
        let coefficients = SIMD3(0.15+0.85*wave(sqrt(3)/37,0xb1),
                                 0.08+0.72*wave(sqrt(5)/59,0xb2),
                                 0.04+0.52*wave(sqrt(7)/89,0xb3))
        // Favor a clear leading harmonic while allowing the lead to move
        // continuously between components. Avoid permanent six-way clutter.
        let powers = coefficients*coefficients*coefficients
        let weights = powers/(powers.x+powers.y+powers.z)
        let weave = SIMD4(Float(Self.strandCount),Float(0.07+0.06*wave(sqrt(2)/41,0xc1)),
                          Float(0.16+0.14*wave(sqrt(3)/73,0xc2)),Float(0.65+0.75*wave(sqrt(13)/113,0xc3)))
        let detail = SIMD4(angle(-t*sqrt(3)*0.067+0.24*sin(t*sqrt(11)/173)+offset),
                           Float(0.90+0.075*wave(sqrt(11)/71,0xc4)),
                           Float(0.10+0.28*wave(sqrt(17)/137,0xc5)),Float(0.65+0.8*wave(sqrt(19)/197,0xc6)))
        let sourceFrame = Self.frame(shape: source,aspect: Double(aspect))
        let targetFrame = Self.frame(shape: target,aspect: Double(aspect))
        // The soft radial projection stays below 1.4. A constant reserve
        // prevents the entire main shape from breathing with the ornament.
        let curvePhase = angle(t*0.035+offset)
        let a = Self.bounds(shape: source,frame: sourceFrame,rotation: rotation,radius: 1.4,phase: Double(curvePhase))
        let b = Self.bounds(shape: target,frame: targetFrame,rotation: rotation,radius: 1.4,phase: Double(curvePhase))
        let low = a.low*(1-transition.blend)+b.low*transition.blend
        let high = a.high*(1-transition.blend)+b.high*transition.blend
        let extent = simd_max(abs(low),abs(high))
        let fit = 0.93*min(Double(aspect)/extent.x,1/extent.y)
        return AtlasUniforms(
            viewport: SIMD4(Float(width), Float(height), aspect, Float(delta)),
            style: SIMD4(Float(settings.lineWidth), Float(settings.trail), Float(settings.speed), Float(settings.density)),
            phase: SIMD4(angle(ornament),Float(0.8+0.7*sin(t*sqrt(7)/53+offset)+0.3*sin(t*sqrt(11)/173)),
                         angle(t*sqrt(2)*0.091+0.17*sin(t*sqrt(7)/211)+offset),curvePhase),
            sourceShape: source,targetShape: target,
            sourceFrame: sourceFrame,targetFrame: targetFrame,
            morph: SIMD4(Float(transition.blend),0,0,0),
            weave: weave,
            harmonicsA: harmonics(node: motif.node),harmonicsB: harmonics(node: motif.node+1),
            weights: SIMD4(Float(weights.x),Float(weights.y),Float(weights.z),Float(motif.blend)),
            detail: detail,
            orbit: orbit,
            layout: SIMD4(Float(fit),Float(rotation),0,0),
            tint: SIMD4(angle(t*0.025+offset)/(2 * .pi),Float(settings.luminosity),Float(settings.glow),0))
    }

    /// CPU reference for closure, correspondence and temporal-continuity checks.
    static func point(_ full: Double,layer: Int,uniforms u: AtlasUniforms) -> SIMD2<Double> {
        let blend = Double(u.morph.x)
        let openness = (isOpen(u.sourceShape) ? 1-blend : 0)+(isOpen(u.targetShape) ? blend : 0)
        // Every strand traverses a shorter arc as the seam opens. The
        // open profiles use the original parameter and never wrap it.
        let phi = Double.pi+(full-Double.pi)*(1-0.18*openness)
        let q = layer == 0 ? 0 : Double(layer-1)/Double(strandCount-2)
        let outside = Self.excursionWeight(q,orbit: u.orbit)
        let influence = layer == 0 ? 0 : Double(u.weave.y)+Double(u.weave.z)*pow(q,Double(u.detail.w))
        let scale = layer == 0 ? 1 : Double(u.detail.y)-(Double(u.detail.y)-Double(u.detail.z))*pow(q,Double(u.weave.w))
        func harmonic(_ frequencies: SIMD4<Float>) -> SIMD2<Double> {
            let phases = [u.phase.x,u.phase.z,u.detail.x]
            var p = SIMD2<Double>(repeating: 0)
            for j in 0..<3 {
                let k = Double(frequencies[j]), phase = Double(phases[j])
                let twist = q*Double(u.phase.y)*(1+0.4*Double(j))+sin(q * .pi)*0.25*sin(Double(u.detail.x)+Double(j) * .pi/3)
                // Advance each component by its fundamental order. Higher
                // windings add detail without tripling the trail velocity.
                let phaseOrder = Double(frequencies.w)*(k>1 ? 1 : -1)
                let a = k*phi+phaseOrder*(phase+twist)
                p += SIMD2(cos(a),sin(a))*Double(u.weights[j])
            }
            return p
        }
        let z: SIMD2<Double>
        if layer == 0 { z = SIMD2(cos(phi),sin(phi)) }
        else {
            let secondary = harmonic(u.harmonicsA)*(1-Double(u.weights.w))+harmonic(u.harmonicsB)*Double(u.weights.w)
            z = SIMD2(cos(phi),sin(phi))*(1-influence)+secondary*influence
        }
        func mapped(_ shape: SIMD4<Float>,_ frame: SIMD4<Float>) -> SIMD2<Double> {
            let length = simd_length(z)
            let exterior = 1.07+0.20*q+0.90*length
            let radial = layer == 0 ? length : length*scale*(1-outside)+exterior*outside
            let raw: SIMD2<Double>
            if isOpen(shape) {
                let s = full / .pi - 1, phase = Double(u.phase.w)
                let drift = (z-SIMD2(cos(phi),sin(phi)))*0.12
                let spread = layer == 0 ? 0 : (q-0.5)*(0.15+0.19*outside)
                if shape.x == 9 {
                    raw = SIMD2(s,Double(shape.z)*sin(.pi*s)+0.10*sin(2 * .pi*s-phase)+spread)+drift
                } else {
                    let f = (s+1)*0.5, r = Double(shape.z)+(1-Double(shape.z))*f
                    let angle = full*Double(shape.y)+Double(shape.w)+0.32*sin(phase)
                    raw = SIMD2(r*cos(angle),r*sin(angle)+spread)+drift
                }
            } else {
                raw = outline(atan2(z.y,z.x),shape: shape,tiltPhase: Double(u.phase.w))*Self.projectedRadius(radial)
            }
            return raw*SIMD2(Double(frame.x),Double(frame.y))+SIMD2(Double(frame.z),Double(frame.w))
        }
        let a = mapped(u.sourceShape,u.sourceFrame), b = mapped(u.targetShape,u.targetFrame)
        let p = a*(1-Double(u.morph.x))+b*Double(u.morph.x)
        let rotation = Double(u.layout.y)
        return SIMD2(p.x*cos(rotation)-p.y*sin(rotation),p.x*sin(rotation)+p.y*cos(rotation))*Double(u.layout.x)
    }
}

/// Kept in float4 units to match Metal alignment exactly.
struct AtlasUniforms {
    var viewport: SIMD4<Float>
    var style: SIMD4<Float>
    var phase: SIMD4<Float>
    var sourceShape: SIMD4<Float>
    var targetShape: SIMD4<Float>
    var sourceFrame: SIMD4<Float>
    var targetFrame: SIMD4<Float>
    var morph: SIMD4<Float>
    var weave: SIMD4<Float>
    var harmonicsA: SIMD4<Float>
    var harmonicsB: SIMD4<Float>
    var weights: SIMD4<Float>
    var detail: SIMD4<Float>
    var orbit: SIMD4<Float>
    var layout: SIMD4<Float>
    var tint: SIMD4<Float>
    var clock: SIMD4<Float> = .zero
    var clockDigits: SIMD4<UInt32> = .zero
}

struct AtlasClockSettings: Codable, Equatable {
    static let delayRange = 30.0...1800.0
    static let durationRange = 8.0...90.0

    var earliest = 300.0
    var latest = 440.0
    var duration = 15.0
    var enabled = true

    var validated: Self {
        func bounded(_ value: Double,_ range: ClosedRange<Double>,_ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : fallback
        }
        let first = bounded(earliest,Self.delayRange,300)
        return Self(earliest: first,latest: max(first,bounded(latest,Self.delayRange,440)),
                    duration: bounded(duration,Self.durationRange,15),enabled: enabled)
    }
}

struct AtlasSettings: Codable {
    static let defaultSpeed = 6.0
    // Keep stored/rendered speed in the original clock units so existing
    // journeys retain their tempo. The control uses a smooth 1...10 scale.
    static let speedRange = 6.0...24.0
    static let speedControlRange = 1.0...10.0

    static func speed(forControl value: Double) -> Double {
        let x = value.isFinite ? min(10, max(1, value)) : 1
        return 0.1*x*x + 0.9*x + 5
    }

    var speedControlValue: Double {
        let value = speed.isFinite ? min(24, max(6, speed)) : Self.defaultSpeed
        return (-0.9 + sqrt(0.81 + 0.4*(value-5)))/0.2
    }
    static let defaultShapeDuration = 8.0
    static let shapeDurationRange = 3.0...40.0

    var speed: Double = AtlasSettings.defaultSpeed
    var shapeDuration: Double = AtlasSettings.defaultShapeDuration
    var trail: Double = 0.55
    var density: Int = 96
    var lineWidth: Double = 0.6
    var glow: Double = 0.55
    var luminosity: Double = 1.35
    var clock = AtlasClockSettings()

    static let defaults = UserDefaults(suiteName: "cz.coolajz.ScreenSaver.Atlas")!

    static func load() -> Self {
        defaults.synchronize()
        guard let data = defaults.data(forKey: "geometricAppearance"),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return decoded.validated
    }

    var validated: Self {
        var result = self
        result.clock = clock.validated
        result.speed = speed.isFinite ? min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, speed)) : Self.defaultSpeed
        result.shapeDuration = shapeDuration.isFinite ? min(Self.shapeDurationRange.upperBound, max(Self.shapeDurationRange.lowerBound, shapeDuration)) : Self.defaultShapeDuration
        result.trail = trail.isFinite ? min(3, max(0.15, trail)) : 0.55
        result.density = min(288, max(48, density)) / 4 * 4
        result.lineWidth = lineWidth.isFinite ? min(1.2, max(0.4, lineWidth)) : 0.7
        result.glow = glow.isFinite ? min(1, max(0, glow)) : 0.55
        result.luminosity = luminosity.isFinite ? min(2.5, max(0.35, luminosity)) : 1.35
        return result
    }

    func save() {
        if let data = try? JSONEncoder().encode(validated) { Self.defaults.set(data, forKey: "geometricAppearance") }
    }
}

extension AtlasSettings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        speed = try values.decodeIfPresent(Double.self,forKey: .speed) ?? Self.defaultSpeed
        shapeDuration = try values.decodeIfPresent(Double.self,forKey: .shapeDuration) ?? Self.defaultShapeDuration
        trail = try values.decodeIfPresent(Double.self,forKey: .trail) ?? 0.55
        density = try values.decodeIfPresent(Int.self,forKey: .density) ?? 96
        lineWidth = try values.decodeIfPresent(Double.self,forKey: .lineWidth) ?? 0.6
        clock = try values.decodeIfPresent(AtlasClockSettings.self,forKey: .clock) ?? AtlasClockSettings()
        let savedLight = try values.decodeIfPresent(Double.self,forKey: .luminosity)
        luminosity = savedLight ?? 1.35
        if let savedGlow = try values.decodeIfPresent(Double.self,forKey: .glow) {
            // The old slider's full travel was 0...0.35. Preserve its position
            // on the new 0...1 range without resetting the remaining settings.
            glow = savedLight == nil ? savedGlow/0.35 : savedGlow
        } else { glow = 0.55 }
    }
}
