//
//  GeminiService.swift
//  bilu

import Foundation

enum SearchFailure: Equatable {
    case noMatches       // server returned an empty result
    case rewardRequired  // server has no free or verified rewarded access left
    case purchaseRequired // server monthly and purchased balances are exhausted
    case pendingDiscovery // recover this job before starting paid work again
    case capacityUnavailable // upstream quota/spending cap is exhausted
    case usageLimitExceeded // per-user or global paid API budget is exhausted
    case timedOut        // the search exceeded the user-facing latency budget
    case offline         // the device has no usable network connection
    case sessionRejected // the session was still rejected after one refresh
    case transportError  // network / HTTP / decode failure
}

/// What the empty-results card offers for each failure. Kept beside the
/// failure type so copy stays distinct and testable without rendering a view.
enum SearchRecoveryAction: Equatable {
    case retry           // run the same search again
    case checkDiscovery  // recover a pending job without paying twice
    case viewDiscoveries // open the purchase gate
    case unlockWithAd    // open the rewarded-ad gate
    case adjustVibe      // go back and change the request
    case startOver       // nothing to retry right now; return to Explore
}

struct SearchRecoveryCopy: Equatable {
    let systemImage: String
    let title: String
    let message: String
    let action: SearchRecoveryAction
    let actionTitle: String

    /// `nil` means the search succeeded with results and no card is shown.
    init(failure: SearchFailure?) {
        switch failure {
        case .noMatches, nil:
            self.init("magnifyingglass", "Nothing matched, yet",
                      "Try a different vibe or widen your search — there's always something nearby worth trying.",
                      .adjustVibe, "Adjust your vibe")
        case .pendingDiscovery:
            self.init("arrow.triangle.2.circlepath", "Your discovery is still running",
                      "Check again to pick up this discovery. Your allowance won’t be used twice.",
                      .checkDiscovery, "Check discovery")
        case .rewardRequired:
            self.init("play.rectangle", "Unlock another discovery",
                      "Today's free discovery is used. Watch a short ad to unlock one more.",
                      .unlockWithAd, "Watch an ad")
        case .purchaseRequired:
            self.init("sparkles", "Ready for more discoveries?",
                      "View your discovery balance or add a Discovery Pass. Your choices are saved here.",
                      .viewDiscoveries, "View discoveries")
        case .usageLimitExceeded:
            self.init("gauge.with.dots.needle.67percent", "Search limit reached",
                      "This account has used its current search allowance. Please try again after the limit resets.",
                      .startOver, "Back to Explore")
        case .capacityUnavailable:
            self.init("hourglass", "Search is at capacity",
                      "Our search provider is temporarily at its limit. Give it a minute, then try again. This search wasn't counted.",
                      .retry, "Try again")
        case .timedOut:
            self.init("clock.arrow.circlepath", "Search took too long",
                      "We stopped waiting so you wouldn't be stuck here. This search wasn't counted — try again for a fresh one.",
                      .retry, "Try again")
        case .offline:
            self.init("wifi.slash", "You're offline",
                      "Check your internet connection, then try again. This search wasn't counted.",
                      .retry, "Try again")
        case .sessionRejected:
            self.init("person.crop.circle.badge.exclamationmark", "Couldn't verify this device",
                      "We refreshed your session but couldn't confirm it. Try again in a moment.",
                      .retry, "Try again")
        case .transportError:
            self.init("exclamationmark.triangle", "Couldn't reach us",
                      "Something went wrong on our end. Tap retry — usually works the second time.",
                      .retry, "Try again")
        }
    }

    private init(_ systemImage: String, _ title: String, _ message: String,
                 _ action: SearchRecoveryAction, _ actionTitle: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action
        self.actionTitle = actionTitle
    }
}

struct VibeFetchOutcome {
    let result: VibeResult
    let failure: SearchFailure?
}

