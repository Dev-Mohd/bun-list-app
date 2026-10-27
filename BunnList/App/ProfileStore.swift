import BunnListCore
import SwiftUI

/// The signed-in account's profile (/api/v1/me), shared by the first-run setup and
/// the profile tab so both always show the same name, picture and status.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var me: RemoteMe?
    /// True while fetching; the app shows the drawing mark until the first profile arrives.
    @Published private(set) var isLoading = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    func refresh(_ auth: AuthModel) async {
        guard auth.isSignedIn else { me = nil; return }
        isLoading = true
        defer { isLoading = false }
        if let fresh = try? await auth.withToken({ try await client.fetchMe(accessToken: $0) }) {
            me = fresh
            // «مطحنتي» from the profile wins over the phone's copy.
            if let grinderID = fresh.grinderId { UserDefaults.standard.set(grinderID, forKey: MyGrinder.key) }
        }
    }

    func clear() { me = nil }
}

/// A round profile picture, or initials / a person glyph when there is none.
struct AvatarView: View {
    let url: String?
    var image: UIImage?
    var name: String?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { $0.resizable().scaledToFill() } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Brand.gold.opacity(0.5), lineWidth: 2))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Circle().fill(Brand.olive.opacity(0.15)).overlay {
            if let initial = name?.trimmingCharacters(in: .whitespaces).first {
                Text(String(initial)).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Brand.olive)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.4)).foregroundStyle(Brand.olive)
            }
        }
    }
}

enum AvatarImage {
    /// Center-cropped square, 512 px, JPEG 0.85: small to upload, sharp at profile sizes.
    static func jpeg(from image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let target = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            let scale = target.width / side
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        return square.jpegData(compressionQuality: 0.85)
    }
}
