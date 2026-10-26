import BunnListCore
import SwiftUI
import UIKit

/// The story card (1080×1920): the bag, its name and roaster, the taste
/// fingerprint, the sharer's stars and match, under the BunnList mark. Laid out
/// at 360×640 points and rendered at 3x.
struct ShareCardView: View {
    let lot: RemoteLotDetail
    let bag: UIImage?
    let myRating: Int?
    let matchScore: Int?

    private var notes: [String] { Array(lot.flavorNotes.prefix(3)) }

    private var glow: [Color] {
        let colors = notes.map(\.family.color)
        return colors.isEmpty ? [Brand.olive, Brand.gold] : colors + [Brand.gold]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.97, green: 0.95, blue: 0.91), Color(red: 0.93, green: 0.89, blue: 0.82)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [glow[0].opacity(0.35), .clear], center: .topTrailing, startRadius: 10, endRadius: 330)
            RadialGradient(colors: [glow[min(1, glow.count - 1)].opacity(0.3), .clear], center: .bottomLeading, startRadius: 10, endRadius: 330)

            VStack(spacing: 14) {
                HStack {
                    Image("BunnListSymbol").resizable().scaledToFit().frame(height: 26)
                    Text("BunnList").font(.system(size: 17, weight: .heavy, design: .rounded))
                    Spacer()
                    if let matchScore {
                        Text("تناسبني \(matchScore)٪")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color(red: 0.33, green: 0.39, blue: 0.27), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)

                ZStack {
                    RoundedRectangle(cornerRadius: 26).fill(Color(white: 0.97))
                    if let bag {
                        Image(uiImage: bag).resizable().scaledToFit().padding(18)
                    } else {
                        CoffeeArtCard(roaster: lot.roasterNameAr, name: lot.nameAr, origin: lot.originNameAr, originCode: lot.originCode)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                    }
                }
                .frame(height: 290)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

                VStack(spacing: 3) {
                    Text(lot.nameAr).font(.system(size: 28, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(lot.roasterNameAr).font(.system(size: 16, weight: .semibold)).foregroundStyle(.black.opacity(0.55))
                }

                if !notes.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                            HStack(spacing: 5) {
                                Circle().fill(note.family.color).frame(width: 9, height: 9)
                                Text(note).font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.7), in: Capsule())
                        }
                    }
                }

                HStack(spacing: 18) {
                    if let origin = lot.originNameAr { fact("المنشأ", origin) }
                    if let process = lot.processNameAr { fact("المعالجة", process) }
                }

                if let myRating {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= myRating ? "star.fill" : "star")
                                .font(.system(size: 20)).foregroundStyle(Color(red: 0.80, green: 0.60, blue: 0.20))
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }

                Spacer(minLength: 0)
                Text("اكتشف، قيّم، واختر أفضل محاصيل القهوة")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.55))
            }
            .padding(24)
            .foregroundStyle(Color(red: 0.09, green: 0.08, blue: 0.07))
        }
        .frame(width: 360, height: 640)
        .environment(\.colorScheme, .light)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.black.opacity(0.5))
            Text(value).font(.system(size: 15, weight: .bold))
        }
    }
}

private extension String {
    var family: FlavorFamily { FlavorFamily.of(self) }
}

/// Preview of the card with the share button. Downloads the bag photo first
/// (ImageRenderer can't wait for AsyncImage) and fetches the match if signed in.
@MainActor
struct ShareCardSheet: View {
    let lot: RemoteLotDetail
    let myRating: Int?

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private var link: URL { ServerConfig.baseURL.appendingPathComponent("coffees").appendingPathComponent(lot.slug) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let rendered {
                    Image(uiImage: rendered).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
                        .padding(.horizontal, 30)
                    ShareLink(item: Image(uiImage: rendered),
                              subject: Text(lot.nameAr),
                              message: Text("\(lot.nameAr) من \(lot.roasterNameAr) على بن لست \(link.absoluteString)"),
                              preview: SharePreview(lot.nameAr, image: Image(uiImage: rendered))) {
                        Label("شارك البطاقة", systemImage: "square.and.arrow.up")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.ink).foregroundStyle(Brand.background)
                    .clipShape(Capsule())
                    .padding(.horizontal, 30)
                    .accessibilityIdentifier("share-card")
                    ShareLink(item: link) { Label("أو شارك الرابط بس", systemImage: "link").font(.subheadline) }
                } else {
                    Spacer()
                    BrandMark(height: 80, looping: true)
                    Text("نجهّز بطاقتك…").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .brandScreen()
            .navigationTitle("شارك القهوة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .task { await render() }
        }
    }

    private func render() async {
        async let bag = loadBag()
        async let match = loadMatch()
        let (image, taste) = await (bag, match)
        let renderer = ImageRenderer(content: ShareCardView(lot: lot, bag: image, myRating: myRating, matchScore: taste?.score))
        renderer.scale = 3
        rendered = renderer.uiImage
    }

    private func loadBag() async -> UIImage? {
        guard let url = lot.imageUrl.flatMap(URL.init(string:)),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    private func loadMatch() async -> RemoteTasteMatch? {
        guard auth.isSignedIn else { return nil }
        return try? await auth.withToken { try await client.fetchTasteMatch(slug: lot.slug, accessToken: $0) }
    }
}
