import SwiftUI
import os

// Design tokens. Colours are OKLCH (source of truth, parsed by scripts/contrast.py and scripts/lint-style.sh),
// drawn in extended linear sRGB: exact on P3 screens, clipped on sRGB screens (the sRGB fallback).
// Foil ramp sampled from refs-foil-1/2 (digital renders), blue pixels only, hue clamped to 228-258 (no purple, clear of the logo colour at hue 183).
enum Tok {
    // One light source and one noise field drive every effect.
    static let lightAngle = -2.2
    static let noiseSeed = 0.37
    // Colour: light, dark
    static let paper = Color.token(.oklch(0.972, 0.010, 240), .oklch(0.170, 0.025, 255))
    static let panel = Color.token(.oklch(0.992, 0.004, 240), .oklch(0.215, 0.025, 255))
    static let ink = Color.token(.oklch(0.255, 0.045, 258), .oklch(0.955, 0.010, 240))
    static let inkMuted = Color.token(.oklch(0.420, 0.035, 255), .oklch(0.800, 0.020, 240))
    static let accent = Color.token(.oklch(0.420, 0.130, 256), .oklch(0.780, 0.100, 245))
    static let foil1 = Color.token(.oklch(0.900, 0.040, 236), .oklch(0.300, 0.050, 240))
    static let foil2 = Color.token(.oklch(0.800, 0.075, 244), .oklch(0.400, 0.080, 246))
    static let foil3 = Color.token(.oklch(0.700, 0.110, 250), .oklch(0.520, 0.110, 250))
    static let foil4 = Color.token(.oklch(0.580, 0.090, 258), .oklch(0.620, 0.100, 256))
    static let glint = Color.token(.oklch(0.840, 0.110, 228), .oklch(0.780, 0.110, 228))
    static let panelOpacity = 0.94
    static let foilStrength = 0.55
    // Glass, noise, grid
    static let refraction = 900.0
    static let gridDensity = 9.0
    static let gridOpacity = 0.22
    static let thinFilm = AngularGradient(colors:[foil1,glint,foil3,foil2,foil1],center:.center)
    static let sheen = LinearGradient(stops:[.init(color:.white.opacity(0.9),location:0),.init(color:.clear,location:0.35)],startPoint:UnitPoint(x:0.5+cos(lightAngle)/2,y:0.5+sin(lightAngle)/2),endPoint:.center)
    // Spacing and radii: DESIGN.md
    enum Space { static let xxs = 4.0, xs = 8.0, sm = 12.0, md = 17.0, lg = 24.0, xl = 32.0, xxl = 48.0, section = 80.0 }
    enum Radius { static let xs = 5.0, sm = 8.0, md = 11.0, lg = 18.0, pill = 9999.0 }
    // Motion: slow, viscous, no overshoot.
    enum Duration { static let quick = 0.24, base = 0.48, slow = 0.9, transition = 1.1, ambient = 5.0 }
    static func viscous(_ duration: Double) -> Animation { .timingCurve(0.3, 0, 0.1, 1, duration:duration) }
    // Type: Bodoni Moda (OFL 1.1), axes read with fontTools: wght 400...900, opsz 6...96.
    enum Face { static let postScript = "BodoniModa-Regular", wght = 0x77676874, opsz = 0x6F70737A, weights = 400.0...900.0, sizes = 6.0...96.0 }
    // Z layers (ZStack order): foil 0, grid 1, metaballs 2, content 10, transition 100.
    static let frameBudget = 16.6
}

// Metaballs: landing (HomeView) only.
enum MetaballTok {
    static let anchors: [(x: Double, y: Double, r: Double)] = [(0.24,-0.15,46),(0.42,0.18,60),(0.58,-0.10,40),(0.74,0.20,52),(0.52,0.0,30)]
    static let drift = 16.0
    static let scrollStretch = 0.14
    static let hoverPull = 0.6
}

