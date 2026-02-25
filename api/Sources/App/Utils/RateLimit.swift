import Vapor

actor SlidingWindowRateLimiter {
    private var hits: [String: [Date]] = [:]

    func allow(key: String, limit: Int, window: TimeInterval, now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-window)
        var keyHits = (hits[key] ?? []).filter { $0 >= cutoff }
        if keyHits.count >= limit {
            hits[key] = keyHits
            return false
        }
        keyHits.append(now)
        hits[key] = keyHits
        return true
    }
}

let authRateLimiter = SlidingWindowRateLimiter()

private let trustForwardedForForRateLimit = (Environment.get("TRUST_X_FORWARDED_FOR") ?? "false")
    .lowercased() == "true"

private func isValidIPToken(_ candidate: String) -> Bool {
    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.")
    return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
}

private func clientIP(_ req: Request) -> String {
    if trustForwardedForForRateLimit,
       let forwarded = req.headers.first(name: .xForwardedFor)?
        .split(separator: ",")
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       isValidIPToken(forwarded) {
        return forwarded
    }
    return req.remoteAddress?.ipAddress ?? "unknown"
}

func enforceLoginRateLimit(_ req: Request, username: String) async throws {
    let key = "login:\(clientIP(req)):\(username.lowercased())"
    let allowed = await authRateLimiter.allow(key: key, limit: 15, window: 60)
    if !allowed {
        throw Abort(.tooManyRequests, reason: "too many login attempts")
    }
}

func enforcePasswordResetRequestRateLimit(_ req: Request) async throws {
    let key = "reset-request:\(clientIP(req))"
    let allowed = await authRateLimiter.allow(key: key, limit: 10, window: 60)
    if !allowed {
        throw Abort(.tooManyRequests, reason: "too many password reset requests")
    }
}

func enforcePasswordResetConfirmRateLimit(_ req: Request) async throws {
    let key = "reset-confirm:\(clientIP(req))"
    let allowed = await authRateLimiter.allow(key: key, limit: 20, window: 60)
    if !allowed {
        throw Abort(.tooManyRequests, reason: "too many password reset confirmations")
    }
}

func enforceInviteRegisterRateLimit(_ req: Request) async throws {
    let key = "invite-register:\(clientIP(req))"
    let allowed = await authRateLimiter.allow(key: key, limit: 20, window: 60)
    if !allowed {
        throw Abort(.tooManyRequests, reason: "too many invite registrations")
    }
}
