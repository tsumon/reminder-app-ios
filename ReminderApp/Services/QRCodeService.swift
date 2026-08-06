import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation

/// 二维码：发送端生成（内容为 http://ip:port/reminders.json），接收端扫码
enum QRCodeService {

    /// 生成二维码 UIImage（品牌深色，白底，便于扫描）
    static func generateQRCode(from text: String, size: CGFloat = 260) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }
        let scale = size / ciImage.extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 扫码视图（AVFoundation，轻量无依赖）

struct QRScannerView: UIViewRepresentable {
    var onScanned: (String) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onError: onError)
    }

    func makeUIView(context: Context) -> UIView {
        let view = QRPreviewView(frame: .zero)
        context.coordinator.previewView = view
        context.coordinator.startSession()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onScanned: (String) -> Void
        var onError: (String) -> Void
        var session: AVCaptureSession?
        weak var previewView: QRPreviewView?

        init(onScanned: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onScanned = onScanned
            self.onError = onError
        }

        func startSession() {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted else {
                        self.onError("请在系统设置中允许相机权限，才能扫描二维码")
                        return
                    }
                    self.configureSession()
                }
            }
        }

        private func configureSession() {
            let session = AVCaptureSession()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                onError("无法访问相机")
                return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            self.session = session
            previewView?.configure(session: session)
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               obj.type == .qr,
               let value = obj.stringValue,
               !value.isEmpty {
                onScanned(value)
            }
        }

        func stop() {
            session?.stopRunning()
            session = nil
        }
    }
}

/// 预览层容器
final class QRPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func configure(session: AVCaptureSession) {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
