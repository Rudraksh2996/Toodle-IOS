import SwiftUI
import ToodleCore
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app
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
                    Text(app.source).font(.caption)
                    Button("Run health check") { Task { busy = true; defer { busy = false }; do { health = try await app.client.health(); status = "Diagnostics complete" } catch { health = nil; status = error.localizedDescription } } }.disabled(busy)
                    if busy { ProgressView() }
                    if let health { LabeledContent("Region",value:health.region); LabeledContent("DynamoDB",value:health.dynamoDB); LabeledContent("SNS",value:health.sns) }
                    if !status.isEmpty { Text(status).font(.caption) }
                }
                Section("Node directory") {
                    ForEach(SeedNodes.all) { node in VStack(alignment:.leading) { Text(node.name); Text("\(node.lat, specifier:"%.4f"), \(node.lng, specifier:"%.4f") · \(node.region)").font(.caption).foregroundStyle(.secondary) } }
                }
                Section("About") {
                    Text("Toodle · 1.0 (1)")
                    Text("Created for KIET Group of Institutions. Built with SwiftUI.")
                    Text("Rainfall: Open-Meteo. Maps: Apple Maps. Risk estimates support field inspection and do not replace official emergency guidance.").font(.caption)
                }
            }.navigationTitle("Settings")
        }.onChange(of:app.offline) { _,_ in app.stop(); app.stage = nil; Task { await app.refresh() } }
    }
}
#Preview { SettingsView().environment(AppEnvironment()) }
