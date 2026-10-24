import SwiftUI
import PhotosUI
import AVFoundation
import CoreLocation
import ToodleCore
@MainActor @Observable final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var fix: CLLocation?
    var status = "Location has not been requested."
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways,.authorizedWhenInUse: manager.requestLocation()
        default: status = "Location access denied. Enable it in iOS Settings for verified capture."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() } }
    func locationManager(_ manager: CLLocationManager,didUpdateLocations locations:[CLLocation]) { fix = locations.last; status = fresh ? "GPS verified" : "Waiting for a fresh, accurate GPS fix." }
    func locationManager(_ manager: CLLocationManager,didFailWithError error: Error) { status = "GPS unavailable: \(error.localizedDescription)" }
    var fresh: Bool { guard let fix else { return false }; return abs(fix.timestamp.timeIntervalSinceNow) < 120 && fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 50 && fix.sourceInformation?.isSimulatedBySoftware != true }
}
struct CaptureView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppEnvironment.self) private var app
    @Environment(AlertFeedbackManager.self) private var feedback
    @State private var location = LocationService()
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var jpeg: Data?
    @State private var camera = false
    @State private var cameraCapture = false
    @State private var capturedFix: CLLocation?
    @State private var result: Analysis?
    @State private var busy = false
    @State private var status = ""
    @State private var showDispatch = false
    @State private var sendingAlert = false
    @State private var alertStatus = ""
    @State private var place: String?
    var verified: Bool { guard cameraCapture, let fix = capturedFix else { return false }; return abs(fix.timestamp.timeIntervalSinceNow) < 120 && fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 50 && fix.sourceInformation?.isSimulatedBySoftware != true }
    var eligible: Bool { result?.eligible(freshGeotag:verified,mocked:!cameraCapture) == true }
    // Exact GPS fix used for analysis, with its accuracy and the place name looked up from the coordinates.
    @ViewBuilder var locationBlock: some View {
        if let capturedFix {
            VStack(alignment:.leading,spacing:4) {
                Text("Location").serifCaption().foregroundStyle(Tok.inkMuted)
                Text(place ?? "Finding place…").foregroundStyle(Tok.ink).accessibilityIdentifier("capturePlace")
                Text("\(capturedFix.coordinate.latitude,specifier:"%.6f"), \(capturedFix.coordinate.longitude,specifier:"%.6f") · ±\(capturedFix.horizontalAccuracy,specifier:"%.0f") m")
                    .monospacedDigit().serifCaption().accessibilityIdentifier("captureCoordinates")
            }
        } else {
            Text("No GPS fix for this image. Its location is not verified.").serifCaption().foregroundStyle(Tok.inkMuted)
        }
    }
    static func placeName(for location: CLLocation) async -> String? {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return [mark.name,mark.subLocality,mark.locality,mark.administrativeArea,mark.country].compactMap { $0 }.joined(separator:", ")
    }
    // The place name used in the help request; falls back to a plain label while the lookup is unavailable.
    var alertPlace: String {
        guard let place, place != "Place name unavailable" else { return "Field capture" }
        return place
    }
    var fieldNode: Node {
        var node = Node(id:"field-\(capturedFix?.coordinate.latitude.formatted(.number.precision(.fractionLength(3))) ?? "demo")-\(capturedFix?.coordinate.longitude.formatted(.number.precision(.fractionLength(3))) ?? "demo")",name:alertPlace,lat:capturedFix?.coordinate.latitude ?? 28.64,lng:capturedFix?.coordinate.longitude ?? 77.22,region:"Field",drainType:"Visual inspection")
        node.reportedFRI = result?.pooling; node.v = result?.pooling ?? 0; node.a = result?.blockage == true ? 1 : 0; node.drainStatus = result?.blockage == true ? "Drain blockage detected (visual)" : "Visual pooling detected"; return node
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:Tok.Space.sm) {
                        KineticText("Ground truth.\nFrom the street.",size:37,style:.largeTitle,extrude:true)
                        Text("Capture a road or drain to inspect pooling and blockage.").foregroundStyle(Tok.inkMuted)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(Tok.Space.lg).textZone()
                    if let image { Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:verticalSizeClass == .compact ? 160 : 300).clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).strokeBorder(Tok.line,lineWidth:1)) }
                    VStack(alignment:.leading,spacing:Tok.Space.sm) {
                    HStack {
                        Button { Task {
                            guard AVCaptureDevice.default(for:.video) != nil else { status = "Camera unavailable. Select a photo for demo analysis."; return }
                            if await AVCaptureDevice.requestAccess(for:.video) { location.request(); camera = true } else { status = "Camera access denied. Enable Camera in iOS Settings or select a photo." }
                        } } label: { Label("Camera",systemImage:"camera") }.buttonStyle(.toodle)
                        PhotosPicker(selection:$item,matching:.images) { Label("Photos",systemImage:"photo") }.buttonStyle(.bordered)
                    }.disabled(busy)
                    Button("Refresh GPS") { location.request() }
                    Text(location.status).serifCaption().foregroundStyle(Tok.inkMuted)
                    if image != nil { locationBlock }
                    if !cameraCapture && image != nil { Text("Library photo · unverified capture location").serifCaption().foregroundStyle(Tok.strongBlue) }
                    Button("Analyze image") { Task { await analyze() } }.buttonStyle(.toodle).disabled(jpeg == nil || busy)
                    if busy { ReactionLoading(title:"Scanning road scene…") }
                    if !status.isEmpty { Text(status) }
                    }.frame(maxWidth:.infinity,alignment:.leading).card()
                    if let result {
                        VStack(alignment:.leading,spacing:12) {
                            KineticText(result.simulated ? "Simulated analysis" : "Analysis result",size:25,style:.title2,weight:700)
                            locationBlock
                            AnalysisIndicators(result:result)
                            Text(result.tags.joined(separator:" · ")).serifCaption().foregroundStyle(Tok.accent)
                            Text(eligible ? "Eligible for field dispatch" : "Not eligible for verified dispatch").serifCaption()
                            if eligible || result.simulated { Button("Preview field dispatch") { showDispatch = true } }
                        }.card()
                    }
                }.padding(24).frame(maxWidth:820).frame(maxWidth:.infinity)
            }.serifBody().foregroundStyle(Tok.ink).foilScreen().tint(Tok.accent)
                .navigationTitle("Field Capture").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge:.bottom) {
                    TimelineView(.periodic(from:.now,by:1)) { _ in
                        VStack(spacing:6) {
                            Button("Send Test Alert") { Task { await sendTestAlert() } }
                                .buttonStyle(.toodle)
                                .frame(maxWidth:.infinity)
                                .disabled(!eligible || app.offline || sendingAlert)
                                .accessibilityIdentifier("sendTestAlert")
                            if !eligible || app.offline { Text("Capture and verify a live image with fresh GPS to enable alerts.").serifCaption().foregroundStyle(Tok.inkMuted) }
                            if sendingAlert { ReactionLoading(title:"Sending alert…") }
                            if !alertStatus.isEmpty { Text(alertStatus).serifCaption().accessibilityIdentifier("testAlertStatus") }
                        }.padding(.horizontal,24).padding(.vertical,12).frame(maxWidth:.infinity)
                            .background(Tok.panel.opacity(0.98))
                            .overlay(alignment:.top) { Rectangle().fill(Tok.line).frame(height:1) }
                    }
                }
                .sheet(isPresented:$camera) { CameraView { photo in accept(photo,fromCamera:true) }.waterEntrance() }
                .sheet(isPresented:$showDispatch) { DispatchSheet(node:fieldNode,simulated:app.offline || result?.simulated == true || !verified,blockage:result?.blockage == true,evidenceExpiresAt:result?.simulated == true ? nil : capturedFix?.timestamp.addingTimeInterval(120)).environment(app).waterEntrance() }
                .task(id:capturedFix?.timestamp) {
                    place = nil
                    guard let capturedFix else { return }
                    place = await Self.placeName(for:capturedFix) ?? "Place name unavailable"
                }
                .onChange(of:item) { _,new in Task { do { if let data = try await new?.loadTransferable(type:Data.self), let photo = UIImage(data:data) { accept(photo,fromCamera:false) } } catch { status = "Could not load this photo." } } }
        }
    }
    func accept(_ photo:UIImage,fromCamera:Bool) {
        result = nil; status = ""; alertStatus = ""; cameraCapture = fromCamera; capturedFix = fromCamera && location.fresh ? location.fix : nil
        let ratio = min(1,1280/max(photo.size.width,photo.size.height)); let size = CGSize(width:photo.size.width*ratio,height:photo.size.height*ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size:size,format:format).image { _ in photo.draw(in:CGRect(origin:.zero,size:size)) }
        image = resized; jpeg = nil
        for quality in stride(from:0.85,through:0.15,by:-0.1) { if let data = resized.jpegData(compressionQuality:quality), data.count <= 1_000_000 { jpeg = data; break } }
        if jpeg == nil { status = "Could not compress this image below 1 MB. Try a different photo." }
    }
    func analyze() async {
        guard let jpeg else { return }; busy = true; defer { busy = false }
        do { result = try await app.client.analyze(image:jpeg,lat:capturedFix?.coordinate.latitude,lng:capturedFix?.coordinate.longitude,mocked:!verified) }
        catch { result = .demo; status = "Analysis unavailable. Showing a labeled demo result. \(error.localizedDescription)" }
    }
    func sendTestAlert() async {
        guard eligible, !app.offline, !sendingAlert else { return }
        let key = "cooldown.live.\(fieldNode.id)"
        let remaining = UserDefaults.standard.double(forKey:key) - Date().timeIntervalSince1970
        guard remaining <= 0 else { alertStatus = "Alert cooldown active for \(Int(ceil(remaining))) seconds."; return }
        sendingAlert = true; alertStatus = ""
        defer { sendingAlert = false }
        do {
            let response = try await feedback.send(api:app.client,node:fieldNode,blockage:result?.blockage == true,baseURL:app.baseURL,simulated:false)
            guard response.success else { alertStatus = "Dispatch was not accepted."; return }
            let until = response.cooldownUntil ?? Date().timeIntervalSince1970 + 900
            UserDefaults.standard.set(until,forKey:key)
            alertStatus = "Accepted · \(response.messageId ?? "No message ID returned")"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch APIError.response(let status,let message,let seconds) {
            alertStatus = message
            if status == 429 { UserDefaults.standard.set(Date().timeIntervalSince1970 + max(seconds,1),forKey:key) }
        } catch { alertStatus = "Delivery unconfirmed. \(error.localizedDescription)" }
    }
}
// Colour-coded indicators for an analysis result. Colours follow the risk bands: green normal, yellow advisory, orange warning, red critical.
struct AnalysisIndicators: View {
    let result: Analysis
    var body: some View {
        VStack(alignment:.leading,spacing:Tok.Space.sm) {
            if result.simulated {
                Label("SIMULATED · demo values, not a real scene",systemImage:"flask.fill")
                    .serifCaption().foregroundStyle(Tok.ink).padding(.horizontal,Tok.Space.sm).padding(.vertical,Tok.Space.xs)
                    .background(RiskBand.advisory.color.opacity(0.25),in:Capsule())
                    .overlay(Capsule().strokeBorder(RiskBand.advisory.color,lineWidth:1.5))
                    .accessibilityIdentifier("simulatedBadge")
            }
            row("Scene",result.valid ? "Valid outdoor scene" : "Not verified",result.valid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",result.valid ? RiskBand.normal.color : RiskBand.warning.color)
            row("Flood",result.flood ? "Detected" : "Not detected",result.flood ? "drop.triangle.fill" : "drop",result.flood ? RiskBand.critical.color : RiskBand.normal.color)
            meter("Pooling",result.pooling,String(format:"%.2f",result.pooling),RiskBand(score:result.pooling).color)
            row("Blockage",result.blockage ? "Detected" : "Not detected",result.blockage ? "xmark.octagon.fill" : "checkmark.circle",result.blockage ? RiskBand.critical.color : RiskBand.normal.color)
            meter("Blockage confidence",result.blockageConfidence / 100,String(format:"%.0f%%",result.blockageConfidence),result.blockage ? RiskBand.critical.color : RiskBand.normal.color)
        }
    }
    func row(_ title: String,_ value: String,_ symbol: String,_ color: Color) -> some View {
        HStack(spacing:Tok.Space.sm) {
            Image(systemName:symbol).foregroundStyle(color).font(.title3).frame(width:28)
            Text(title).serifCaption().foregroundStyle(Tok.inkMuted)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(color)
        }.accessibilityElement(children:.combine)
    }
    func meter(_ title: String,_ fraction: Double,_ label: String,_ color: Color) -> some View {
        VStack(alignment:.leading,spacing:4) {
            HStack { Text(title).serifCaption().foregroundStyle(Tok.inkMuted); Spacer(); Text(label).fontWeight(.semibold).monospacedDigit().foregroundStyle(color) }
            ProgressView(value:min(max(fraction,0),1)).tint(color)
        }.accessibilityElement(children:.combine)
    }
}
#Preview { CaptureView().environment(AppEnvironment()) }
