import SwiftUI
import Charts
import ToodleCore
struct NodeDetailSheet: View {
    let node: Node
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var weather = WeatherSnapshot()
    @State private var showDispatch = false
    var current: Node { app.nodes.first { $0.id == node.id } ?? node }
    var liveSamples: [LiveRiskSample] { app.liveHistory[current.id] ?? [] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    HStack { VStack(alignment:.leading) { Text(current.drainType).foregroundStyle(.secondary); RiskBadge(node:current) }; Spacer(); Text(current.fri,format:.number.precision(.fractionLength(2))).font(.system(size:52,weight:.bold,design:.rounded)).foregroundStyle(current.band.color).monospacedDigit() }
                    Text(current.drainStatus).font(.headline)
                    Text(current.band.action).foregroundStyle(.secondary)
                    Text("Live FRI observations").font(.caption)
                    if liveSamples.count > 1 {
                        Chart {
                            ForEach(liveSamples) { sample in LineMark(x:.value("Time",sample.timestamp),y:.value("FRI",sample.score)).foregroundStyle(current.band.color) }
                            ForEach([0.35,0.65,0.85],id:\.self) { threshold in RuleMark(y:.value("Threshold",threshold)).foregroundStyle(RiskBand(score:threshold).color.opacity(0.5)).lineStyle(StrokeStyle(dash:[4])) }
                        }.chartYScale(domain:0...1).frame(height:180)
                    } else {
                        Chart { if let sample = liveSamples.first { PointMark(x:.value("Time",sample.timestamp),y:.value("FRI",sample.score)).foregroundStyle(current.band.color) } }.chartYScale(domain:0...1).frame(height:110)
                        Text("Collecting live samples from the AWS backend. The chart fills as monitoring refreshes.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Live risk inputs").font(.caption)
                    Chart {
                        BarMark(x:.value("Component","Rain"),y:.value("Score",current.r)).foregroundStyle(.blue)
                    }.chartYScale(domain:0...1).frame(height:120).accessibilityLabel("Live rain risk \(current.r)")
                    Text("Pooling and acoustic-impedance readings are not published by the current AWS endpoint.").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment:.leading,spacing:10) {
                        Text("Weather").font(.title2.bold())
                        Text("\(weather.tempC, specifier:"%.1f")°C · Rain \(weather.rainMmH, specifier:"%.1f") mm/h")
                        if weather.rainMmH == 0 && weather.last24hMm >= 1 { Text("Clear now, rain in the last 24h: \(weather.last24hMm, specifier:"%.1f") mm").foregroundStyle(.teal) }
                        Text("1h / 3h / 6h / 24h").font(.caption).foregroundStyle(.secondary)
                        Text([weather.last1hMm,weather.last3hMm,weather.last6hMm,weather.last24hMm].map { $0.formatted(.number.precision(.fractionLength(1))) }.joined(separator:" / ") + " mm").monospacedDigit()
                        Text("Peak 3h: \(weather.peakLast3hMmH, specifier:"%.1f") · Effective: \(weather.effectiveRainMmH, specifier:"%.1f") mm/h").font(.caption)
                        Text("Next 6h: \(weather.next6hPrecipMm, specifier:"%.1f") mm · \(weather.precipProbMax, specifier:"%.0f")% probability").font(.caption)
                        if !weather.forecast.isEmpty { Chart(Array(weather.forecast.enumerated()),id:\.offset) { i,value in BarMark(x:.value("Hour",i+1),y:.value("Rain",value)).foregroundStyle(.blue) }.frame(height:90) }
                        Text(weather.source).font(.caption2).foregroundStyle(.secondary)
                    }.card()
                    if current.fri >= 0.86 { Button("Preview dispatch") { showDispatch = true }.buttonStyle(.borderedProminent) }
                }.padding()
            }.navigationTitle(current.name).navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
                .task(id:app.offline) { weather = (try? await app.client.weather(lat:node.lat,lng:node.lng)) ?? WeatherSnapshot() }
                .sheet(isPresented:$showDispatch) { DispatchSheet(node:current,simulated:app.simulated).environment(app) }
        }
    }
}
#Preview { NodeDetailSheet(node:StormSimulator.nodes(stage:.storm)[3]).environment(AppEnvironment()) }
