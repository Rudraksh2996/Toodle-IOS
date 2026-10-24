import SwiftUI
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context:Context) -> CameraController {
        let controller = CameraController()
        controller.onImage = { image in onImage(image); dismiss() }
        controller.onCancel = { dismiss() }
        return controller
    }
    func updateUIViewController(_ controller:CameraController,context:Context) {}
}
final class CameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label:"com.toodle.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private let shutter = UIButton(type:.system)
    private let status = UILabel()
    var onImage: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session:session); preview.videoGravity = .resizeAspectFill; view.layer.addSublayer(preview); self.preview = preview
        shutter.setTitle("Capture photo",for:.normal); shutter.titleLabel?.font = .preferredFont(forTextStyle:.headline); shutter.backgroundColor = .systemTeal; shutter.tintColor = .black; shutter.layer.cornerRadius = 25; shutter.isEnabled = false; shutter.addTarget(self,action:#selector(capture),for:.touchUpInside)
        let cancel = UIButton(type:.system); cancel.setTitle("Cancel",for:.normal); cancel.addTarget(self,action:#selector(close),for:.touchUpInside)
        status.textColor = .white; status.numberOfLines = 0; status.textAlignment = .center
        for control in [shutter,cancel,status] { control.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(control) }
        NSLayoutConstraint.activate([
            shutter.centerXAnchor.constraint(equalTo:view.centerXAnchor),shutter.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-24),shutter.widthAnchor.constraint(equalToConstant:180),shutter.heightAnchor.constraint(equalToConstant:52),
            cancel.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:24),cancel.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:20),
            status.centerXAnchor.constraint(equalTo:view.centerXAnchor),status.centerYAnchor.constraint(equalTo:view.centerYAnchor),status.widthAnchor.constraint(lessThanOrEqualTo:view.widthAnchor,constant:-40)
        ])
        let session = session; let output = output
        queue.async { [weak self] in
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else { throw CameraError.unavailable }
                let input = try AVCaptureDeviceInput(device:device)
                session.beginConfiguration(); session.sessionPreset = .photo
                guard session.canAddInput(input),session.canAddOutput(output) else { session.commitConfiguration(); throw CameraError.unavailable }
                session.addInput(input); session.addOutput(output); session.commitConfiguration(); session.startRunning()
                DispatchQueue.main.async { self?.configureRotation(device:device); self?.shutter.isEnabled = true }
            } catch { DispatchQueue.main.async { self?.status.text = "Camera unavailable. Close and select a photo instead." } }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewDidDisappear(_ animated:Bool) { super.viewDidDisappear(animated); let session = session; queue.async { session.stopRunning() } }
    @objc private func close() { onCancel?() }
    private func configureRotation(device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device:device, previewLayer:preview)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options:[.initial, .new]) { [weak self] coordinator, _ in
            guard let connection = self?.preview?.connection else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
    }
    @objc private func capture() {
        shutter.isEnabled = false
        if let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
           let connection = output.connection(with:.video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        output.capturePhoto(with:AVCapturePhotoSettings(),delegate:self)
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?) {
        shutter.isEnabled = true
        guard error == nil,let data = photo.fileDataRepresentation(),let image = UIImage(data:data) else { status.text = "Capture failed. Please try again."; return }; onImage?(image)
    }
    enum CameraError: Error { case unavailable }
}
#Preview { CameraView { _ in } }
