import SwiftUI
import os

// Design tokens. Colours are OKLCH (source of truth, parsed by scripts/style_check.py).
// PROVISIONAL: sampled from the supplied stylized foil references, not physical raking-light photos.
// Their pink/violet pixels are excluded; the foil ramp stays in the blue hue range 235...254.
enum Tok {
    // One light source and one noise field drive every effect.
    static let lightAngle = -2.2
    static let noiseSeed = 0.37
    // Colour: light, dark
    static let paper = Color.token(.oklch(0.981, 0.006, 252), .oklch(0.170, 0.025, 250))
    static let panel = Color.token(.oklch(0.992, 0.004, 250), .oklch(0.215, 0.025, 250))
    static let ink = Color.token(.oklch(0.255, 0.045, 250), .oklch(0.955, 0.010, 245))
    static let inkMuted = Color.token(.oklch(0.420, 0.035, 250), .oklch(0.800, 0.020, 245))
    static let accent = Color.token(.oklch(0.420, 0.125, 250), .oklch(0.780, 0.090, 245))
    static let quietBlue = Color.token(.oklch(0.910, 0.025, 250), .oklch(0.310, 0.045, 245))
    static let line = Color.token(.oklch(0.810, 0.025, 250), .oklch(0.450, 0.040, 245))
    static let strongBlue = Color.token(.oklch(0.320, 0.110, 250), .oklch(0.860, 0.065, 245))
    static let logoTeal = Color.token(.oklch(0.350, 0.090, 183), .oklch(0.780, 0.100, 183))
    static let foil1 = Color.token(.oklch(0.835, 0.041, 254), .oklch(0.300, 0.050, 242))
    static let foil2 = Color.token(.oklch(0.747, 0.105, 250), .oklch(0.400, 0.080, 246))
    static let foil3 = Color.token(.oklch(0.699, 0.060, 250), .oklch(0.520, 0.100, 250))
    static let foil4 = Color.token(.oklch(0.534, 0.110, 250), .oklch(0.620, 0.090, 250))
    static let glint = Color.token(.oklch(0.900, 0.045, 235), .oklch(0.780, 0.095, 235))
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

private struct ToodleTransitionProgressKey: EnvironmentKey { static let defaultValue = 1.0 }
extension EnvironmentValues {
    var toodleTransitionProgress: Double {
        get { self[ToodleTransitionProgressKey.self] }
        set { self[ToodleTransitionProgressKey.self] = newValue }
    }
}

// 3. Glass text zone: near-opaque paper so text never sits on foil, thin-film edge, anisotropic highlight.
extension View {
    func textZone(radius: Double = Tok.Radius.lg) -> some View {
        let shape = RoundedRectangle(cornerRadius:radius,style:.continuous)
        return background(Tok.panel.opacity(Tok.panelOpacity),in:shape).overlay(shape.strokeBorder(Tok.thinFilm.opacity(0.7),lineWidth:1)).overlay(shape.strokeBorder(Tok.sheen,lineWidth:1.5).blendMode(.plusLighter))
    }
    func foilScreen() -> some View { background { Backdrop() } }
    func serifBody() -> some View { modifier(KineticFont(weight:450,opsz:16,size:16,style:.body)) }
    func serifCaption() -> some View { modifier(KineticFont(weight:500,opsz:13,size:13,style:.caption1)) }
}

// 9. Native system font. Size is still scaled by Dynamic Type in KineticFont; the weight is mapped to SwiftUI's Font.Weight.
enum Serif {
    static func font(size: Double, weight: Double, opsz: Double) -> Font {
        .system(size: size.rounded(), weight: fontWeight(weight))
    }
    private static func fontWeight(_ value: Double) -> Font.Weight {
        switch value {
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
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
    @Environment(\.toodleTransitionProgress) private var transitionProgress
    @State private var settled = false
    init(_ text: String, size: Double, style: UIFont.TextStyle, weight: Double = 600, extrude: Bool = false, kinetic: Bool = true) { self.text = text; self.size = size; self.style = style; self.weight = weight; self.extrude = extrude; self.kinetic = kinetic }
    var body: some View {
        let done = settled || reduceMotion || !kinetic
        let font = KineticFont(weight:done ? weight : Tok.Face.weights.lowerBound,opsz:done ? size * 1.6 : Tok.Face.sizes.lowerBound,size:size,style:style)
        let content = Text(text).modifier(font).foregroundStyle(Tok.ink)
            .background(alignment:.topLeading) {
                if extrude { ZStack(alignment:.topLeading) { ForEach(1..<5) { i in Text(text).modifier(font).foregroundStyle(Tok.foil4.opacity(0.32 - Double(i) * 0.06)).offset(x:-cos(Tok.lightAngle) * Double(i) * 0.8,y:-sin(Tok.lightAngle) * Double(i) * 0.8) } }.accessibilityHidden(true) }
            }
            .onAppear { withAnimation(Tok.viscous(Tok.Duration.slow)) { settled = true } }
            .onChange(of:text) { settled = false; Task { withAnimation(Tok.viscous(Tok.Duration.slow)) { settled = true } } }
        if kinetic && !reduceMotion && transitionProgress > 0.001 && transitionProgress < 0.999 {
            content.distortionEffect(ShaderLibrary.typeDisplace(.float(transitionProgress),.float(Tok.noiseSeed)),maxSampleOffset:CGSize(width:4,height:4))
        } else { content }
    }
}

// Button spec: idle / hover (pointer lift) / active (caustics) / disabled / focus (two-tone ring, >= 3:1 on paper and foil).
struct ToodleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration:configuration) }
    struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label.serifBody().padding(.horizontal,20).padding(.vertical,12)
                .frame(minHeight:44).foregroundStyle(enabled ? Tok.panel : Tok.ink)
                .background { ZStack { Capsule().fill(enabled ? Tok.ink : Tok.quietBlue); if enabled && (configuration.isPressed || focused) { Caustics().clipShape(Capsule()) } } }
                .overlay { if focused { ZStack { Capsule().strokeBorder(Tok.panel,lineWidth:2).padding(-2); Capsule().strokeBorder(Tok.accent,lineWidth:2).padding(-4) } } }
                .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
                .animation(reduceMotion ? nil : Tok.viscous(Tok.Duration.quick),value:configuration.isPressed)
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

// Quality tiers: p95 of display-link frame intervals over 120 frames. The 0.2 ms tolerance
// accounts for a 60 Hz display's nominal 16.67 ms interval; recover after five clean windows.
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
        if p95 > Tok.frameBudget + 0.2, tier > .low { tier = Tier(rawValue:tier.rawValue - 1)!; clean = 0 }
        else if p95 <= Tok.frameBudget { clean += 1; if clean >= 5, tier < .high { tier = Tier(rawValue:tier.rawValue + 1)!; clean = 0 } }
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

struct WaterTransition: View {
    var progress: Double
    @Environment(\.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quality = Quality.shared
    var body: some View {
        GeometryReader { geometry in
            if reduceMotion { Color.clear }
            else if quality.tier == .low {
                Tok.paper.opacity(1 - abs(2 * progress - 1))
            } else {
                Rectangle().fill(.white).colorEffect(ShaderLibrary.flowField(
                    .float2(geometry.size),.float(progress),.float(Tok.lightAngle),.float(Tok.noiseSeed),
                    .color(Tok.foil1.resolved(env)),.color(Tok.foil4.resolved(env))))
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct WaterEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.5
    func body(content: Content) -> some View {
        content.environment(\.toodleTransitionProgress,progress)
            .overlay { WaterTransition(progress:progress) }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Tok.viscous(Tok.Duration.transition / 2)) { progress = 1 }
            }
    }
}
extension View {
    func waterEntrance() -> some View { modifier(WaterEntrance()) }
}

// The baked Gray–Scott mask is used only while an existing operation is loading.
struct ReactionLoading: View {
    var title = "Loading…"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0
    var body: some View {
        HStack(spacing:Tok.Space.sm) {
            Image("ReactionPattern").resizable().renderingMode(.template)
                .foregroundStyle(Tok.accent).frame(width:32,height:32)
                .rotationEffect(.degrees(rotation)).accessibilityHidden(true)
            Text(title).serifCaption()
        }.accessibilityElement(children:.ignore).accessibilityLabel(title)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Tok.viscous(Tok.Duration.ambient)) { rotation = 120 }
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
