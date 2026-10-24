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
    var verified: Bool { guard cameraCapture, let fix = capturedFix else { return false }; return abs(fix.timestamp.timeIntervalSinceNow) < 120 && fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 50 && fix.sourceInformation?.isSimulatedBySoftware != true }
    var eligible: Bool { result?.eligible(freshGeotag:verified,mocked:!cameraCapture) == true }
    var fieldNode: Node {
        var node = Node(id:"field-\(capturedFix?.coordinate.latitude.formatted(.number.precision(.fractionLength(3))) ?? "demo")-\(capturedFix?.coordinate.longitude.formatted(.number.precision(.fractionLength(3))) ?? "demo")",name:"Field capture",lat:capturedFix?.coordinate.latitude ?? 28.64,lng:capturedFix?.coordinate.longitude ?? 77.22,region:"Field",drainType:"Visual inspection")
        node.reportedFRI = result?.pooling; node.v = result?.pooling ?? 0; node.a = result?.blockage == true ? 1 : 0; node.drainStatus = result?.blockage == true ? "Drain blockage detected (visual)" : "Visual pooling detected"; return node
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("Ground truth.\nFrom the street.").font(.largeTitle.bold())
                    Text("Capture a road or drain to inspect pooling and blockage.").foregroundStyle(.secondary)
                    if let image { Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:verticalSizeClass == .compact ? 160 : 300).clipShape(RoundedRectangle(cornerRadius:20)) }
                    HStack {
                        Button { Task {
                            guard AVCaptureDevice.default(for:.video) != nil else { status = "Camera unavailable. Select a photo for demo analysis."; return }
                            if await AVCaptureDevice.requestAccess(for:.video) { location.request(); camera = true } else { status = "Camera access denied. Enable Camera in iOS Settings or select a photo." }
                        } } label: { Label("Camera",systemImage:"camera") }.buttonStyle(.borderedProminent)
                        PhotosPicker(selection:$item,matching:.images) { Label("Photos",systemImage:"photo") }.buttonStyle(.bordered)
                    }.disabled(busy)
                    Button("Refresh GPS") { location.request() }
                    Text(location.status).font(.caption).foregroundStyle(.secondary)
                    if !cameraCapture && image != nil { Text("Library photo · unverified capture location").font(.caption).foregroundStyle(.orange) }
                    Button("Analyze image") { Task { await analyze() } }.buttonStyle(.borderedProminent).disabled(jpeg == nil || busy)
                    if busy { ProgressView("Scanning road scene…") }
                    if !status.isEmpty { Text(status).font(.callout) }
                    if let result {
                        VStack(alignment:.leading,spacing:12) {
                            Label(result.simulated ? "Simulated analysis" : "Analysis result",systemImage:"checkmark.viewfinder").font(.title2.bold())
                            Text(result.valid ? "Valid outdoor scene" : "Scene not verified")
                            Text("Flood: \(result.flood ? "Detected" : "Not detected") · Pooling: \(result.pooling, specifier:"%.2f")")
                            Text("Blockage: \(result.blockage ? "Detected" : "Not detected") · Confidence: \(result.blockageConfidence, specifier:"%.0f")%")
                            Text(result.tags.joined(separator:" · ")).font(.caption).foregroundStyle(.teal)
                            Text(eligible ? "Eligible for field dispatch" : "Not eligible for verified dispatch").font(.caption)
                            if eligible || result.simulated { Button("Preview field dispatch") { showDispatch = true } }
                        }.card()
                    }
                }.padding(24)
            }.navigationTitle("Field Capture").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge:.bottom) {
                    TimelineView(.periodic(from:.now,by:1)) { _ in
                        VStack(spacing:6) {
                            Button("Send Test Alert") { Task { await sendTestAlert() } }
                                .buttonStyle(.borderedProminent).tint(eligible && !app.offline ? Tok.accent : .gray)
                                .frame(maxWidth:.infinity)
                                .disabled(!eligible || app.offline || sendingAlert)
                                .accessibilityIdentifier("sendTestAlert")
                            if !eligible || app.offline { Text("Capture and verify a live image with fresh GPS to enable alerts.").font(.caption).foregroundStyle(.secondary) }
                            if sendingAlert { ProgressView() }
                            if !alertStatus.isEmpty { Text(alertStatus).font(.caption).accessibilityIdentifier("testAlertStatus") }
                        }.padding(.horizontal,24).padding(.vertical,12).frame(maxWidth:.infinity)
                            .background(.regularMaterial)
                    }
                }
                .sheet(isPresented:$camera) { CameraView { photo in accept(photo,fromCamera:true) } }
                .sheet(isPresented:$showDispatch) { DispatchSheet(node:fieldNode,simulated:app.offline || result?.simulated == true || !verified,blockage:result?.blockage == true,evidenceExpiresAt:result?.simulated == true ? nil : capturedFix?.timestamp.addingTimeInterval(120)).environment(app) }
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
#Preview { CaptureView().environment(AppEnvironment()) }