extension Color {
    static func oklch(_ l: Double, _ c: Double, _ h: Double) -> Color {
        let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
        let l3 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3), m3 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3), s3 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return Color(.sRGBLinear,red:4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,green:-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,blue:-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
    }
    static func token(_ light: Color, _ dark: Color) -> Color { Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) }) }
    func resolved(_ env: EnvironmentValues) -> Color { Color(resolve(in:env)) }
}

// 3. Glass text zone: near-opaque paper so text never sits on foil, thin-film edge, anisotropic highlight.
extension View {
    func textZone(radius: Double = Tok.Radius.lg) -> some View {
        let shape = RoundedRectangle(cornerRadius:radius,style:.continuous)
        return background(Tok.panel.opacity(Tok.panelOpacity),in:shape).overlay(shape.strokeBorder(Tok.thinFilm.opacity(0.7),lineWidth:1)).overlay(shape.strokeBorder(Tok.sheen,lineWidth:1.5).blendMode(.plusLighter))
    }
}

// 9. Kinetic serif: animates the wght/opsz axes. Fonts are cached per quantised axis value.
enum Serif {
    private static var cache: [String: Font] = [:]
    static func font(size: Double, weight: Double, opsz: Double) -> Font {
        let w = (weight / 10).rounded() * 10, o = opsz.rounded(), s = size.rounded()
        let key = "\(s)-\(w)-\(o)"
        if let font = cache[key] { return font }
        let descriptor = UIFontDescriptor(name:Tok.Face.postScript,size:s).addingAttributes([UIFontDescriptor.AttributeName(rawValue:kCTFontVariationAttribute as String):[Tok.Face.wght:w,Tok.Face.opsz:o]])
        let font = Font(UIFont(descriptor:descriptor,size:s) as CTFont)
        cache[key] = font
        return font
    }
}
struct KineticFont: ViewModifier, Animatable {
    var weight: Double
    var opsz: Double
    let size: Double
    let style: UIFont.TextStyle
    @Environment(\.dynamicTypeSize) private var typeSize
    var animatableData: AnimatablePair<Double, Double> { get { .init(weight,opsz) } set { weight = newValue.first; opsz = newValue.second } }
    func body(content: Content) -> some View {
        let scaled = UIFontMetrics(forTextStyle:style).scaledValue(for:size,compatibleWith:UITraitCollection(preferredContentSizeCategory:UIContentSizeCategory(typeSize)))
        return content.font(Serif.font(size:scaled,weight:weight,opsz:min(opsz,Tok.Face.sizes.upperBound)))
    }
}
struct KineticText: View {
    let text: String
    let size: Double
    let style: UIFont.TextStyle
    var weight = 600.0
    var extrude = false
    var kinetic = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    init(_ text: String, size: Double, style: UIFont.TextStyle, weight: Double = 600, extrude: Bool = false, kinetic: Bool = true) { self.text = text; self.size = size; self.style = style; self.weight = weight; self.extrude = extrude; self.kinetic = kinetic }
    var body: some View {
        let done = settled || reduceMotion || !kinetic
        let font = KineticFont(weight:done ? weight : Tok.Face.weights.lowerBound,opsz:done ? size * 1.6 : Tok.Face.sizes.lowerBound,size:size,style:style)
        Text(text).modifier(font).foregroundStyle(Tok.ink)
            .background(alignment:.topLeading) {
                if extrude { ZStack(alignment:.topLeading) { ForEach(1..<5) { i in Text(text).modifier(font).foregroundStyle(Tok.foil4.opacity(0.32 - Double(i) * 0.06)).offset(x:-cos(Tok.lightAngle) * Double(i) * 0.8,y:-sin(Tok.lightAngle) * Double(i) * 0.8) } }.accessibilityHidden(true) }
            }
            .onAppear { withAnimation(Tok.viscous(Tok.Duration.slow)) { settled = true } }
            .onChange(of:text) { settled = false; Task { withAnimation(Tok.viscous(Tok.Duration.slow)) { settled = true } } }
    }
}

