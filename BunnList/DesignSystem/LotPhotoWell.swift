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

    /// Set by CardPressStyle while the card is held: the bag lifts off the card.
    @Environment(\.cardPressed) private var pressed

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
                // A soft shadow on the card that spreads as the bag lifts.
                Ellipse()
                    .fill(.black.opacity(pressed ? 0.10 : 0.16))
                    .frame(width: 70, height: 10)
                    .scaleEffect(pressed ? 1.25 : 1)
                    .blur(radius: pressed ? 8 : 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, padding + 2)
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.35))) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit().padding(padding).blendMode(.multiply)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(wash.opacity(0.6))
                    default:
                        ProgressView().tint(wash)
                    }
                }
                .scaleEffect(pressed ? 1.06 : 1)
                .offset(y: pressed ? -6 : 0)
                .rotation3DEffect(.degrees(pressed ? 4 : 0), axis: (x: 1, y: 0, z: 0))
            }
            .compositingGroup()
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
        } else {
            CoffeeArtCard(roaster: roaster, name: name, origin: origin, originCode: originCode)
        }
    }
}
