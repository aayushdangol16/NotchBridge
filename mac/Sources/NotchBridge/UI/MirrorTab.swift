import AVFoundation
import AppKit
import SwiftUI

/// Front-camera preview, only running while the Mirror tab is on screen.
final class CameraMirror: ObservableObject {
    enum State { case idle, starting, running, denied, unavailable }
    @Published private(set) var state: State = .idle
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "notchbridge.camera")
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            state = .starting
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { ok ? self.run() : (self.state = .denied) }
            }
        default:
            state = .denied
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
        if state == .running || state == .starting { state = .idle }
    }

    private func run() {
        state = .starting
        queue.async {
            if !self.configured {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .medium
                self.session.addInput(input)
                self.session.commitConfiguration()
                self.configured = true
            }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }
}

private struct PreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MirrorTab: View {
    @ObservedObject var model: IslandModel
    @StateObject private var camera = CameraMirror()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.05))
            switch camera.state {
            case .running:
                PreviewLayerView(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
            case .denied:
                message("video.slash", "Camera access is off", button: "Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .unavailable:
                message("video.slash", "No camera found")
            default:
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .animation(.easeOut(duration: 0.25), value: camera.state)
    }

    private func message(_ icon: String, _ text: String, button: String? = nil, action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
            Text(text).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.45))
            if let button { IslandButton(title: button, icon: nil, style: .secondary, action: action) }
        }
    }
}
