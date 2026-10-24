import SwiftUI
struct RootTabView: View {
    @State private var app = AppEnvironment()
    @State private var transitionProgress = 1.0
    @State private var transitionID = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TabView(selection:$app.tab) {
            HomeView().tabItem { Label("Home",systemImage:"drop.fill") }.tag(0)
            CommandCenterView().tabItem { Label("Command",systemImage:"map") }.tag(1)
            CaptureView().tabItem { Label("Capture",systemImage:"camera") }.tag(2)
            SettingsView().tabItem { Label("Settings",systemImage:"gearshape") }.tag(3)
        }.environment(app).environment(\.toodleTransitionProgress,transitionProgress).tint(Tok.accent)
            .overlay { WaterTransition(progress:transitionProgress) }
            .onChange(of:app.tab) { _,_ in
                guard !reduceMotion else { return }
                transitionID += 1
                let current = transitionID
                transitionProgress = 0
                DispatchQueue.main.async {
                    guard current == transitionID else { return }
                    withAnimation(Tok.viscous(Tok.Duration.transition)) { transitionProgress = 1 }
                }
            }
    }
}
#Preview { RootTabView() }
