import BunnListCore
import SwiftUI

/// "يناسبك ٨٧٪" on every card: cards ask for their slug as they appear, and the
/// asks are gathered into one request a moment later. Answers are kept for a few
/// minutes, so new ratings show up on the next pass.
@MainActor
final class MatchScores: ObservableObject {
    /// One store for the whole app, so any card can show its score without wiring.
    static let shared = MatchScores()

    @Published private(set) var scores: [String: Int] = [:]
    /// Ratings still needed before any score shows; nil until known.
    @Published private(set) var needed: Int?

    private var askedAt: [String: Date] = [:]
    private var pending = Set<String>()
    private var flush: Task<Void, Never>?
    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private let freshFor: TimeInterval = 300

    func want(_ slug: String, auth: AuthModel) {
        guard auth.isSignedIn else { return }
        if let at = askedAt[slug], Date().timeIntervalSince(at) < freshFor { return }
        askedAt[slug] = Date()
        pending.insert(slug)
        flush?.cancel()
        flush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.send(auth: auth)
        }
    }

    /// Forget everything (sign-out, or after rating so scores recompute).
    func reset() {
        scores = [:]
        needed = nil
        askedAt = [:]
        pending = []
    }

    private func send(auth: AuthModel) async {
        let slugs = Array(pending)
        pending = []
        guard !slugs.isEmpty else { return }
        do {
            let result = try await auth.withToken { try await self.client.fetchMatchScores(slugs: slugs, accessToken: $0) }
            needed = result.needed
            scores.merge(result.scores) { _, new in new }
        } catch {
            slugs.forEach { askedAt[$0] = nil }
        }
    }
}
