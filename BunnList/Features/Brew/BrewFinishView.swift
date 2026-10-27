import BunnListCore
import SwiftUI

/// «كيف طلعت؟» after a brew: optional. With stars it saves a brew experience
/// (private unless published), which is what earns its points and passport stamp
/// under the usual rules; without stars, nothing is saved.
@MainActor
struct BrewFinishView: View {
    let ref: BrewFinishRef

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var stars = 0
    @State private var tastes: [String] = []
    @State private var note = ""
    @State private var publish = false
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private static let tasteWords = ["حلوة", "متوازنة", "حامضة", "مرّة", "خفيفة", "ثقيلة"]

    var body: some View {
        NavigationStack {
            Group {
                if saved { savedView } else { form }
            }
            .brandScreen()
            .navigationTitle("كيف طلعت؟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !saved {
                    ToolbarItem(placement: .cancellationAction) { Button("تخطّي") { dismiss() } }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var form: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text(ref.coffeeName).font(.headline)
                    Text("\(RecipeText.method(ref.plan.methodCode))\(ref.seconds > 0 ? " · " + RecipeText.duration(ref.seconds) : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { n in
                            Button { stars = stars == n ? 0 : n } label: {
                                Image(systemName: n <= stars ? "star.fill" : "star")
                                    .font(.system(size: 34)).foregroundStyle(n <= stars ? Brand.gold : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(n) نجوم")
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .sensoryFeedback(.selection, trigger: stars)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
            }
            Section("بكلمة") {
                FlowChips(words: Self.tasteWords, selected: $tastes)
                TextField("ملاحظة (اختياري)", text: $note, axis: .vertical).lineLimit(1...4)
            }
            Section {
                Toggle("انشرها مع تجارب هالقهوة", isOn: $publish).tint(Brand.olive)
            } footer: {
                Text("التقييم اختياري. بدون نجوم ما نحفظ شي، وتقدر تتخطّى.")
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            Section {
                Button { Task { await save() } } label: {
                    Text(isSaving ? "نحفظ…" : "حفظ التجربة").font(.headline).frame(maxWidth: .infinity)
                }
                .disabled(stars == 0 || isSaving)
            }
        }
    }

    private var savedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Brand.olive)
                .symbolEffect(.bounce, value: saved)
            Text("انحفظت تجربتك").font(.title2.bold())
            Text("تلقاها في صفحة القهوة، وتحسب في نقاطك وجوازك حسب القواعد.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("تم") { dismiss() }.buttonStyle(.borderedProminent).tint(Brand.olive).padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: saved)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let text = (tastes + [note.trimmingCharacters(in: .whitespacesAndNewlines)]).filter { !$0.isEmpty }.joined(separator: " · ")
        do {
            _ = try await auth.withToken {
                try await client.saveExperience(slug: ref.slug, accessToken: $0, clientID: UUID().uuidString,
                                                methodCode: ref.plan.methodCode, stars: stars, brewedAt: Date(),
                                                note: text, publish: publish)
            }
            withAnimation { saved = true }
        } catch APIError.forbidden {
            errorMessage = "حسابك موقوف عن النشر حاليًا."
        } catch {
            errorMessage = "ما انحفظت. حاول مرة ثانية."
        }
    }
}

/// Tap-to-toggle word chips that wrap.
private struct FlowChips: View {
    let words: [String]
    @Binding var selected: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(words, id: \.self) { word in
                let on = selected.contains(word)
                Button {
                    if on { selected.removeAll { $0 == word } } else { selected.append(word) }
                } label: {
                    Text(word).font(.subheadline.bold())
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(on ? Brand.olive : Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(on ? Brand.background : Brand.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
