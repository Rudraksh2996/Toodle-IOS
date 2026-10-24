import SwiftUI
import ClerkKit
import ToodleCore

@MainActor @Observable final class AlertFeedbackManager {
    enum Stage { case question, thankYou, offerResend }
    var stage: Stage?
    private var pending: Task<Void,Never>?
    private var deadline: Date?
    private var foreground = true
    private var lastAlert: (node: Node, blockage: Bool, baseURL: String)?

    func send(api: any APIClient, node: Node, blockage: Bool, baseURL: String, simulated: Bool) async throws -> DispatchResult {
        let response = try await api.dispatch(node:node,blockage:blockage)
        if response.success && !simulated { schedule(node:node,blockage:blockage,baseURL:baseURL) }
        return response
    }

    func schedule(node: Node, blockage: Bool, baseURL: String) {
        pending?.cancel()
        stage = nil
        lastAlert = (node,blockage,baseURL)
        deadline = Date().addingTimeInterval(40)
        pending = Task { [weak self] in
            try? await Task.sleep(for:.seconds(40))
            guard !Task.isCancelled else { return }
            self?.showIfDue()
        }
    }

    func setForeground(_ value: Bool) {
        foreground = value
        if value { showIfDue() }
    }

    private func showIfDue() {
        guard foreground, let deadline, Date() >= deadline else { return }
        self.deadline = nil
        stage = .question
    }

    func dismiss() { stage = nil }
    func cancel() {
        pending?.cancel()
        pending = nil
        deadline = nil
        lastAlert = nil
        stage = nil
    }

    func resend(token: String) async throws {
        guard let lastAlert else { throw APIError.unavailable }
        guard let url = URL(string:lastAlert.baseURL.trimmingCharacters(in:CharacterSet(charactersIn:"/")) + "/api/test-alert-resend"), url.scheme == "https" else { throw APIError.invalidURL }
        var request = URLRequest(url:url,timeoutInterval:12)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject:[
            "nodeId":lastAlert.node.id,
            "nodeName":lastAlert.node.name,
            "fri":lastAlert.node.fri,
            "drainStatus":lastAlert.node.drainStatus,
            "action":lastAlert.node.band.action,
            "blockageDetected":lastAlert.blockage
        ])
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse else { throw APIError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
            throw APIError.response(http.statusCode,object["error"] as? String ?? "Resend was not accepted.",object["remainingSeconds"] as? Double ?? 0)
        }
        guard let result = try? JSONDecoder().decode(DispatchResult.self,from:data), result.success else { throw APIError.unavailable }
        schedule(node:lastAlert.node,blockage:lastAlert.blockage,baseURL:lastAlert.baseURL)
    }
}

private struct FeedbackPopupModifier: ViewModifier {
    let feedback: AlertFeedbackManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var overlayWindow: UIWindow?
    func body(content: Content) -> some View {
        content
            .onAppear { updateWindow() }
            .onChange(of:feedback.stage != nil) { _,_ in updateWindow() }
            .onChange(of:scenePhase) { _,phase in feedback.setForeground(phase == .active) }
            .onDisappear { overlayWindow?.isHidden = true; overlayWindow = nil }
    }
    private func updateWindow() {
        guard feedback.stage != nil else { overlayWindow?.isHidden = true; overlayWindow = nil; return }
        guard overlayWindow == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where:{ $0.activationState == .foregroundActive }) else { return }
        let window = UIWindow(windowScene:scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = UIColor.clear
        window.rootViewController = UIHostingController(rootView:FeedbackOverlayView().environment(feedback).environment(Clerk.shared))
        window.isHidden = false
        overlayWindow = window
    }
}

extension View {
    func feedbackPopup(_ manager: AlertFeedbackManager) -> some View { modifier(FeedbackPopupModifier(feedback:manager)) }
}

private struct FeedbackOverlayView: View {
    var body: some View {
        ZStack {
            Tok.ink.opacity(0.55).ignoresSafeArea()
            FeedbackPopupView().padding(24)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

private struct FeedbackPopupView: View {
    @Environment(AlertFeedbackManager.self) private var feedback
    @Environment(Clerk.self) private var clerk
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        VStack(spacing:18) {
            switch feedback.stage {
            case .question:
                KineticText("Was action taken by the authorities?",size:27,style:.title2,weight:700,kinetic:false).multilineTextAlignment(.center)
                HStack(spacing:16) {
                    Button("Yes") { feedback.stage = .thankYou }.buttonStyle(.toodle)
                    Button("No") { feedback.stage = .offerResend }.buttonStyle(.bordered)
                }
            case .thankYou:
                KineticText("Thank you",size:27,style:.title2,weight:700)
                Button("Done") { feedback.dismiss() }.buttonStyle(.toodle)
            case .offerResend:
                KineticText("No action yet?",size:27,style:.title2,weight:700,kinetic:false)
                Text("You can send the test alert again.").multilineTextAlignment(.center).foregroundStyle(Tok.inkMuted)
                Button("Send test alert again") { Task { await resend() } }.buttonStyle(.toodle).disabled(busy)
                Button("Cancel") { feedback.dismiss() }.disabled(busy)
            case nil: EmptyView()
            }
            if busy { ReactionLoading(title:"Sending…") }
            if !error.isEmpty { Text(error).serifCaption().foregroundStyle(Tok.strongBlue).multilineTextAlignment(.center) }
        }
        .padding(24).frame(maxWidth:400)
        .serifBody().foregroundStyle(Tok.ink).textZone(radius:24).tint(Tok.accent)
    }
    private func resend() async {
        guard !busy else { return }
        busy = true; error = ""
        defer { busy = false }
        do {
            guard let token = try await clerk.auth.getToken() else { throw APIError.unavailable }
            try await feedback.resend(token:token)
        } catch { self.error = error.localizedDescription }
    }
}
