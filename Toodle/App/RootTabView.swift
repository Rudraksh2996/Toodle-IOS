import SwiftUI
struct RootTabView: View {
    var body: some View {
        TabView {
            Text("Toodle").tabItem { Label("Home", systemImage: "drop.fill") }
            Text("Command Center").tabItem { Label("Command", systemImage: "map") }
            Text("Field Capture").tabItem { Label("Capture", systemImage: "camera") }
            Text("Settings").tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
#Preview { RootTabView() }
