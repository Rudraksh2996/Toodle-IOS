import SwiftUI
import ToodleCore
struct DispatchSheet: View {
    let node: Node
    let simulated: Bool
    var blockage = false
    var evidenceExpiresAt: Date? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(AlertFeedbackManager.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var result = ""
    @State private var until: Double = 0
    var key: String { "cooldown.\(simulated ? "demo" : "live").\(node.id)" }
    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:24) {
                Label(simulated ? "Simulated dispatch" : "Emergency SMS",systemImage:"paperplane.fill").font(.title.bold()).foregroundStyle(simulated ? .teal : .red)
                Text("Node: \(node.name)\nFRI: \(node.fri.formatted(.number.precision(.fractionLength(2))))\nDrain: \(node.drainStatus)\nAction: \(blockage ? "Clear visually verified drain blockage." : node.band.action)").frame(maxWidth:.infinity,alignment:.leading).card()
                if simulated { Text("Demo only. No SMS will be sent.").foregroundStyle(.secondary) }
                TimelineView(.periodic(from:.now,by:1)) { context in
                    let remaining = max(0,Int(ceil(until-context.date.timeIntervalSince1970)))
                    if let expiry = evidenceExpiresAt, expiry <= context.date { Text("GPS evidence expired. Capture a new photo before sending.").foregroundStyle(.orange) }
                    if remaining > 0 { Text("Cooldown: \(remaining/60)m \(remaining%60)s").monospacedDigit() }
                    Button(simulated ? "Simulate dispatch" : "Send emergency SMS") { Task { await send() } }.buttonStyle(.borderedProminent).disabled(busy || remaining > 0 || (!blockage && node.fri < 0.86 && evidenceExpiresAt == nil) || (evidenceExpiresAt.map { $0 <= context.date } ?? false))
                }
                if busy { ProgressView() }; if !result.isEmpty { Text(result).accessibilityIdentifier("dispatchResult") }
                Spacer()
            }.padding(24).navigationTitle("Dispatch preview").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
                .onAppear { until = UserDefaults.standard.double(forKey:key) }
        }
    }
    func send() async {
        guard evidenceExpiresAt.map({ $0 > Date() }) ?? true else { result = "GPS evidence expired. Capture a new photo."; return }
        busy = true; defer { busy = false }
        do {
            let api: any APIClient = simulated ? MockAPIClient() : app.client
            let response = try await feedback.send(api:api,node:node,blockage:blockage,baseURL:app.baseURL,simulated:simulated)
            guard response.success else { result = "Dispatch was not accepted."; return }
            result = "\(simulated ? "Simulated" : "Accepted") · \(response.messageId ?? "No message ID returned")"
            until = response.cooldownUntil ?? Date().timeIntervalSince1970 + 900
            UserDefaults.standard.set(until,forKey:key); UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch APIError.response(let status,let message,let seconds) {
            result = message
            if status == 429 { until = Date().timeIntervalSince1970 + max(seconds,1); UserDefaults.standard.set(until,forKey:key) }
        } catch { result = "Delivery unconfirmed. \(error.localizedDescription)" }
    }
}
#Preview { DispatchSheet(node:StormSimulator.nodes(stage:.storm)[3],simulated:true).environment(AppEnvironment()) }
