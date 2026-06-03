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

    // MARK: - Cache

    // Cache rookie status per player per season year.
    // rateLimited results are never cached — always re-fetch those.
    // Cache expires after 7 days to pick up mid-season changes.
    private static let cacheKey = "brefRookieStatusCache"
    private static let cacheTTLSeconds: TimeInterval = 7 * 24 * 60 * 60

    private struct CachedEntry: Codable {
        let status: RookieStatus
        let timestamp: Date
    }

    private func cacheKey(for mlbID: Int) -> String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(mlbID)_\(year)"
    }

    private func cachedStatus(for mlbID: Int) -> RookieStatus? {
        guard
            let data = UserDefaults.standard.data(forKey: Self.cacheKey),
            let cache = try? JSONDecoder().decode([String: CachedEntry].self, from: data),
            let entry = cache[cacheKey(for: mlbID)],
            Date().timeIntervalSince(entry.timestamp) < Self.cacheTTLSeconds
        else { return nil }
        return entry.status
    }

    private func store(status: RookieStatus, for mlbID: Int) {
        let key = cacheKey(for: mlbID)
        var cache: [String: CachedEntry] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let existing = try? JSONDecoder().decode([String: CachedEntry].self, from: data) {
            cache = existing
        }
        cache[key] = CachedEntry(status: status, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
        }
    }

    // MARK: - Fetch

    func fetchRookieStatus(forMLBID mlbID: Int) async -> BaseballReferenceLookup {
        // Return cached result if available (never cache rateLimited)
        if let cached = cachedStatus(for: mlbID) {
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
                store(status: .exceededRookieLimits, for: mlbID)
                return BaseballReferenceLookup(status: .exceededRookieLimits, retryAfterSeconds: nil)
            }

            if lowerHTML.contains("still intact") {
                store(status: .rookieEligible, for: mlbID)
                return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
            }

            // No rookie status section on an otherwise valid page — player has no prior
            // MLB service time, so rookie status is intact by definition
            store(status: .rookieEligible, for: mlbID)
            return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
        } catch {
            // Network error — treat as rate limited so we don't silently mis-classify
            return BaseballReferenceLookup(status: .rateLimited, retryAfterSeconds: nil)
        }
    }
}
