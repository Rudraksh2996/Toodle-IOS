import SwiftUI
import ClerkKit
@main struct ToodleApp: App {
    @State private var feedback = AlertFeedbackManager()
    private let clerkConfigured: Bool
    private let visualScheme: ColorScheme
    init() {
        visualScheme = ProcessInfo.processInfo.arguments.contains("-ToodleDark") ? .dark : .light
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(Tok.panel)
        navigation.titleTextAttributes = [.font:UIFont.preferredFont(forTextStyle:.headline), .foregroundColor:UIColor(Tok.ink)]
        navigation.largeTitleTextAttributes = [.font:UIFont.preferredFont(forTextStyle:.largeTitle), .foregroundColor:UIColor(Tok.ink)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(Tok.panel)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
        let tabFont = UIFont.preferredFont(forTextStyle:.caption2)
        UITabBarItem.appearance().setTitleTextAttributes([.font:tabFont],for:.normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font:tabFont],for:.selected)
        let key = Bundle.main.object(forInfoDictionaryKey:"CLERK_PUBLISHABLE_KEY") as? String ?? ""
        clerkConfigured = key.hasPrefix("pk_test_") || key.hasPrefix("pk_live_")
        if clerkConfigured { Clerk.configure(publishableKey:key) }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if clerkConfigured { AuthGateView().environment(Clerk.shared).environment(feedback).feedbackPopup(feedback) }
                else { ClerkSetupView() }
            }.preferredColorScheme(visualScheme)
        }
    }
}
