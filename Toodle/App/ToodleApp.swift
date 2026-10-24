import SwiftUI
@main struct ToodleApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let mode = UserDefaults.standard.string(forKey:"ToodleBench") { Bench(mode:mode) } else { RootTabView() }
            #else
            RootTabView()
            #endif
        }
    }
}
