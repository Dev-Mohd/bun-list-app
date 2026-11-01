import Foundation

/// Links the app shares and opens: bunnlist.com/coffees/<slug> and /lists/<id> (Universal Links).
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

    /// The list a shared link points at.
    public static func listID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "lists" else { return nil }
        let id = parts[1]
        guard !id.isEmpty, id.count <= 64, id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return nil }
        return id
    }

    public static func listURL(_ id: String) -> URL {
        URL(string: "https://bunnlist.com/lists/\(id)")!
    }
}
