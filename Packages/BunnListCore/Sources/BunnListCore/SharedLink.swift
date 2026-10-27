import Foundation

/// Links the app shares and opens: bunnlist.com/coffees/<slug> (Universal Links).
public enum SharedLink {
    public static let hosts: Set<String> = ["bunnlist.com", "www.bunnlist.com"]

    /// The coffee a shared link points at, or nil when it isn't one of ours.
    public static func coffeeSlug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "coffees" else { return nil }
        let slug = parts[1]
        guard !slug.isEmpty, slug.count <= 200,
              slug.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" }) else { return nil }
        return slug
    }
}
