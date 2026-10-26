import BunnListCore
import SwiftUI

/// A coffee's picture on a soft wash of its main flavor's color. The bag photos
/// sit on white, and multiplying them over the wash lets the white take the
/// tint, so the bag looks printed on the card; without a photo, the drawn card.
struct LotPhotoWell: View {
    let imageUrl: String?
    let notes: [String]
    let roaster: String
    let name: String
    let origin: String?
    let originCode: String?
    var padding: CGFloat = 4

    private var wash: Color {
        let family = FlavorFamily.dominant(notes)
        return family == .other ? Brand.gold : family.color
    }

    var body: some View {
        if let url = imageUrl.flatMap(URL.init(string:)) {
            ZStack {
                // Always a light ground, also in dark mode, so the multiply keeps the bag's own colors.
                Color.white
                wash.opacity(0.16)
                LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit().padding(padding).blendMode(.multiply)
                } placeholder: {
                    ProgressView().tint(wash)
                }
            }
            .compositingGroup()
        } else {
            CoffeeArtCard(roaster: roaster, name: name, origin: origin, originCode: originCode)
        }
    }
}
