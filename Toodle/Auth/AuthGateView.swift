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
                else { RootTabView().waterEntrance() }
                #else
                RootTabView().waterEntrance()
                #endif
            }
            else { LoginView().waterEntrance() }
        }.onChange(of:clerk.user?.id) { _,userId in if userId == nil { feedback.cancel() } }
    }
}

struct ClerkSetupView: View {
    var body: some View {
        VStack(spacing:16) {
            Image(systemName:"lock.shield").font(.largeTitle).foregroundStyle(Tok.accent)
            KineticText("Toodle sign-in needs setup",size:28,style:.title2,extrude:true)
            Text("Add your Clerk publishable key to the app build configuration, then run Toodle again.")
                .multilineTextAlignment(.center).foregroundStyle(Tok.inkMuted)
        }.padding(24).frame(maxWidth:440).textZone().padding(24)
            .frame(maxWidth:.infinity,maxHeight:.infinity).foilScreen().tint(Tok.accent)
    }
}
