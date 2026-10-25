import BunnListCore
import CoreImage
import SwiftUI
import UIKit
import Vision

/// The on-device product-photo pipeline. Real photos only: Core Image's automatic
/// adjustments fix light, color and tilt, Vision lifts the bag out of its
/// background, a light sharpen restores edges, and the bag is centered on a plain
/// square card. Nothing is generated. Returns nil when no clear subject is found
/// (or on the simulator, which lacks the Neural Engine).
enum BagCutout {
    struct Result {
        let image: UIImage
        /// Why a retake would give a better catalog photo; empty when the shot is good.
        let issues: [BagPhotoIssue]
    }

    static func cardImage(from image: UIImage) async -> UIImage? {
        await process(image)?.image
    }

    static func process(_ image: UIImage, background: UIColor = UIColor(white: 0.97, alpha: 1)) async -> Result? {
        await Task.detached(priority: .userInitiated) { () -> Result? in
            guard let cgImage = image.cgImage else { return nil }
            let context = CIContext()

            // 1. Enhance the real photo: exposure, color balance and straightening.
            var enhanced = CIImage(cgImage: cgImage).oriented(orientation(of: image))
            for filter in enhanced.autoAdjustmentFilters(options: [.redEye: false, .level: true]) {
                filter.setValue(enhanced, forKey: kCIInputImageKey)
                if let output = filter.outputImage { enhanced = output }
            }
            guard let enhancedCG = context.createCGImage(enhanced, from: enhanced.extent) else { return nil }

            // 2. Find the bag and lift it out.
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: enhancedCG, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
                let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
                let cut = try observation.generateMaskedImage(
                    ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)

                // 3. Restore a little crispness lost to resizing and compression.
                let sharpened = CIImage(cvPixelBuffer: cut)
                    .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.4])
                guard let cutCG = context.createCGImage(sharpened, from: sharpened.extent) else { return nil }

                // 4. Judge the shot.
                let box = boundingBox(of: CIImage(cvPixelBuffer: mask), context: context)
                let issues = box.map {
                    BagPhotoCheck.issues(box: $0, photoWidth: Double(enhancedCG.width), photoHeight: Double(enhancedCG.height),
                                         sharpness: sharpness(of: sharpened, context: context))
                } ?? []
                return Result(image: compose(UIImage(cgImage: cutCG), on: background), issues: issues)
            } catch {
                return nil
            }
        }.value
    }

    /// The bag's extent as fractions of the photo, read from a 64×64 copy of the mask.
    private static func boundingBox(of mask: CIImage, context: CIContext) -> BagPhotoCheck.Box? {
        let side = 64
        let extent = mask.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scaled = mask.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / extent.width, y: CGFloat(side) / extent.height))
        var pixels = [UInt8](repeating: 0, count: side * side)
        context.render(scaled, toBitmap: &pixels, rowBytes: side, bounds: CGRect(x: 0, y: 0, width: side, height: side),
                       format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where pixels[y * side + x] > 127 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let s = Double(side)
        return BagPhotoCheck.Box(minX: Double(minX) / s, minY: Double(minY) / s, maxX: Double(maxX + 1) / s, maxY: Double(maxY + 1) / s)
    }

    /// Mean edge strength (0…1) inside the bag, away from its outline.
    private static func sharpness(of cutout: CIImage, context: CIContext) -> Double? {
        let inner = cutout.extent.insetBy(dx: cutout.extent.width * 0.2, dy: cutout.extent.height * 0.2)
        guard inner.width > 8, inner.height > 8 else { return nil }
        let edges = cutout.cropped(to: inner)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
            .applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: inner)])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(edges, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return Double(pixel[0]) / 255
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

/// A coffee without a photo, drawn from its own data - never generated: the roaster
/// in large type over a tone picked by origin region, with origin and name below.
struct CoffeeArtCard: View {
    let roaster: String
    let name: String
    var origin: String?
    var originCode: String?
    var compact = false

    private var tone: (top: Color, bottom: Color, ink: Color) {
        switch CoffeeArtTone.forOrigin(originCode) {
        case .africa: return (Brand.gold.opacity(0.55), Brand.brown.opacity(0.55), Brand.ink)
        case .latinAmerica: return (Brand.olive.opacity(0.45), Brand.olive.opacity(0.8), .white)
        case .arabia: return (Brand.brown.opacity(0.75), Brand.ink.opacity(0.85), Brand.gold)
        case .asia: return (Brand.olive.opacity(0.25), Brand.brown.opacity(0.5), Brand.ink)
        case .other: return (Brand.gold.opacity(0.2), Brand.olive.opacity(0.35), Brand.ink)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [tone.top, tone.bottom], startPoint: .top, endPoint: .bottom)
            VStack(spacing: compact ? 2 : 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(compact ? .caption : .title3)
                    .opacity(0.7)
                Text(roaster)
                    .font(compact ? .caption2.bold() : .headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if !compact {
                    Text(name).font(.caption).opacity(0.85).lineLimit(1)
                    if let origin { Text(origin).font(.caption2.weight(.semibold)).opacity(0.75) }
                }
            }
            .foregroundStyle(tone.ink)
            .padding(compact ? 4 : 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) من \(roaster)")
    }
}
