import SwiftUI
import Charts
import ToodleCore
struct NodeDetailSheet: View {
    let node: Node
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var weather = WeatherSnapshot()
    @State private var weatherLoaded = false
    @State private var showDispatch = false
    var current: Node { app.nodes.first { $0.id == node.id } ?? node }
    var liveSamples: [LiveRiskSample] { app.liveHistory[current.id] ?? [] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:Tok.Space.sm) {
                        HStack { VStack(alignment:.leading) { Text(current.drainType).foregroundStyle(Tok.inkMuted); RiskBadge(node:current) }; Spacer(); Text(current.fri,format:.number.precision(.fractionLength(2))).modifier(KineticFont(weight:700,opsz:52,size:52,style:.largeTitle)).foregroundStyle(current.band.color).monospacedDigit() }
                        Text(current.drainStatus).modifier(KineticFont(weight:650,opsz:17,size:17,style:.headline))
                        Text(current.band.action).foregroundStyle(Tok.inkMuted)
                    }.card()
                    VStack(alignment:.leading,spacing:Tok.Space.sm) {
                    Text("Live FRI observations").serifCaption()
                    if liveSamples.count > 1 {
                        Chart {
                            ForEach(liveSamples) { sample in LineMark(x:.value("Time",sample.timestamp),y:.value("FRI",sample.score)).foregroundStyle(current.band.color) }
                            ForEach([0.35,0.65,0.85],id:\.self) { threshold in RuleMark(y:.value("Threshold",threshold)).foregroundStyle(RiskBand(score:threshold).color.opacity(0.5)).lineStyle(StrokeStyle(dash:[4])) }
                        }.chartYScale(domain:0...1).frame(height:180)
                    } else {
                        Chart { if let sample = liveSamples.first { PointMark(x:.value("Time",sample.timestamp),y:.value("FRI",sample.score)).foregroundStyle(current.band.color) } }.chartYScale(domain:0...1).frame(height:110)
                        Text("Collecting live samples from the AWS backend. The chart fills as monitoring refreshes.").serifCaption().foregroundStyle(Tok.inkMuted)
                    }
                    Text("Live risk inputs").serifCaption()
                    Chart {
                        BarMark(x:.value("Component","Rain"),y:.value("Score",current.r)).foregroundStyle(Tok.accent)
                    }.chartYScale(domain:0...1).frame(height:120).accessibilityLabel("Live rain risk \(current.r)")
                    Text("Pooling and acoustic-impedance readings are not published by the current AWS endpoint.").serifCaption().foregroundStyle(Tok.inkMuted)
                    }.card()
                    VStack(alignment:.leading,spacing:10) {
                        KineticText("Weather",size:26,style:.title2,weight:700)
                        Text("\(weather.tempC, specifier:"%.1f")°C · Rain \(weather.rainMmH, specifier:"%.1f") mm/h")
                        if weather.rainMmH == 0 && weather.last24hMm >= 1 { Text("Clear now, rain in the last 24h: \(weather.last24hMm, specifier:"%.1f") mm").foregroundStyle(Tok.accent) }
                        Text("1h / 3h / 6h / 24h").serifCaption().foregroundStyle(Tok.inkMuted)
                        Text([weather.last1hMm,weather.last3hMm,weather.last6hMm,weather.last24hMm].map { $0.formatted(.number.precision(.fractionLength(1))) }.joined(separator:" / ") + " mm").monospacedDigit()
                        Text("Peak 3h: \(weather.peakLast3hMmH, specifier:"%.1f") · Effective: \(weather.effectiveRainMmH, specifier:"%.1f") mm/h").serifCaption()
                        Text("Next 6h: \(weather.next6hPrecipMm, specifier:"%.1f") mm · \(weather.precipProbMax, specifier:"%.0f")% probability").serifCaption()
                        if !weather.forecast.isEmpty { Chart(Array(weather.forecast.enumerated()),id:\.offset) { i,value in BarMark(x:.value("Hour",i+1),y:.value("Rain",value)).foregroundStyle(Tok.accent) }.frame(height:90) }
                        Text(weather.source).serifCaption().foregroundStyle(Tok.inkMuted)
                    }.card()
                    if current.fri >= 0.86 { Button("Preview dispatch") { showDispatch = true }.buttonStyle(.toodle) }
                }.padding().frame(maxWidth:820).frame(maxWidth:.infinity)
            }.serifBody().foregroundStyle(Tok.ink).foilScreen().tint(Tok.accent)
                .navigationTitle(current.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.principal) {
                        HStack(spacing:Tok.Space.sm) {
                            Text(current.name).font(.headline).lineLimit(1)
                            if weatherLoaded { Text("\(weather.tempC, specifier:"%.0f")°C · \(weather.rainMmH, specifier:"%.1f") mm/h").font(.caption).padding(.horizontal,Tok.Space.sm).padding(.vertical,Tok.Space.xs).background(Tok.quietBlue,in:Capsule()).accessibilityIdentifier("nodeWeather") }
                        }
                    }
                    ToolbarItem(placement:.topBarTrailing) { Button("Done") { dismiss() } }
                }
                .task(id:app.offline) {
                    if let live = try? await app.client.weather(lat:node.lat,lng:node.lng) { weather = live; weatherLoaded = !app.offline } else { weatherLoaded = false }
                }
                .sheet(isPresented:$showDispatch) { DispatchSheet(node:current,simulated:app.simulated).environment(app).waterEntrance() }
        }
    }
}
#Preview { NodeDetailSheet(node:StormSimulator.nodes(stage:.storm)[3]).environment(AppEnvironment()) }
