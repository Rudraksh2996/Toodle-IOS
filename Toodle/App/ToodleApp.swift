import SwiftUI
import ClerkKit
@main struct ToodleApp: App {
    @State private var feedback = AlertFeedbackManager()
    private let clerkConfigured: Bool
    init() {
        let key = Bundle.main.object(forInfoDictionaryKey:"CLERK_PUBLISHABLE_KEY") as? String ?? ""
        clerkConfigured = key.hasPrefix("pk_test_") || key.hasPrefix("pk_live_")
        if clerkConfigured { Clerk.configure(publishableKey:key) }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if clerkConfigured { AuthGateView().environment(Clerk.shared).environment(feedback).feedbackPopup(feedback) }
                else { ClerkSetupView() }
            }
        }
    }
}
