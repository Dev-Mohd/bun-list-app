import BunnListCore
import MapKit
import SwiftUI

/// «خريطة المناطق»: each producing country as a bubble sized by how many coffees we
/// list; green once you've tried one from there. Tap a bubble for what it tastes
/// like, its regions, and its coffees.
@MainActor
struct OriginsMapView: View {
    /// Opens the catalog filtered to one origin (ISO code).
    var openOrigin: (String) -> Void

    @EnvironmentObject private var auth: AuthModel
    @State private var data: RemoteOrigins?
    @State private var failed = false
    @State private var selected: RemoteOrigin?
    @State private var appeared = false
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 8, longitude: 10),
                           span: MKCoordinateSpan(latitudeDelta: 110, longitudeDelta: 200))
    )

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private struct MapPoint: Identifiable {
        let origin: RemoteOrigin
        let point: OriginCentroids.Point
        var id: String { origin.code }
    }

    private var points: [MapPoint] {
        (data?.origins ?? []).compactMap { o in o.coordinate.map { MapPoint(origin: o, point: $0) } }
    }

    var body: some View {
        Map(position: $position) {
            ForEach(points) { item in
                Annotation(item.origin.nameAr, coordinate: CLLocationCoordinate2D(latitude: item.point.lat, longitude: item.point.lon), anchor: .center) {
                    Button {
                        Haptics.tap()
                        selected = item.origin
                    } label: {
                        OriginBubble(origin: item.origin, isSelected: selected?.code == item.origin.code)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(appeared ? 1 : 0.1)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(Double(item.origin.lots % 7) * 0.05), value: appeared)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .overlay(alignment: .top) { header }
        .overlay {
            if data == nil {
                if failed {
                    ContentUnavailableView {
                        Label("تعذّر التحميل", systemImage: "wifi.exclamationmark")
                    } actions: { Button("إعادة المحاولة") { Task { await load() } } }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(40)
                } else {
                    ProgressView().padding().background(.regularMaterial, in: Circle())
                }
            }
        }
        .navigationTitle("خريطة المناطق")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { origin in
            OriginSheet(origin: origin) {
                selected = nil
                openOrigin(origin.code)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { if data == nil { await load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let line = data?.progressLine {
                Text(line).font(.headline).foregroundStyle(Brand.ink)
            } else if let data {
                Text("قهاوي من \(points.count.formatted()) دولة").font(.headline)
                    .accessibilityLabel("قهاوي من \(data.origins.count) دولة")
            }
            HStack(spacing: 14) {
                legend(Brand.olive, "جرّبت منها")
                legend(Brand.gold, "لسّا ما جرّبت")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
        .opacity(data == nil ? 0 : 1)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 10, height: 10); Text(text) }
    }

    private func load() async {
        failed = false
        do {
            data = try await client.fetchOrigins(accessToken: auth.currentAccessToken())
            appeared = true
        } catch {
            failed = data == nil
        }
    }
}

/// A country's bubble: bigger with more coffees, green once tried.
private struct OriginBubble: View {
    let origin: RemoteOrigin
    let isSelected: Bool

    private var tried: Bool { (origin.tried ?? 0) > 0 }
    private var size: CGFloat { min(64, 28 + sqrt(CGFloat(origin.lots)) * 3) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill((tried ? Brand.olive : Brand.gold).opacity(0.25)).frame(width: size + 10, height: size + 10)
                Circle().fill(tried ? Brand.olive : Brand.gold).frame(width: size, height: size)
                if tried {
                    Image(systemName: "checkmark").font(.system(size: size * 0.32, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Text(origin.lots.formatted()).font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.white)
                }
            }
            .scaleEffect(isSelected ? 1.15 : 1)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Text(origin.nameAr)
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(origin.nameAr)، \(origin.lots) قهوة\(tried ? "، جرّبت منها" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// One country: its coffees in numbers, what they taste like, where from, and a way in.
private struct OriginSheet: View {
    let origin: RemoteOrigin
    var showCoffees: () -> Void

    private var families: [FlavorFamily] { origin.families.compactMap { FlavorFamily(rawValue: $0.key) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(origin.nameAr).font(.title.bold())
                    if let flag = ReferenceCodes.flag(origin.code) { Text(flag).font(.title) }
                    Spacer()
                    if let tried = origin.tried, tried > 0 {
                        Label("جرّبت \(tried.formatted())", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.bold()).foregroundStyle(Brand.olive)
                    }
                }
                HStack(spacing: 10) {
                    tile(origin.lots.formatted(), "قهوة")
                    tile(origin.roasters.formatted(), "محمصة")
                    tile(origin.averageRating > 0 ? origin.averageRating.formatted(.number.precision(.fractionLength(1))) : "—", "التقييم")
                }
                if !families.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("طعمها غالبًا").font(.headline)
                        RoasterChips(items: families.map(\.shortNameAr), colors: families.map(\.color))
                    }
                }
                if !origin.processes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("المعالجة").font(.headline)
                        RoasterChips(items: origin.processes.map { ReferenceCodes.process($0.key)?.nameAr ?? $0.key })
                    }
                }
                if !origin.regions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("المناطق").font(.headline)
                        RoasterChips(items: origin.regions)
                    }
                }
                Button(action: showCoffees) {
                    Text("شوف قهاويها (\(origin.lots.formatted()))")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(Brand.olive, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(Brand.brown)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
