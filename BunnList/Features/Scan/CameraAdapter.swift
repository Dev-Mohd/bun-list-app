import AVFoundation
import BunnListCore
import SwiftUI
import UIKit

/// Camera hardware and permission. UI tests inject a state with `-cameraState noCamera|denied`.
struct CameraEnvironment {
    var hardware: () -> CameraHardware
    var authorization: () -> CameraAuthorization
    var requestAccess: () async -> Bool

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> CameraEnvironment {
        if let index = arguments.firstIndex(of: "-cameraState"), arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "noCamera": return .fixed(hardware: .unavailable, authorization: .notDetermined)
            case "denied": return .fixed(hardware: .available, authorization: .denied)
            default: break
            }
        }
        return .live
    }

    static let live = CameraEnvironment(
        hardware: { UIImagePickerController.isSourceTypeAvailable(.camera) ? .available : .unavailable },
        authorization: {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .restricted: return .restricted
            case .denied: return .denied
            @unknown default: return .denied
            }
        },
        requestAccess: { await AVCaptureDevice.requestAccess(for: .video) }
    )

    static func fixed(hardware: CameraHardware, authorization: CameraAuthorization) -> CameraEnvironment {
        CameraEnvironment(hardware: { hardware }, authorization: { authorization }, requestAccess: { false })
    }

    var entryState: ScanEntryState { .resolve(hardware: hardware(), authorization: authorization()) }
}

/// System camera capture. The JPEG stays in memory for the demo extractor; it is not stored or uploaded in C01.
struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.8) {
                onImage(data)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}
