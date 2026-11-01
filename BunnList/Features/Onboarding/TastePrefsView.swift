import BunnListCore
import SwiftUI

/// First run, step two: «وش تحب في قهوتك؟» Pick flavour families and how you brew;
/// the catalog's «لك» order puts coffees close to these first. Both are optional.
@MainActor
struct TastePrefsView: View {
    enum Mode { case firstRun, settings }
    var mode: Mode = .firstRun
    var onDone: () -> Void = {}

    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var families: Set<FlavorFamily> = []
    @State private var brews: Set<String> = []
    @State private var isSaving = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private let flavorColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let brewColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var hasPicks: Bool { !families.isEmpty || !brews.isEmpty }
    /// Settings may clear everything (back to a plain daily shuffle).
    private var canSave: Bool { mode == .settings || hasPicks }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    if mode == .firstRun { Text("وش تحب في قهوتك؟").font(.title.bold()) }
                    Text("اختر النكهات اللي تشدّك، ونرتّب لك القهاوي على ذوقك.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: flavorColumns, spacing: 10) {
                    ForEach(TastePrefs.families, id: \.self) { family in
                        FlavorPrefTile(family: family, isOn: families.contains(family)) {
                            if families.contains(family) { families.remove(family) } else { families.insert(family) }
                            Haptics.tap()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("وش تستخدم؟").font(.headline)
                    LazyVGrid(columns: brewColumns, spacing: 10) {
                        ForEach(TastePrefs.brews) { brew in
                            let on = brews.contains(brew.code)
                            Button {
                                if on { brews.remove(brew.code) } else { brews.insert(brew.code) }
                                Haptics.tap()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: brew.symbol).font(.title3)
                                    Text(brew.nameAr).font(.caption.bold()).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 66)
                                .foregroundStyle(on ? Color.white : Brand.ink)
                                .background(on ? Brand.olive : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button { Task { await save() } } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(mode == .firstRun ? "التالي" : "حفظ")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(canSave ? Brand.olive : Color.secondary.opacity(0.4), in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving)
                .accessibilityIdentifier("taste-prefs-next")
                if mode == .firstRun {
                    Button("تخطّي") { onDone() }.font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(mode == .settings ? "ذوقي" : "")
        .onAppear {
            guard mode == .settings, families.isEmpty, brews.isEmpty, let me = profile.me else { return }
            families = Set((me.tastePrefs ?? []).compactMap(FlavorFamily.init(rawValue:)))
            brews = Set(me.brewPrefs ?? [])
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let picked = TastePrefs.families.filter { families.contains($0) }
        let methods = TastePrefs.brews.map(\.code).filter { brews.contains($0) }
        // A failed save shouldn't block signup; the order just stays a daily shuffle.
        _ = try? await auth.withToken { try await client.updateTastePrefs(families: picked, brews: methods, accessToken: $0) }
        if mode == .settings {
            await profile.refresh(auth)
            Haptics.tap()
            dismiss()
        }
        onDone()
    }
}

/// A flavour family as a tappable tile: its colour as a soft blob, the short name.
private struct FlavorPrefTile: View {
    let family: FlavorFamily
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(family.color.opacity(isOn ? 1 : 0.25)).frame(width: 34, height: 34)
                    if isOn {
                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                    }
                }
                .scaleEffect(isOn ? 1.08 : 1)
                Text(family.shortNameAr).font(.caption.bold()).foregroundStyle(Brand.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isOn ? family.color : .clear, lineWidth: 2))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.nameAr)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
