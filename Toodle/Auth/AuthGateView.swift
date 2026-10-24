import SwiftUI
import ClerkKit

struct AuthGateView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(AlertFeedbackManager.self) private var feedback
    var body: some View {
        Group {
            if clerk.user != nil {
                #if DEBUG
                if let mode = UserDefaults.standard.string(forKey:"ToodleBench") { Bench(mode:mode) }
                else { RootTabView() }
                #else
                RootTabView()
                #endif
            }
            else { LoginView() }
        }.onChange(of:clerk.user?.id) { _,userId in if userId == nil { feedback.cancel() } }
    }
}

struct ClerkSetupView: View {
    var body: some View {
        VStack(spacing:16) {
            Image(systemName:"lock.shield").font(.largeTitle).foregroundStyle(Tok.accent)
            Text("Toodle sign-in needs setup").font(.title2.bold())
            Text("Add your Clerk publishable key to the app build configuration, then run Toodle again.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth:440)
    }
}
