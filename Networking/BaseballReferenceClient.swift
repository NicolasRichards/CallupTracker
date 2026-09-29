import Foundation

struct BaseballReferenceLookup {
    let status: BaseballReferenceClient.RookieStatus
    let retryAfterSeconds: Int?
}

struct BaseballReferenceClient {
    static let shared = BaseballReferenceClient()

    enum RookieStatus: String, Codable {
        case rookieEligible
        case exceededRookieLimits
        case rateLimited
    }

    // Actor serialises all reads and writes, eliminating the concurrent
    // read-modify-write race. Prunes prior-season entries on each write so
    // the UserDefaults blob doesn't grow unboundedly across seasons.
    private static let cache = BRefCacheStore()

    func hasCachedStatus(forMLBID mlbID: Int) async -> Bool {
        await Self.cache.get(mlbID: mlbID) != nil
    }

    // MARK: - Fetch

    func fetchRookieStatus(forMLBID mlbID: Int) async -> BaseballReferenceLookup {
        if let cached = await Self.cache.get(mlbID: mlbID) {
            return BaseballReferenceLookup(status: cached, retryAfterSeconds: nil)
        }

        guard let url = URL(string: "https://www.baseball-reference.com/redirect.fcgi?player=1&mlb_ID=\(mlbID)") else {
            return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Condition 1: explicit 429 with optional Retry-After header
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                return BaseballReferenceLookup(status: .rateLimited, retryAfterSeconds: retryAfter)
            }

            // Condition 2: any other non-2xx status (403, 503, etc.) — treat as rate limited
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return BaseballReferenceLookup(status: .rateLimited, retryAfterSeconds: nil)
            }

            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""

            let lowerHTML = html.lowercased()

            // Condition 3: 200 response but page content indicates blocking/rate limiting
            let rateLimitPhrases = ["rate limit", "too many requests", "unusual traffic",
                                    "captcha", "access denied", "you have been blocked",
                                    "please wait before", "temporarily unavailable"]
            if rateLimitPhrases.contains(where: { lowerHTML.contains($0) }) {
                return BaseballReferenceLookup(status: .rateLimited, retryAfterSeconds: nil)
            }

            if lowerHTML.contains("exceeded rookie limits") {
                await Self.cache.set(.exceededRookieLimits, mlbID: mlbID)
                return BaseballReferenceLookup(status: .exceededRookieLimits, retryAfterSeconds: nil)
            }

            // "still intact" or no rookie section — eligible either way
            await Self.cache.set(.rookieEligible, mlbID: mlbID)
            return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
        } catch {
            // Network error — treat as rate limited so we don't silently mis-classify
            return BaseballReferenceLookup(status: .rateLimited, retryAfterSeconds: nil)
        }
    }
}

// MARK: - Cache actor

// Serialises every cache read and write so concurrent BRef completions can't
// interleave their read-modify-write on the UserDefaults blob and silently
// drop each other's entries. Also prunes prior-season entries on each write.
private actor BRefCacheStore {
    private let defaultsKey = "brefRookieStatusCache"
    private let ttl: TimeInterval = 7 * 24 * 60 * 60

    private struct Entry: Codable {
        let status: BaseballReferenceClient.RookieStatus
        let timestamp: Date
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    func get(mlbID: Int) -> BaseballReferenceClient.RookieStatus? {
        let key = "\(mlbID)_\(currentYear)"
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let cache = try? JSONDecoder().decode([String: Entry].self, from: data),
            let entry = cache[key],
            Date().timeIntervalSince(entry.timestamp) < ttl
        else { return nil }
        return entry.status
    }

    func set(_ status: BaseballReferenceClient.RookieStatus, mlbID: Int) {
        let year = currentYear
        let key = "\(mlbID)_\(year)"
        var cache: [String: Entry] = [:]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let existing = try? JSONDecoder().decode([String: Entry].self, from: data) {
            // Drop entries from prior seasons so the blob doesn't grow indefinitely
            cache = existing.filter { $0.key.hasSuffix("_\(year)") }
        }
        cache[key] = Entry(status: status, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }
}
