import SwiftUI
import MapKit
import CoreLocation
import Charts
import ToodleCore
struct CommandCenterView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .sheet(item:$selected) { node in NodeDetailSheet(node:node).environment(app).waterEntrance().presentationDetents([.medium,.large]) }
                .sheet(item:$dispatch) { node in DispatchSheet(node:node,simulated:app.simulated).environment(app).waterEntrance() }
                .task {
                    while !Task.isCancelled { await app.refresh(); do { try await Task.sleep(for:.seconds(30)) } catch { break } }
                }.onAppear { if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() } }
                .onDisappear { app.stop() }
                .foilScreen().tint(Tok.accent).foregroundStyle(Tok.ink)
        }
    }
    func mapPanel(height: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label(app.source,systemImage:app.simulated ? "wifi.slash" : "antenna.radiowaves.left.and.right").serifCaption(); Spacer(); Toggle("Satellite",isOn:$satellite).serifCaption().fixedSize() }
                .padding(Tok.Space.sm).textZone(radius:Tok.Radius.md)
            if app.stage != nil { Text("SIMULATION · not live data").serifCaption().foregroundStyle(Tok.strongBlue).padding(.horizontal,Tok.Space.sm) }
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
                        Button { dispatch = critical } label: {
                            Label("Critical hazard · Preview dispatch",systemImage:"exclamationmark.octagon.fill")
                                .frame(maxWidth:.infinity).padding().foregroundStyle(Tok.ink)
                                .background(Tok.quietBlue,in:RoundedRectangle(cornerRadius:14))
                                .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Tok.strongBlue,lineWidth:2))
                        }
                    }
                    VStack(alignment:.leading,spacing:14) {
                        HStack { KineticText("Storm Simulation",size:20,style:.headline); Spacer(); if let stage = app.stage { KineticText("T+\(stage.minute)m",size:16,style:.body).monospacedDigit() } }
                        Text("Simulated storm data for demonstrations. It does not change live monitoring.").serifCaption().foregroundStyle(Tok.inkMuted)
                        ViewThatFits {
                            HStack { stageButtons }
                            VStack { stageButtons }
                        }
                        if app.playing { ProgressView(value:Double(app.stage?.minute ?? 0),total:60) }
                        Button { app.playing ? app.stop() : app.play() } label: { Label(app.playing ? "Stop sequence" : "Play Storm Sequence",systemImage:app.playing ? "stop.fill" : "play.fill") }.accessibilityIdentifier("playStorm")
                        Toggle("Sync simulation telemetry to cloud",isOn:$app.syncToCloud).font(.caption).disabled(app.offline)
                        if app.syncToCloud { Text("Stage changes write demo telemetry to the configured backend.").serifCaption().foregroundStyle(Tok.strongBlue) }
                        if app.stage != nil { simulatedFRIGraph }
                        if app.stage != nil { Button("Return to live data") { app.resumeLive() }.accessibilityIdentifier("resumeLive") }
                    }.card()
                    KineticText("Priority Queue",size:28,style:.title2,extrude:true).padding(Tok.Space.sm).textZone(radius:Tok.Radius.md)
                    ForEach(app.sorted) { node in
                        Button { selected = node } label: {
                            HStack { VStack(alignment:.leading,spacing:7) { Text(node.name).modifier(KineticFont(weight:650,opsz:17,size:17,style:.headline)); Text(node.drainType).serifCaption().foregroundStyle(Tok.inkMuted); RiskBadge(node:node) }; Spacer(); Text(node.fri,format:.number.precision(.fractionLength(2))).modifier(KineticFont(weight:700,opsz:28,size:28,style:.title2)).monospacedDigit().foregroundStyle(node.band.color) }.card()
                        }.buttonStyle(.plain).accessibilityIdentifier("node-\(node.id)")
                    }
                    if !app.message.isEmpty { Text(app.message).serifCaption().card() }
        }
    }
    // Simulated FRI history (60 points per node) for the highest-risk node in the current storm stage.
    @ViewBuilder var simulatedFRIGraph: some View {
        if let top = app.sorted.first {
            VStack(alignment:.leading,spacing:8) {
                Text("Simulated FRI · \(top.name)").serifCaption().foregroundStyle(Tok.strongBlue)
                Chart {
                    ForEach(Array(top.history.enumerated()),id:\.offset) { index,value in LineMark(x:.value("Minute",index),y:.value("FRI",value)).foregroundStyle(top.band.color) }
                    ForEach([0.35,0.65,0.85],id:\.self) { threshold in RuleMark(y:.value("Threshold",threshold)).foregroundStyle(RiskBand(score:threshold).color.opacity(0.5)).lineStyle(StrokeStyle(dash:[4])) }
                }.chartYScale(domain:0...1).frame(height:160).accessibilityLabel("Simulated FRI history for \(top.name)")
            }
        }
    }
    var stageButtons: some View { ForEach(StormStage.allCases,id:\.self) { stage in Button(stage.rawValue) { app.stop(); app.setStage(stage) }.buttonStyle(.bordered).tint(Tok.accent).serifCaption() } }
}
#Preview { CommandCenterView().environment(AppEnvironment()) }
