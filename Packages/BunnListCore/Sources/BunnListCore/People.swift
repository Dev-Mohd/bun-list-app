import Foundation

// Finding people and private accounts: search, suggestions, the «أتابعهم» feed, a
// person's coffee shelves, and follow requests for a private account.

/// Where the viewer stands with someone.
public enum FollowState: Equatable, Sendable {
    case none, requested, following

    public init(following: Bool, requested: Bool) {
        self = following ? .following : requested ? .requested : .none
    }

    /// The follow button's label: «تابِع», «طلبت», «تتابعه».
    public var buttonAr: String {
        switch self {
        case .none: return "تابِع"
        case .requested: return "طلبت المتابعة"
        case .following: return "تتابعه"
        }
    }
}

public struct RemotePersonCard: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: String { username }
    public let username: String
    public let displayName: String?
    public let avatarUrl: String?
    public let isPrivate: Bool
    public let isFollowing: Bool
    public let requested: Bool
    /// Why they're suggested ("جربتوا ٤ قهاوي نفسها"); nil in search.
    public let reasonAr: String?

    public var followState: FollowState { FollowState(following: isFollowing, requested: requested) }
}

public struct RemoteSuggestedPeople: Codable, Equatable, Sendable {
    public let similar: [RemotePersonCard]
    public let active: [RemotePersonCard]

    public init(similar: [RemotePersonCard], active: [RemotePersonCard]) {
        self.similar = similar; self.active = active
    }
}

/// A person's coffee shelves.
public enum CoffeeShelf: String, CaseIterable, Sendable, Identifiable {
    case owned, tried, favorite, wantsToTry
    public var id: String { rawValue }

    public var nameAr: String {
        switch self {
        case .owned: return "عندي"
        case .tried: return "جرّبتها"
        case .favorite: return "المفضلة"
        case .wantsToTry: return "أبي أجربها"
        }
    }

    public func contains(_ item: RemoteCollectionItem) -> Bool {
        switch self {
        case .owned: return item.owned
        case .tried: return item.tried
        case .favorite: return item.favorite
        case .wantsToTry: return item.wantsToTry
        }
    }
}

public struct RemotePersonCoffees: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public let owned: Int
        public let tried: Int
        public let favorite: Int
        public let wantsToTry: Int

        public init(owned: Int, tried: Int, favorite: Int, wantsToTry: Int) {
            self.owned = owned; self.tried = tried; self.favorite = favorite; self.wantsToTry = wantsToTry
        }

        public subscript(shelf: CoffeeShelf) -> Int {
            switch shelf {
            case .owned: return owned
            case .tried: return tried
            case .favorite: return favorite
            case .wantsToTry: return wantsToTry
            }
        }
    }

    public let counts: Counts
    public let coffees: [RemoteCollectionItem]
}

extension CatalogAPIClient {
    private static func peoplePath(_ username: String) -> String {
        "/api/v1/users/" + (username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String, _ accessToken: String?) async throws -> T {
        let response = try await transport.send(HTTPRequest(method: .get, path: path, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func searchPeople(_ query: String, accessToken: String?) async throws -> [RemotePersonCard] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=@"))) ?? ""
        struct Wrapper: Decodable { let people: [RemotePersonCard] }
        return try await get(Wrapper.self, "/api/v1/users/search?q=\(q)", accessToken).people
    }

    public func suggestedPeople(accessToken: String) async throws -> RemoteSuggestedPeople {
        try await get(RemoteSuggestedPeople.self, "/api/v1/users/suggested", accessToken)
    }

    /// «أتابعهم»: what the people you follow did lately.
    public func followingFeed(accessToken: String) async throws -> [RemotePulseItem] {
        struct Wrapper: Decodable { let items: [RemotePulseItem] }
        return try await get(Wrapper.self, "/api/v1/community/following", accessToken).items
    }

    /// Throws `APIError.forbidden` when their coffees are kept from you (a private account you don't follow).
    public func personCoffees(_ username: String, shelf: CoffeeShelf, accessToken: String?) async throws -> RemotePersonCoffees {
        try await get(RemotePersonCoffees.self, Self.peoplePath(username) + "/coffees?shelf=\(shelf.rawValue)", accessToken)
    }

    public func followRequests(accessToken: String) async throws -> [RemotePerson] {
        struct Wrapper: Decodable { let people: [RemotePerson] }
        return try await get(Wrapper.self, "/api/v1/me/follow-requests", accessToken).people
    }

    public func answerFollowRequest(username: String, accept: Bool, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: ["accept": accept])) ?? Data()
        let path = "/api/v1/me/follow-requests/" + (username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)
        let response = try await transport.send(HTTPRequest(method: .post, path: path, body: data, bearer: accessToken))
        try Self.checkContract(response)
    }

    /// Takes someone off your followers; they aren't told.
    public func removeFollower(username: String, accessToken: String) async throws {
        let path = "/api/v1/me/followers/" + (username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)
        let response = try await transport.send(HTTPRequest(method: .delete, path: path, bearer: accessToken))
        try Self.checkContract(response)
    }

    public func setPrivate(_ isPrivate: Bool, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: ["isPrivate": isPrivate])) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .patch, path: "/api/v1/me/profile", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }
}
