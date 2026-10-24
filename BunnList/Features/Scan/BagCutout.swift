import CoreImage
import SwiftUI
import UIKit
import Vision

/// Lifts the bag out of a photo on the device (Vision subject lifting, iOS 17) and
/// centers it on a plain square card, ready for list thumbnails and the detail
/// hero. Returns nil when no clear subject is found (or on the simulator, which
/// lacks the Neural Engine); callers then keep the original photo.
enum BagCutout {
    static func cardImage(from image: UIImage, background: UIColor = UIColor(white: 0.97, alpha: 1)) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let cgImage = image.cgImage else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation(of: image), options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
                let buffer = try observation.generateMaskedImage(
                    ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
                let ciImage = CIImage(cvPixelBuffer: buffer)
                guard let cut = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
                return compose(UIImage(cgImage: cut), on: background)
            } catch {
                return nil
            }
        }.value
    }

    /// The subject centered on a square with ~8% margin.
    private static func compose(_ subject: UIImage, on background: UIColor) -> UIImage {
        let side = max(subject.size.width, subject.size.height) * 1.16
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let origin = CGPoint(x: (side - subject.size.width) / 2, y: (side - subject.size.height) / 2)
            subject.draw(in: CGRect(origin: origin, size: subject.size))
        }
    }

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
