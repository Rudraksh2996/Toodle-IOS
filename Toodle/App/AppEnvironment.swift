import SwiftUI
import ToodleCore
struct LiveRiskSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let score: Double
}
@MainActor @Observable final class AppEnvironment {
    var nodes = StormSimulator.nodes(stage: .clear)
    var source = "Offline demo data"
    var stage: StormStage?
    var playing = false
    var tab = 0
    var syncToCloud = false
    var message = ""
    var liveHistory: [String: [LiveRiskSample]] = [:]
    var offline: Bool { didSet { UserDefaults.standard.set(offline, forKey:"offline") } }
    var baseURL: String { didSet { UserDefaults.standard.set(baseURL,forKey:"baseURL") } }
    var sequence: Task<Void,Never>?
    init() {
        offline = UserDefaults.standard.bool(forKey:"offline") || ProcessInfo.processInfo.arguments.contains("--uitesting")
        if ProcessInfo.processInfo.arguments.contains("--uitesting") { for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("cooldown.demo.") { UserDefaults.standard.removeObject(forKey:key) } }
        baseURL = UserDefaults.standard.string(forKey:"baseURL") ?? Bundle.main.object(forInfoDictionaryKey:"API_BASE_URL") as? String ?? "https://main.d8ovyga5ca3ks.amplifyapp.com"
    }
    var client: any APIClient { offline ? MockAPIClient() : LiveAPIClient(baseURL:baseURL) }
    var sorted: [Node] { nodes.sorted { $0.fri == $1.fri ? $0.id < $1.id : $0.fri > $1.fri } }
    var simulated: Bool { offline || stage != nil || source != "Live" }
    func refresh() async {
        guard stage == nil else { return }
        do {
            let (values,label) = try await client.nodes()
            guard stage == nil, !Task.isCancelled else { return }
            nodes = values; source = label
            if label == "Live" {
                let now = Date()
                for node in values {
                    liveHistory[node.id] = Array((liveHistory[node.id] ?? []).suffix(119)) + [LiveRiskSample(timestamp: now, score: node.fri)]
                }
            }
        }
        catch { guard stage == nil, !Task.isCancelled else { return }; nodes = StormSimulator.nodes(stage:.clear); source = "Offline demo data" }
    }
    func setStage(_ value: StormStage) {
        stage = value; source = "Offline demo data"
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .spring()) { nodes = StormSimulator.nodes(stage:value) }
        UIImpactFeedbackGenerator(style:.medium).impactOccurred()
        if syncToCloud && !offline {
            let values = nodes; let api = client
            Task { do { for node in values { try await api.sync(node:node) }; message = "Simulation telemetry synced" } catch { message = error.localizedDescription } }
        }
    }
    func play() {
        stop(); playing = true
        sequence = Task { for value in StormStage.allCases { guard !Task.isCancelled else { break }; setStage(value); do { try await Task.sleep(for:.seconds(3)) } catch { break } }; playing = false }
    }
    func stop() { sequence?.cancel(); sequence = nil; playing = false }
}
extension RiskBand { var color: Color { Color(red:Double((hex >> 16) & 255)/255,green:Double((hex >> 8) & 255)/255,blue:Double(hex & 255)/255) } }
extension View {
    func card() -> some View { padding(Tok.Space.md).textZone() }
}
struct RiskBadge: View {
    let node: Node
    var body: some View { Text(node.band.rawValue).font(.caption.bold()).foregroundStyle(node.band.color).padding(7).background(node.band.color.opacity(0.12),in:Capsule()) }
}
#Preview { RiskBadge(node:SeedNodes.all[0]) }
