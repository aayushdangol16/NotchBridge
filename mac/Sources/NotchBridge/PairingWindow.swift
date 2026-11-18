import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

final class PairingModel: ObservableObject {
    @Published var url: String = Pairing.shared.pairingURL
    @Published var status: BridgeServer.Status = .starting
    var onReset: () -> Void = {}

    func refresh() { url = Pairing.shared.pairingURL }
}

struct PairingView: View {
    @ObservedObject var model: PairingModel
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Pair your Android phone").font(.title2.weight(.semibold))
            Text("Open **NotchBridge** on the phone and tap **Scan QR code**.\nBoth devices must be on the same Wi-Fi.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let qr = Self.qrImage(model.url) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 240, height: 240)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
            }

            statusLine

            HStack {
                Button("Copy pairing link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.url, forType: .string)
                }
                Button("Reset pairing key…") { confirmReset = true }
            }
            .controlSize(.small)
        }
        .padding(28)
        .frame(width: 380)
        .confirmationDialog("Reset the pairing key?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.onReset() }
        } message: {
            Text("The phone that is paired now will stop working until it scans the new QR code.")
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch model.status {
        case .connected(let name):
            Label("Connected to \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
        default:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Waiting for the phone…") }
                .foregroundStyle(.secondary)
        }
    }

    static func qrImage(_ string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}

final class PairingWindowController {
    let model = PairingModel()
    private var window: NSWindow?

    func show() {
        model.refresh()
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "NotchBridge"
            w.contentView = NSHostingView(rootView: PairingView(model: model))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
    var isVisible: Bool { window?.isVisible ?? false }
}
