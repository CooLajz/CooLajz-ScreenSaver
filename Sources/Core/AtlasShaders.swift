import Foundation

enum AtlasShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms {
        float4 viewport, style, phase, sourceShape, targetShape, sourceFrame, targetFrame, morph, weave, harmonicsA, harmonicsB, weights, detail, orbit, layout, tint;
        float4 clock;
        uint4 clockDigits;
    };
    struct Segment { float4 endpoints; float4 appearance; };
    constant float2 snowflakeArm[] = {\(AtlasField.snowflakeArm.map { "float2(\($0.x),\($0.y))" }.joined(separator: ","))};
    float2 rotate(float2 p,float angle) {
        return float2(p.x*cos(angle)-p.y*sin(angle),p.x*sin(angle)+p.y*cos(angle));
    }
    bool isOpen(float4 shape) { return shape.x == 9 || shape.x == 13; }
    float2 outline(float angle,float4 shape,float tiltPhase) {
        int kind = int(shape.x);
        float2 unit = float2(cos(angle),sin(angle));
        if (kind == 5) {
            float2 p = float2(unit.x,shape.z*sin(2*angle)*(1+shape.y*unit.x));
            return float2(p.x*cos(shape.w)-p.y*sin(shape.w),p.x*sin(shape.w)+p.y*cos(shape.w));
        }
        if (kind == 10) {
            constexpr uint count = \(AtlasField.snowflakeArm.count-1);
            float ring = fract(angle/6.28318530718)*6;
            uint sector = min(5u,uint(ring));
            float along = (ring-float(sector))*float(count);
            uint edge = min(count-1,uint(along));
            float2 p = mix(snowflakeArm[edge],snowflakeArm[edge+1],along-float(edge));
            p.y *= 1-(1-shape.z)*clamp((p.x-0.10)*4,0.0,1.0);
            return rotate(p,float(sector)*1.0471975512+shape.w);
        }
        if (kind == 11) {
            float a = angle*shape.y, b = 2*angle;
            float r = 0.68+shape.z*cos(a), tilt = 0.54+0.48*sin(tiltPhase+shape.w);
            return float2(r*cos(b),r*sin(b)*cos(tilt)+shape.z*sin(a)*sin(tilt));
        }
        if (kind == 12) {
            float y = (13*unit.x-5*cos(2*angle)-2*cos(3*angle)-cos(4*angle)+2)/16;
            return float2(-unit.y*unit.y*unit.y*shape.z,y);
        }
        float radius = 1;
        if (kind == 6) {
            radius = 1-shape.z+shape.z*cos(shape.y*(angle-shape.w));
        } else if (kind == 7) {
            radius = pow(pow(abs(unit.x),shape.z)+pow(abs(unit.y),shape.z),-1.0/shape.z);
        } else if (kind == 8) {
            radius = pow(pow(abs(unit.x),2.0/3.0)+pow(abs(unit.y),2.0/3.0),-1.5);
        } else if (kind == 1 || kind == 2 || kind == 3) {
            bool star = kind == 1;
            int count = int(shape.y)*(star ? 2 : 1);
            float step = 6.28318530718/float(count);
            float position = (angle-shape.w)/step;
            int edge = int(floor(position));
            float delta = fract(position)*step;
            float a = star && ((edge&1) != 0) ? shape.z : 1.0;
            float b = star && ((edge&1) == 0) ? shape.z : 1.0;
            radius = a*b*sin(step)/max(0.0001,b*sin(step-delta)+a*sin(delta));
        }
        return unit*radius;
    }
    float2 harmonicField(float phi,float q,float4 frequencies,constant Uniforms &u) {
        float3 phases = float3(u.phase.x,u.phase.z,u.detail.x);
        float2 p = 0;
        for (uint j=0; j<3; ++j) {
            float k = frequencies[j];
            float twist = q*u.phase.y*(1.0+0.4*float(j))+sin(q*3.14159265359)*0.25*sin(u.detail.x+float(j)*1.0471975512);
            float phaseOrder = frequencies.w*(k>1 ? 1.0 : -1.0);
            float a = k*phi+phaseOrder*(phases[j]+twist);
            p += float2(cos(a),sin(a))*u.weights[j];
        }
        return p;
    }
    float2 mappedFilament(float2 z,float2 base,float full,float q,float scale,float excursion,
                          uint layer,float4 shape,float4 frame,float phase) {
        if (isOpen(shape)) {
            float s = full/3.14159265359-1;
            float2 drift = (z-base)*0.12;
            float spread = layer == 0 ? 0 : (q-0.5)*(0.15+0.19*excursion);
            float2 raw;
            if (shape.x == 9) {
                raw = float2(s,shape.z*sin(3.14159265359*s)+0.10*sin(6.28318530718*s-phase)+spread);
            } else {
                float r = mix(shape.z,1.0,(s+1)*0.5);
                float angle = full*shape.y+shape.w+0.32*sin(phase);
                raw = float2(r*cos(angle),r*sin(angle)+spread);
            }
            return (raw+drift)*frame.xy+frame.zw;
        }
        float r = length(z);
        float exterior = 1.07+0.20*q+0.90*r;
        float radius = mix(r*scale,exterior,excursion);
        float excess = max(0.0,radius-1.0);
        radius = radius<=1.0 ? radius : 1.0+excess*rsqrt(1.0+excess*excess/0.16);
        float2 raw = outline(atan2(z.y,z.x),shape,phase)*radius;
        return raw*frame.xy+frame.zw;
    }
    float2 figure(float full,uint layer,constant Uniforms &u) {
        float openness = (isOpen(u.sourceShape) ? 1-u.morph.x : 0)+(isOpen(u.targetShape) ? u.morph.x : 0);
        float phi = mix(full,3.14159265359,0.18*openness);
        float q = layer == 0 ? 0.0 : float(layer-1u)/(u.weave.x-2.0);
        float influence = layer == 0 ? 0.0 : u.weave.y+u.weave.z*pow(q,u.detail.w);
        float scale = layer == 0 ? 1.0 : u.detail.y-(u.detail.y-u.detail.z)*pow(q,u.weave.w);
        float excursion = layer == 0 ? 0.0 : clamp(u.orbit.x+u.orbit.y*(2*q-1)+u.orbit.z*sin(q*3.14159265359),0.0,1.0);
        excursion = excursion*excursion*excursion*(excursion*(excursion*6-15)+10);
        float2 base = float2(cos(phi),sin(phi));
        float2 z = base;
        if (layer != 0) {
            float2 secondary = mix(harmonicField(phi,q,u.harmonicsA,u),harmonicField(phi,q,u.harmonicsB,u),u.weights.w);
            z = z*(1-influence)+secondary*influence;
        }
        float2 a = mappedFilament(z,base,full,q,scale,excursion,layer,u.sourceShape,u.sourceFrame,u.phase.w);
        float2 b = mappedFilament(z,base,full,q,scale,excursion,layer,u.targetShape,u.targetFrame,u.phase.w);
        return rotate(mix(a,b,u.morph.x),u.layout.y)*u.layout.x;
    }
    // Seven fine strokes per digit. The mask leaves a fixed place for
    // every stroke, so digits changing at the minute never reorder segments.
    constant uint digitMasks[] = {63,6,91,79,102,109,125,7,127,111};
    constant float4 clockStrokes[] = {
        float4(-.235,.46,.235,.46), float4(.275,.41,.275,.05),
        float4(.275,-.05,.275,-.41), float4(.235,-.46,-.235,-.46),
        float4(-.275,-.41,-.275,-.05), float4(-.275,.05,-.275,.41),
        float4(-.235,0,.235,0)
    };
    struct ClockStroke { float2 a,b; float visible; };
    ClockStroke clockStroke(uint slot,constant Uniforms &u) {
        bool date = slot >= 30;
        uint local = date ? slot-30 : slot;
        uint count = date ? 8 : 4;
        float2 a,b;
        float visibility = 1;
        float row = date ? -.54 : (u.clock.y > .5 ? .30 : 0.0);
        float scale = date ? .47 : 1.0;
        if (local >= count*7) {
            bool second = local != count*7;
            float x = date ? (second ? .08 : -1.50) : 0.0;
            float y = date ? -.40 : (second ? -.17 : .17);
            a = float2(x-.026,y); b = float2(x+.026,y+.02);
        } else {
            uint digit = local/7, edge = local%7;
            uint shift = 4*(count-1-digit);
            uint old = ((date ? u.clockDigits.y : u.clockDigits.x)>>shift)&15;
            uint next = ((date ? u.clockDigits.w : u.clockDigits.z)>>shift)&15;
            float x = date ? (float(digit)-3.5)*.71+(digit>=2 ? .16 : 0)+(digit>=4 ? .16 : 0)-.16
                           : (float(digit)-1.5)*.73+(digit>=2 ? .13 : -.13);
            float4 ends = clockStrokes[edge]+float4(x,0,x,0);
            a = ends.xy; b = ends.zw;
            visibility = mix(float((digitMasks[old]>>edge)&1),float((digitMasks[next]>>edge)&1),u.clock.z);
        }
        return {a*scale+float2(0,row),b*scale+float2(0,row),visibility};
    }
    float2 clockPoint(ClockStroke stroke,float t,uint slot,uint layer,float q,constant Uniforms &u) {
        float2 p = mix(stroke.a,stroke.b,t);
        if (layer != 0) {
            float2 direction = normalize(stroke.b-stroke.a);
            float2 normal = float2(-direction.y,direction.x);
            float phase = u.phase.x+float(slot)*0.69+q*4.6;
            float bow = sin(t*3.14159265);
            p += normal*(.044*(q-.5)+.020*bow*sin(phase+t*6.2831853));
            p += direction*.012*sin(u.phase.z+q*6.0+t*3.14159265);
        }
        // The composition travels and breathes, but both baselines stay level.
        float phase = u.clock.w;
        float scale = min(.92,.46*u.viewport.z)*(1+.10*sin(phase*2-.7));
        float2 travel = float2(.105*u.viewport.z*sin(phase),.12*sin(phase*2+.8));
        return (p*scale+travel)*float2(1,-1);
    }
    kernel void advance(device Segment *segments [[buffer(0)]],
                        constant Uniforms &u [[buffer(1)]], uint i [[thread_position_in_grid]]) {
        uint count = uint(u.style.w)*8u;
        if (i >= count*uint(u.weave.x)) return;
        uint layer = i/count, sample = i%count;
        float phi = float(sample)/float(count)*6.28318530718;
        float next = float(sample+1u)/float(count)*6.28318530718;
        float2 before = figure(phi,layer,u);
        float2 after = figure(next,layer,u);
        float q = layer == 0 ? 0.0 : float(layer-1u)/(u.weave.x-2.0);
        float hue = fract(float(sample)/float(count)+u.tint.x+q*0.08);
        // Two broad, slowly travelling light accents add depth to the same
        // geometry. Their phases remain shared and continuous across the curve.
        float accent = pow(0.5+0.5*cos(phi*2.0-u.phase.w*4.0),8.0);
        float energy = layer == 0 ? 0.11 : 0.25/(u.weave.x-1.0);
        // A densely folded dendrite accumulates more overlapping trails.
        float snow = mix(u.sourceShape.x == 10 ? 1.0 : 0.0,u.targetShape.x == 10 ? 1.0 : 0.0,u.morph.x);
        energy *= mix(1.0,layer == 0 ? 0.72 : 0.50,snow);
        if (u.clock.x > 0) {
            // At zero blend these are the original contiguous segments.
            // As the clock forms, each group pulls toward one distinct stroke.
            uint slots = u.clock.y > .5 ? 88u : 30u;
            uint slot = sample*slots/count;
            uint start = (slot*count+slots-1u)/slots;
            uint end = ((slot+1u)*count+slots-1u)/slots;
            float local = float(sample-start)/float(end-start);
            float following = float(sample+1u-start)/float(end-start);
            ClockStroke stroke = clockStroke(slot,u);
            before = mix(before,clockPoint(stroke,local,slot,layer,q,u),u.clock.x);
            after = mix(after,clockPoint(stroke,following,slot,layer,q,u),u.clock.x);
            float clockEnergy = layer == 0 ? .17 : .22/(u.weave.x-1);
            // Luminous packets travel along neighboring filaments at
            // slightly different phases without moving or widening them.
            float phase = u.clock.w;
            float charge = pow(.5+.5*cos(phase*10-float(slot)*.47-local*6.2831853-q*1.8),4.0);
            float spark = pow(.5+.5*cos(phase*23+float(slot)*1.37-local*12.566371-q*4.1),7.0);
            float pulse = .73+.51*charge+.26*spark;
            energy = mix(energy,clockEnergy*stroke.visible*pulse,u.clock.x);
            accent = mix(accent,max(accent,.84*charge+.16*spark),u.clock.x);
        }
        segments[i] = Segment{float4(before,after),float4(hue,energy,accent,0)};
    }

    struct FullOut { float4 position [[position]]; float2 uv; };
    vertex FullOut fullVertex(uint i [[vertex_id]]) {
        float2 p = float2(float((i << 1) & 2),float(i & 2));
        return {float4(p*float2(2,-2)+float2(-1,1),0,1),p};
    }
    fragment float4 fadeFragment(FullOut in [[stage_in]], texture2d<float> history [[texture(0)]],
                                 constant Uniforms &u [[buffer(0)]]) {
        constexpr sampler s(filter::nearest);
        float3 old = history.sample(s,in.uv).rgb;
        float trail = mix(u.style.y,min(u.style.y,.25),u.clock.x);
        return float4(old * exp(-u.viewport.w/trail),1);
    }
    fragment float4 bloomExtract(FullOut in [[stage_in]], texture2d<float> history [[texture(0)]]) {
        constexpr sampler s(filter::linear,address::clamp_to_edge);
        float2 pixel = 1.0/float2(history.get_width(),history.get_height());
        float3 light = 0;
        for (int y=-1; y<=1; y+=2) { for (int x=-1; x<=1; x+=2) {
            float3 sample = history.sample(s,in.uv+float2(x,y)*pixel).rgb;
            float peak = max(sample.r,max(sample.g,sample.b));
            // Extract before averaging so thin luminous lines survive the
            // downsample while the weakest old trails do not turn into fog.
            light += sample * max(peak-0.11,0.0)/max(peak,0.0001);
        } }
        return float4(light*0.25,1);
    }
    fragment float4 bloomBlur(FullOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                               constant float2 &step [[buffer(0)]]) {
        constexpr sampler s(filter::linear,address::clamp_to_edge);
        const float weights[] = {0.22702703,0.19459459,0.12162162,0.05405405,0.01621622};
        float3 sum = source.sample(s,in.uv).rgb*weights[0];
        for (int i=1; i<5; ++i) {
            sum += (source.sample(s,in.uv+step*float(i)).rgb
                  + source.sample(s,in.uv-step*float(i)).rgb)*weights[i];
        }
        return float4(sum,1);
    }
    float3 toneMap(float3 light) {
        // Compress the peak once for all three channels so bright colors retain
        // their ratios instead of independently clipping toward white.
        float peak = max(light.r,max(light.g,light.b));
        float mapped = clamp((peak*(2.51*peak+0.03))/(peak*(2.43*peak+0.59)+0.14),0.0,1.0);
        return light*(mapped/max(peak,0.0001));
    }
    float3 linearToSRGB(float3 color) {
        return select(1.055*pow(color,float3(1.0/2.4))-0.055,
                      color*12.92,color<=0.0031308);
    }
    fragment float4 displayFragment(FullOut in [[stage_in]], texture2d<float> history [[texture(0)]],
                                      texture2d<float> nearLight [[texture(1)]],
                                      texture2d<float> farLight [[texture(2)]],
                                      constant Uniforms &u [[buffer(0)]]) {
        constexpr sampler s(filter::linear,address::clamp_to_edge);
        float3 light = history.sample(s,in.uv).rgb;
        light += u.tint.z*(nearLight.sample(s,in.uv).rgb*1.8+farLight.sample(s,in.uv).rgb*0.55);
        // All accumulation and bloom use linear floating-point light. Encode
        // for the sRGB display only after exposure and highlight compression.
        return float4(linearToSRGB(toneMap(light*u.tint.y)),1);
    }

    struct LineOut {
        float4 position [[position]];
        float2 local;
        float length [[flat]];
        float4 appearance [[flat]];
    };
    vertex LineOut lineVertex(uint v [[vertex_id]], uint i [[instance_id]],
                               device const Segment *segments [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]]) {
        const float2 corners[] = {float2(0,-1),float2(1,-1),float2(0,1),
                                  float2(0,1),float2(1,-1),float2(1,1)};
        Segment s = segments[i];
        float2 scale = float2(u.viewport.y*0.5);
        float2 a = s.endpoints.xy*scale + u.viewport.xy*0.5;
        float2 b = s.endpoints.zw*scale + u.viewport.xy*0.5;
        float2 d = b-a;
        float len = max(length(d),0.001);
        float2 direction = d/len;
        float2 normal = float2(-direction.y,direction.x);
        float extent = max(1.5,u.style.x*2.0);
        float2 c = corners[v];
        float longitudinal = mix(-extent,len+extent,c.x);
        float2 pixel = a + direction*longitudinal + normal*c.y*extent;
        return {float4(pixel/u.viewport.xy*float2(2,-2)+float2(-1,1),0,1),
                float2(longitudinal,c.y*extent),len,s.appearance};
    }
    float3 rainbow(float hue) {
        float3 rgb = clamp(abs(fract(hue+float3(0,2.0/3.0,1.0/3.0))*6.0-3.0)-1.0,0.0,1.0);
        return mix(float3(0.16),rgb,0.84);
    }
    fragment float4 lineFragment(LineOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float distance = abs(in.local.y);
        float radius = u.style.x*0.5;
        float core = 1-smoothstep(max(0.0,radius-0.55),radius+0.55,distance);
        float hotRadius = radius*0.35;
        float hot = 1-smoothstep(max(0.0,hotRadius-0.4),hotRadius+0.4,distance);
        // Adjacent butt-ended segments share a one-pixel coverage ramp. This
        // avoids bright beads at their joins while keeping subpixel lines smooth.
        float along = clamp(min(in.local.x+0.5,in.length-in.local.x+0.5),0.0,1.0);
        float3 color = rainbow(in.appearance.x);
        float3 body = color*core*1.8;
        float3 centre = mix(color,float3(1),0.58)*hot*(0.25+in.appearance.z*0.45);
        return float4((body+centre)*in.appearance.y*along,0);
    }
    """
}
