import SwiftUI
struct RootTabView: View {
    @State private var app = AppEnvironment()
    var body: some View {
        TabView(selection:$app.tab) {
            HomeView().tabItem { Label("Home",systemImage:"drop.fill") }.tag(0)
            CommandCenterView().tabItem { Label("Command",systemImage:"map") }.tag(1)
            CaptureView().tabItem { Label("Capture",systemImage:"camera") }.tag(2)
            SettingsView().tabItem { Label("Settings",systemImage:"gearshape") }.tag(3)
        }.environment(app).tint(Color(red:0.08,green:0.72,blue:0.65))
    }
}
#Preview { RootTabView() }