enum GeminiService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    typealias RequestFactory = (_ path: String, _ timeout: TimeInterval) async throws -> URLRequest

    private static let emptyResult = VibeResult(recommendations: [], groundingPlaces: [], relaxed: nil)
    /// The server's Gemini deadline (RECOMMENDATIONS_DEADLINE_MS) and the
    /// budget for its auth and access checks that run before that deadline starts.
    static let serverRecommendationsDeadline: TimeInterval = 19
    static let serverPreflightBudget: TimeInterval = 5
    // Must outlast the server's access checks plus its 19 s Gemini deadline.
    // If the client gives up first, the server can still succeed and spend the
    // discovery while the results are lost; the server's own timeout refunds it.
    static let recommendationTimeout: TimeInterval = 30
    private static let enrichmentTimeout: TimeInterval = 8

    // Phase 1 — fast: Gemini recommendations only (no Places enrichment)
    static func getVibeRecommendations(
        selection: VibeSelection,
        rewardedAccessToken: String? = nil
    ) async -> VibeFetchOutcome {
        let prompt = PromptBuilder.getPrompt(selection: selection)
        var body: [String: Any] = [
            "occasion": selection.occasion,
            "vibe": selection.vibe,
            "hunger": selection.hunger,
            "location": selection.location,
            "googleSearch": selection.googleSearch,
            "thinkingLevel": selection.thinkingLevel,
            "prompt": prompt
        ]
        if selection.useRadiusSearch {
            body["radiusMiles"] = selection.radiusMiles
            if let lat = selection.latitude  { body["latitude"]  = lat }
            if let lng = selection.longitude { body["longitude"] = lng }
        }

        if PurchaseConfiguration.current.commerceEnabled {
            do {
                let result = try await DiscoveryJobService.shared.explore(input: body)
                return VibeFetchOutcome(result: result, failure: result.recommendations.isEmpty ? .noMatches : nil)
            } catch DiscoveryJobError.allowanceRequired {
                return VibeFetchOutcome(result: emptyResult, failure: .purchaseRequired)
            } catch DiscoveryJobError.pending {
                return VibeFetchOutcome(result: emptyResult, failure: .pendingDiscovery)
            } catch {
                return VibeFetchOutcome(result: emptyResult, failure: failure(for: error))
            }
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return VibeFetchOutcome(result: emptyResult, failure: .transportError)
        }
        return await fetchRecommendations(body: httpBody, rewardedAccessToken: rewardedAccessToken)
    }

    /// Sends one recommendations request. A 401 means the server rejected a
    /// token the device still considers fresh (revoked or rotated), so the
    /// token is dropped and the request is retried exactly once with a
    /// refreshed session. The server rejects auth before reserving access, so
    /// the retry cannot spend a discovery twice.
    static func fetchRecommendations(
        body: Data,
        rewardedAccessToken: String?,
        makeRequest: RequestFactory = { try await AuthenticatedAPIRequest.post(path: $0, timeout: $1) },
        invalidateToken: (String) async -> Void = { await SupabaseAuthSession.shared.invalidate(accessToken: $0) },
        transport: Transport = { try await URLSession.shared.data(for: $0) }
    ) async -> VibeFetchOutcome {
        var refreshedSession = false
        while true {
            do {
                var request = try await makeRequest("recommendations", recommendationTimeout)
                if let rewardedAccessToken {
                    request.setValue(rewardedAccessToken, forHTTPHeaderField: "X-Rewarded-Access-Token")
                }
                request.httpBody = body

                let (data, response) = try await transport(request)
                guard let http = response as? HTTPURLResponse else {
                    return VibeFetchOutcome(result: emptyResult, failure: .transportError)
                }
                if http.statusCode == 401 {
                    guard !refreshedSession else {
                        return VibeFetchOutcome(result: emptyResult, failure: .sessionRejected)
                    }
                    refreshedSession = true
                    let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
                    await invalidateToken(String(bearer.dropFirst("Bearer ".count)))
                    continue
                }
                guard (200...299).contains(http.statusCode) else {
                    #if DEBUG
                    print("[GeminiService] recommendations HTTP \(http.statusCode)")
                    #endif
                    struct ErrorResponse: Decodable { let code: String? }
                    let errorCode = try? JSONDecoder().decode(ErrorResponse.self, from: data).code
                    return VibeFetchOutcome(result: emptyResult,
                                            failure: failure(status: http.statusCode, code: errorCode))
                }
                let decoded = try JSONDecoder().decode(VibeResult.self, from: data)
                let failure: SearchFailure? = decoded.recommendations.isEmpty ? .noMatches : nil
                return VibeFetchOutcome(result: decoded, failure: failure)
            } catch {
                return VibeFetchOutcome(result: emptyResult, failure: failure(for: error))
            }
        }
    }

    static func failure(status: Int, code: String?) -> SearchFailure {
        switch (status, code) {
        case (503, "UPSTREAM_CAPACITY"), (429, "GLOBAL_BUDGET_EXCEEDED"): return .capacityUnavailable
        case (402, "REWARDED_AD_REQUIRED"): return .rewardRequired
        case (429, "USAGE_LIMIT_EXCEEDED"): return .usageLimitExceeded
        case (504, "UPSTREAM_TIMEOUT"): return .timedOut
        default: return .transportError
        }
    }

    static func failure(for error: Error) -> SearchFailure {
        if case SupabaseAuthError.rejected(let status, _) = error, status == 400 || status == 401 || status == 403 {
            // The refresh token itself was refused; the identity is kept, never replaced.
            return .sessionRejected
        }
        guard let urlError = error as? URLError else {
            return (error as NSError).code == NSURLErrorTimedOut ? .timedOut : .transportError
        }
        switch urlError.code {
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        default:
            return .transportError
        }
    }

    // Phase 2 — background: Places enrichment (photos + coordinates)
    static func enrichRecommendations(
        _ recommendations: [Recommendation],
        groundingPlaces: [GroundingPlace],
        location: String
    ) async -> [Recommendation] {
        var body: [String: Any] = [
            "recommendations": recommendations.map {
                ["name": $0.name, "dish": $0.dish, "image": $0.image ?? "",
                 "explanation": $0.explanation, "mapsUrl": $0.mapsUrl,
                 "parking": $0.parking ?? "Not confirmed"]
            },
            "groundingPlaces": groundingPlaces.map {
                ["placeId": $0.placeId, "title": $0.title, "uri": $0.uri]
            }
        ]
        if !location.isEmpty { body["location"] = location }

        do {
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                return []
            }
            var request = try await AuthenticatedAPIRequest.post(
                path: "enrich",
                timeout: enrichmentTimeout
            )
            request.httpBody = httpBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[GeminiService] enrich HTTP \(code): \(body)")
                #endif
                return []
            }
            let decoded = try JSONDecoder().decode(VibeResult.self, from: data)
            // Defense in depth: the backend filters too, but the app never
            // publishes a restaurant without an explicit open confirmation.
            return decoded.recommendations.verifiedOpenRecommendations
        } catch {
            return []
        }
    }

    // Phase 3 — lazy: fetch gallery photos for a place on demand
    static func fetchGalleryPhotos(placeId: String) async -> [String] {
        guard let body = try? JSONSerialization.data(withJSONObject: ["placeId": placeId]) else { return [] }

        do {
            var request = try await AuthenticatedAPIRequest.post(path: "photos", timeout: 20)
            request.httpBody = body
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            struct PhotosResponse: Decodable { let photos: [String] }
            let decoded = try JSONDecoder().decode(PhotosResponse.self, from: data)
            return decoded.photos
        } catch {
            return []
        }
    }
}
