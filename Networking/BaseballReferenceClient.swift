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

            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                return BaseballReferenceLookup(status: .rateLimited, retryAfterSeconds: retryAfter)
            }

            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""

            let lowerHTML = html.lowercased()

            if lowerHTML.contains("exceeded rookie limits") {
                return BaseballReferenceLookup(status: .exceededRookieLimits, retryAfterSeconds: nil)
            }

            if lowerHTML.contains("still intact") {
                return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
            }

            // No rookie status section found — default to eligible (e.g. truly first MLB appearance)
            return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
        } catch {
            return BaseballReferenceLookup(status: .rookieEligible, retryAfterSeconds: nil)
        }
    }
}