// Button spec: idle / hover (pointer lift) / active (caustics) / disabled / focus (two-tone ring, >= 3:1 on paper and foil).
struct ToodleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration:configuration) }
    struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label.foregroundStyle(Tok.panel)
                .background { ZStack { Capsule().fill(Tok.ink.opacity(enabled ? 1 : 0.4)); if configuration.isPressed || focused { Caustics().clipShape(Capsule()) } } }
                .overlay { if focused { ZStack { Capsule().strokeBorder(Tok.panel,lineWidth:2).padding(-2); Capsule().strokeBorder(Tok.accent,lineWidth:2).padding(-4) } } }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Tok.viscous(Tok.Duration.quick),value:configuration.isPressed)
                .hoverEffect(.lift)
        }
    }
}
extension ButtonStyle where Self == ToodleButtonStyle { static var toodle: ToodleButtonStyle { .init() } }

// 4. Caustics + diffraction edge (active/focused elements only).
struct Caustics: View {
    @Environment(\.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused:reduceMotion)) { context in
            GeometryReader { geo in
                Rectangle().fill(.white).colorEffect(ShaderLibrary.caustics(.float2(geo.size),.float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:600)),.float(Tok.lightAngle),.float(Tok.noiseSeed),.color(Tok.foil1.resolved(env)),.color(Tok.glint.resolved(env)),.color(Tok.foil3.resolved(env)),.color(Tok.foil2.resolved(env))))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

// Quality tiers: p95 of display-link frame intervals over 120 frames. Downgrade when p95 > 1.5x budget
// (more than 5% dropped frames); recover after 5 clean windows (~10 s). Launch arg `-ToodleTier low|medium|high` pins it.
@Observable final class Quality: NSObject {
    enum Tier: Int, Comparable { case low, medium, high; static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue } }
    static let shared = Quality()
    var tier: Tier
    private(set) var p95 = 0.0
    private let pinned: Bool
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var samples: [Double] = []
    @ObservationIgnored private var clean = 0
    @ObservationIgnored private var users = 0
    private let log = Logger(subsystem:"com.toodle.ios",category:"frames")
    override init() {
        let pin = UserDefaults.standard.string(forKey:"ToodleTier").flatMap { ["low":Tier.low,"medium":.medium,"high":.high][$0] }
        tier = pin ?? .high; pinned = pin != nil
        super.init()
    }
    func start() {
        users += 1
        guard link == nil else { return }
        last = 0; samples.removeAll()
        link = CADisplayLink(target:self,selector:#selector(tick)); link?.add(to:.main,forMode:.common)
    }
    func stop() { users = max(0,users - 1); if users == 0 { link?.invalidate(); link = nil } }
    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        samples.append((link.timestamp - last) * 1000)
        guard samples.count >= 120 else { return }
        let sorted = samples.sorted(); samples.removeAll(keepingCapacity:true)
        p95 = sorted[Int(Double(sorted.count) * 0.95)]
        log.info("p95 \(self.p95, format:.fixed(precision:1)) ms tier \(self.tier.rawValue)")
        guard !pinned else { return }
        if p95 > Tok.frameBudget * 1.5, tier > .low { tier = Tier(rawValue:tier.rawValue - 1)!; clean = 0 }
        else if p95 <= Tok.frameBudget * 1.1 { clean += 1; if clean >= 5, tier < .high { tier = Tier(rawValue:tier.rawValue + 1)!; clean = 0 } }
    }
}

