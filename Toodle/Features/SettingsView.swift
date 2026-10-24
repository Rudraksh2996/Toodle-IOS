import SwiftUI
import ToodleCore
import ClerkKit
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(Clerk.self) private var clerk
    @State private var health: HealthReport?
    @State private var status = ""
    @State private var busy = false
    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("HTTPS API base URL",text:$app.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Toggle("Force offline demo mode",isOn:$app.offline).accessibilityIdentifier("offlineMode")
                    Text(app.source).serifCaption().foregroundStyle(Tok.inkMuted)
                    Button("Run health check") { Task { busy = true; defer { busy = false }; do { health = try await app.client.health(); status = "Diagnostics complete" } catch { health = nil; status = error.localizedDescription } } }.disabled(busy)
                    if busy { ReactionLoading(title:"Checking connection…") }
                    if let health { LabeledContent("Region",value:health.region); LabeledContent("DynamoDB",value:health.dynamoDB); LabeledContent("SNS",value:health.sns) }
                    if !status.isEmpty { Text(status).serifCaption() }
                }.listRowBackground(Tok.panel.opacity(Tok.panelOpacity))
                Section("Node directory") {
                    ForEach(SeedNodes.all) { node in VStack(alignment:.leading) { Text(node.name); Text("\(node.lat, specifier:"%.4f"), \(node.lng, specifier:"%.4f") · \(node.region)").serifCaption().foregroundStyle(Tok.inkMuted) } }
                }.listRowBackground(Tok.panel.opacity(Tok.panelOpacity))
                Section("About") {
                    Text("Toodle · 1.0 (1)")
                    Text("Created for KIET Group of Institutions. Built with SwiftUI.")
                    Text("Rainfall: Open-Meteo. Maps: Apple Maps. Risk estimates support field inspection and do not replace official emergency guidance.").serifCaption()
                }.listRowBackground(Tok.panel.opacity(Tok.panelOpacity))
                Section("Account") {
                    Button("Sign Out") { Task { do { try await clerk.auth.signOut() } catch { status = error.localizedDescription } } }
                }.listRowBackground(Tok.panel.opacity(Tok.panelOpacity))
            }.scrollContentBackground(.hidden).serifBody().foregroundStyle(Tok.ink)
                .foilScreen().tint(Tok.accent).navigationTitle("Settings")
        }.onChange(of:app.offline) { _,_ in app.stop(); app.stage = nil; Task { await app.refresh() } }
    }
}
#Preview { SettingsView().environment(AppEnvironment()) }
