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
                Label(simulated ? "Simulated dispatch" : "Emergency SMS",systemImage:"paperplane.fill")
                    .modifier(KineticFont(weight:700,opsz:30,size:30,style:.title1)).foregroundStyle(Tok.ink)
                    .padding(Tok.Space.md).textZone()
                Text("Node: \(node.name)\nFRI: \(node.fri.formatted(.number.precision(.fractionLength(2))))\nDrain: \(node.drainStatus)\nAction: \(blockage ? "Clear visually verified drain blockage." : node.band.action)").frame(maxWidth:.infinity,alignment:.leading).card()
                if simulated { Text("Demo only. No SMS will be sent.").foregroundStyle(Tok.inkMuted).card() }
                TimelineView(.periodic(from:.now,by:1)) { context in
                    let remaining = max(0,Int(ceil(until-context.date.timeIntervalSince1970)))
                    if let expiry = evidenceExpiresAt, expiry <= context.date { Text("GPS evidence expired. Capture a new photo before sending.").foregroundStyle(Tok.strongBlue).card() }
                    if remaining > 0 { Text("Cooldown: \(remaining/60)m \(remaining%60)s").monospacedDigit().card() }
                    Button(simulated ? "Simulate dispatch" : "Send emergency SMS") { Task { await send() } }.buttonStyle(.toodle).disabled(busy || remaining > 0 || (!blockage && node.fri < 0.86 && evidenceExpiresAt == nil) || (evidenceExpiresAt.map { $0 <= context.date } ?? false))
                }
                if busy { ReactionLoading(title:"Sending…") }; if !result.isEmpty { Text(result).card().accessibilityIdentifier("dispatchResult") }
                Spacer()
            }.padding(24).frame(maxWidth:640).frame(maxWidth:.infinity)
                .serifBody().foregroundStyle(Tok.ink).foilScreen().tint(Tok.accent)
                .navigationTitle("Dispatch preview").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
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