// 1 + 2 (+ 6 on landing): foil, perspective dot grid, metaballs. Ambient motion settles after Tok.Duration.ambient (WCAG 2.2.2).
struct Backdrop: View {
    var metaballs = false
    var anchor = CGPoint.zero
    var stageHeight = 0.0
    var scroll = 0.0
    var hover: CGPoint?
    var foil = true
    var grid = true
    var continuous = false
    @Environment(\.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quality = Quality.shared
    @State private var start = Date()
    @State private var settled = false
    var body: some View {
        let animated = !reduceMotion && quality.tier != .low && (continuous || !settled)
        TimelineView(.animation(minimumInterval:quality.tier == .high ? nil : 1.0 / 30,paused:!animated)) { context in
            let t = context.date.timeIntervalSince(start), cap = Tok.Duration.ambient
            let time = !animated && !settled ? 0 : continuous ? t : cap * (1 - pow(max(0,1 - t / cap),2))
            GeometryReader { geo in layers(size:geo.size,time:time) }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        .task(id:animated) {
            guard animated else { return }
            quality.start(); defer { quality.stop() }
            if !continuous { try? await Task.sleep(for:.seconds(Tok.Duration.ambient)); settled = true }
            else { while !Task.isCancelled { try? await Task.sleep(for:.seconds(60)) } }
        }
    }
    @ViewBuilder func layers(size: CGSize, time: Double) -> some View {
        let stack = ZStack {
            if foil { Rectangle().fill(.white).colorEffect(ShaderLibrary.foil(.float2(size),.float(time),.float(Tok.lightAngle),.float(Tok.noiseSeed),.float(Tok.foilStrength),color(Tok.paper),color(Tok.foil1),color(Tok.foil2),color(Tok.foil3),color(Tok.foil4))) }
            else { Rectangle().fill(Tok.paper) }
            if grid { Rectangle().fill(.white).colorEffect(ShaderLibrary.dotGrid(.float2(size),.float(Tok.gridDensity),color(Tok.ink),.float(Tok.gridOpacity))) }
            if metaballs && quality.tier != .high { Rectangle().fill(.white).colorEffect(ShaderLibrary.metaballsFlat(.floatArray(balls(size:size,time:time)),.float(Tok.lightAngle),color(Tok.ink),color(Tok.glint),color(Tok.paper))) }
        }
        if metaballs && quality.tier == .high {
            stack.layerEffect(ShaderLibrary.metaballs(.floatArray(balls(size:size,time:time)),.float(Tok.lightAngle),.float(Tok.refraction),color(Tok.ink),color(Tok.glint),color(Tok.paper)),maxSampleOffset:CGSize(width:40,height:40))
        } else { stack }
    }
    func color(_ token: Color) -> Shader.Argument { .color(token.resolved(env)) }
    func balls(size: CGSize, time: Double) -> [Float] {
        let scale = min(1.3,size.width / 390), center = anchor == .zero ? CGPoint(x:0,y:size.height * 0.28) : anchor
        let amp = continuous ? 1 : max(0,1 - time / Tok.Duration.ambient)
        return MetaballTok.anchors.enumerated().flatMap { i, b -> [Float] in
            var x = b.x * size.width + sin(time * 0.4 + Double(i) * 1.7) * MetaballTok.drift * amp
            var y = center.y + b.y * stageHeight + cos(time * 0.33 + Double(i)) * MetaballTok.drift * 0.7 * amp + scroll * (1 + MetaballTok.scrollStretch * Double(i))
            if i == 1, let hover { x += (hover.x - x) * MetaballTok.hoverPull; y += (hover.y - y) * MetaballTok.hoverPull }
            return [Float(x),Float(y),Float(b.r * scale)]
        }
    }
}

#if DEBUG
// Step 1 risk test harness (debug builds only). Launch with `-ToodleBench foil` or `-ToodleBench metaball`.
struct Bench: View {
    let mode: String
    @State private var quality = Quality.shared
    var body: some View {
        Backdrop(metaballs:mode == "metaball",anchor:CGPoint(x:0,y:400),stageHeight:220,foil:mode != "metaball",grid:false,continuous:true)
            .overlay(alignment:.bottom) { Text("\(mode) · p95 \(quality.p95,specifier:"%.1f") ms · tier \(quality.tier.rawValue)").font(.caption.monospaced()).foregroundStyle(Tok.ink).padding(Tok.Space.xs).textZone(radius:Tok.Radius.sm).padding(Tok.Space.xxl) }
    }
}
#endif
