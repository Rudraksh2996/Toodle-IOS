import SwiftUI
import MapKit
import CoreLocation
import ToodleCore
struct CommandCenterView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: Node?
    @State private var dispatch: Node?
    @State private var satellite = false
    // Asking for when-in-use access lets MapKit show the blue current-location dot.
    @State private var locationManager = CLLocationManager()
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width > 650 && !typeSize.isAccessibilitySize {
                    HStack(alignment:.top,spacing:20) {
                        mapPanel(height:max(180, geometry.size.height - 72)).frame(maxWidth:.infinity)
                        ScrollView { controlsPanel.padding(.bottom) }.frame(maxWidth:.infinity)
                    }.padding(.horizontal).padding(.top,8)
                } else {
                    ScrollView {
                        VStack(alignment:.leading,spacing:18) {
                            mapPanel(height:300)
                            controlsPanel
                        }.padding()
                    }
                }
            }
            .navigationTitle("Command Center")
                .sheet(item:$selected) { node in NodeDetailSheet(node:node).environment(app).presentationDetents([.medium,.large]) }
                .sheet(item:$dispatch) { node in DispatchSheet(node:node,simulated:app.simulated).environment(app) }
                .task {
                    while !Task.isCancelled { await app.refresh(); do { try await Task.sleep(for:.seconds(30)) } catch { break } }
                }.onAppear { if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() } }
                .onDisappear { app.stop() }
        }
    }
    func mapPanel(height: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label(app.source,systemImage:app.simulated ? "wifi.slash" : "antenna.radiowaves.left.and.right").font(.caption); Spacer(); Toggle("Satellite",isOn:$satellite).font(.caption).fixedSize() }
            Map(initialPosition:.userLocation(fallback:.region(MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:28.7531817,longitude:77.4970664),span:MKCoordinateSpan(latitudeDelta:0.25,longitudeDelta:0.25))))) {
                UserAnnotation()
                ForEach(app.nodes) { node in
                    Annotation(node.name,coordinate:CLLocationCoordinate2D(latitude:node.lat,longitude:node.lng)) {
                        Button { selected = node } label: {
                            Image(systemName:"drop.fill").font(.title3).foregroundStyle(node.band.color).padding(9).background(.black.opacity(0.8),in:Circle())
                                .symbolEffect(.pulse,options:.repeating,isActive:node.band == .critical && !reduceMotion)
                        }.accessibilityLabel("\(node.name), \(node.band.rawValue), FRI \(node.fri.formatted(.number.precision(.fractionLength(2))))")
                    }
                }
            }.mapStyle(satellite ? .imagery : .standard).frame(height:height).clipShape(RoundedRectangle(cornerRadius:24))
        }
    }
    var controlsPanel: some View {
        @Bindable var app = app
        return VStack(alignment:.leading,spacing:18) {
                    if let critical = app.sorted.first, critical.fri >= 0.86 {
                        Button { dispatch = critical } label: { Label("Critical hazard · Preview dispatch",systemImage:"exclamationmark.triangle.fill").font(.headline).frame(maxWidth:.infinity).padding().background(.red.opacity(0.2),in:RoundedRectangle(cornerRadius:14)).foregroundStyle(.red) }.transition(.move(edge:.top).combined(with:.opacity))
                    }
                    VStack(alignment:.leading,spacing:14) {
                        HStack { Text("Storm Simulator").font(.headline); Spacer(); if let stage = app.stage { Text("T+\(stage.minute)m").monospacedDigit().foregroundStyle(.teal) } }
                        ViewThatFits {
                            HStack { stageButtons }
                            VStack { stageButtons }
                        }
                        if app.playing { ProgressView(value:Double(app.stage?.minute ?? 0),total:60) }
                        Button { app.playing ? app.stop() : app.play() } label: { Label(app.playing ? "Stop sequence" : "Play Storm Sequence",systemImage:app.playing ? "stop.fill" : "play.fill") }.accessibilityIdentifier("playStorm")
                        Toggle("Sync simulation telemetry to cloud",isOn:$app.syncToCloud).font(.caption).disabled(app.offline)
                        if app.syncToCloud { Text("Stage changes write demo telemetry to the configured backend.").font(.caption).foregroundStyle(.orange) }
                        if app.stage != nil { Button("Resume live monitoring") { app.stop(); app.stage = nil; Task { await app.refresh() } } }
                    }.card()
                    Text("Priority Queue").font(.title2.bold())
                    ForEach(app.sorted) { node in
                        Button { selected = node } label: {
                            HStack { VStack(alignment:.leading,spacing:7) { Text(node.name).font(.headline); Text(node.drainType).font(.caption).foregroundStyle(.secondary); RiskBadge(node:node) }; Spacer(); Text(node.fri,format:.number.precision(.fractionLength(2))).font(.system(.title2,design:.rounded,weight:.bold)).monospacedDigit().contentTransition(.numericText()).foregroundStyle(node.band.color) }.card()
                        }.buttonStyle(.plain).accessibilityIdentifier("node-\(node.id)")
                    }
                    if !app.message.isEmpty { Text(app.message).font(.caption) }
        }
    }
    var stageButtons: some View { ForEach(StormStage.allCases,id:\.self) { stage in Button(stage.rawValue) { app.stop(); app.setStage(stage) }.buttonStyle(.bordered).tint(app.stage == stage ? .teal : .gray).font(.caption) } }
}
#Preview { CommandCenterView().environment(AppEnvironment()).preferredColorScheme(.dark) }
