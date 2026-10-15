import SwiftUI
import AVFoundation

/// Manages a camera capture session for the mirror.
@MainActor
final class CameraController: ObservableObject {
    let session = AVCaptureSession()
    @Published var authorized = false
    @Published var denied = false
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in ok ? self.configure() : (self.denied = true) }
            }
        default:
            denied = true
        }
    }

    private func configure() {
        authorized = true
        if !configured {
            configured = true
            session.beginConfiguration()
            session.sessionPreset = .high
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
        }
        if !session.isRunning { session.startRunning() }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.layer as? AVCaptureVideoPreviewLayer)?.frame = nsView.bounds
    }
}

struct MirrorView: View {
    @StateObject private var cam = CameraController()

    var body: some View {
        Group {
            if cam.authorized {
                CameraPreview(session: cam.session)
                    // Mirror horizontally like FaceTime.
                    .scaleEffect(x: -1, y: 1)
                    .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            } else if cam.denied {
                FeedStatus(icon: "camera.fill", text: "Camera access denied",
                    accessory: AnyView(
                        PillButton(title: "Open Privacy Settings", prominent: true) {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                        }
                    ))
            } else {
                FeedStatus(icon: "camera.fill", text: "Starting camera…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
    }
}
