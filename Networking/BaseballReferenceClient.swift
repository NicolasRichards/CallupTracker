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

    func fetchRookieStatus(forMLBID mlbID: Int) async -> BaseballReferenceLookup {
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
                return BaseballReferenceLookup(status: .exceededRookieLimits, retryAfterSeconds: nil)
            }

            if lowerHTML.contains("still intact") {
                return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
            }

            // No rookie status section on an otherwise valid page — player has no prior
            // MLB service time, so rookie status is intact by definition
            return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
        } catch {
            // Network error — treat as rate limited so we don't silently mis-classify
            return BaseballReferenceLookup(status: .rateLimited, retryAfterSeconds: nil)
        }
    }
}
