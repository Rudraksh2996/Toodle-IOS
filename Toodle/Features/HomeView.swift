import SwiftUI
import ToodleCore
struct HomeView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scroll = 0.0
    @State private var hover: CGPoint?
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:Tok.Space.lg) {
                    HStack { Image("toodle-logo-teal").resizable().scaledToFit().frame(width:120,height:55); Spacer(); Label("DELHI NCR",systemImage:"location.fill").font(.caption.monospaced()).foregroundStyle(Tok.ink).padding(.horizontal,Tok.Space.sm).padding(.vertical,Tok.Space.xs).textZone(radius:Tok.Radius.pill) }
                    Color.clear.frame(height:stage(geometry))
                    VStack(alignment:.leading,spacing:Tok.Space.sm) {
                        KineticText("See the risk.\nBefore the flood.",size:44,style:.largeTitle,extrude:true).minimumScaleFactor(0.7)
                        Text("Predict floods before the street submerges.").font(.title3).foregroundStyle(Tok.inkMuted)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(Tok.Space.lg).textZone()
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),alignment:.leading),count:typeSize.isAccessibilitySize ? 1 : geometry.size.width > 650 ? 4 : 2),spacing:Tok.Space.md) {
                        stat("12","Monitoring nodes")
                        stat("30–45m","Target lead time")
                        stat("<2.5s","Target alert latency")
                        stat(app.sorted.first?.fri.formatted(.number.precision(.fractionLength(2))) ?? "—","Highest risk",kinetic:false)
                    }
                    Button { app.tab = 1 } label: { HStack { Text("Open Command Center"); Spacer(); Image(systemName:"arrow.up.right") }.font(.headline).padding() }.buttonStyle(.toodle)
                    VStack(alignment:.leading,spacing:Tok.Space.sm) {
                        Label(app.source,systemImage:app.simulated ? "wifi.slash" : "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(Tok.inkMuted)
                        KineticText("Hyperlocal intelligence. Earlier action.",size:20,style:.headline)
                        Text("Visual pooling, acoustic impedance and rainfall combine into one actionable Flood Risk Index.").foregroundStyle(Tok.inkMuted)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(Tok.Space.lg).textZone()
                }.padding(Tok.Space.lg).frame(maxWidth:820).frame(maxWidth:.infinity)
                .onGeometryChange(for:Double.self) { Double($0.frame(in:.scrollView).minY) } action: { scroll = $0 }
            }
            .onContinuousHover { phase in if case .active(let point) = phase { hover = point } else { hover = nil } }
            .background { Backdrop(metaballs:true,anchor:CGPoint(x:0,y:geometry.safeAreaInsets.top + Tok.Space.lg * 2 + 55 + stage(geometry) / 2),stageHeight:stage(geometry),scroll:reduceMotion ? 0 : scroll,hover:hover) }
            }
        }
        .task {
            await app.refresh()
        }
    }
    // Highest risk is a risk indicator: static (kinetic:false).
    func stat(_ value:String,_ title:String,kinetic:Bool = true) -> some View { VStack(alignment:.leading,spacing:Tok.Space.xs) { KineticText(value,size:28,style:.title1,weight:700,kinetic:kinetic).monospacedDigit(); Text(title).font(.caption).foregroundStyle(Tok.inkMuted) }.frame(maxWidth:.infinity,alignment:.leading).card() }
    func stage(_ geometry:GeometryProxy) -> Double { min(220,geometry.size.height * 0.22) }
}
#Preview { HomeView().environment(AppEnvironment()) }
