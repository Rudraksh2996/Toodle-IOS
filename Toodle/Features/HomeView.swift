import SwiftUI
import ToodleCore
struct HomeView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:26) {
                    HStack { Image("toodle-logo-teal").resizable().scaledToFit().frame(width:120,height:55); Spacer(); Label("DELHI NCR",systemImage:"location.fill").font(.caption.monospaced()) }
                    Text("See the risk.\nBefore the flood.").font(.system(size:44,weight:.bold,design:.rounded)).minimumScaleFactor(0.7)
                    Text("Predict floods before the street submerges.").font(.title3).foregroundStyle(.secondary)
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),alignment:.leading),count:typeSize.isAccessibilitySize ? 1 : geometry.size.width > 650 ? 4 : 2),spacing:16) {
                        stat("12","Monitoring nodes")
                        stat("30–45m","Target lead time")
                        stat("<2.5s","Target alert latency")
                        stat(app.sorted.first?.fri.formatted(.number.precision(.fractionLength(2))) ?? "—","Highest risk")
                    }
                    Button { app.tab = 1 } label: { HStack { Text("Open Command Center"); Spacer(); Image(systemName:"arrow.up.right") }.font(.headline).padding() }.buttonStyle(.borderedProminent)
                    Label(app.source,systemImage:app.simulated ? "wifi.slash" : "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.secondary)
                    Text("Hyperlocal intelligence. Earlier action.").font(.headline)
                    Text("Visual pooling, acoustic impedance and rainfall combine into one actionable Flood Risk Index.").foregroundStyle(.secondary)
                }.padding(24)
            }.background {
                TimelineView(.animation(minimumInterval:0.1,paused:reduceMotion)) { context in
                    let phase = reduceMotion ? 0 : sin(context.date.timeIntervalSince1970 / 4)
                    LinearGradient(colors:[Color.teal.opacity(0.18 + phase * 0.04),.black,.black],startPoint:.topLeading,endPoint:.bottomTrailing)
                }.ignoresSafeArea()
            }
            }
        }
        .task {
            await app.refresh()
        }
    }
    func stat(_ value:String,_ title:String) -> some View { VStack(alignment:.leading,spacing:8) { Text(value).font(.system(.title,design:.rounded,weight:.bold)).monospacedDigit().contentTransition(.numericText()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).card() }
}
#Preview { HomeView().environment(AppEnvironment()).preferredColorScheme(.dark) }
