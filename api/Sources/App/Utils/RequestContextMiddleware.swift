import Vapor

private struct RequestIDKey: StorageKey {
    typealias Value = String
}

struct RequestContextMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let incoming = req.headers.first(name: "X-Request-ID")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = (incoming?.isEmpty == false) ? incoming! : UUID().uuidString
        req.storage[RequestIDKey.self] = requestID
        req.logger[metadataKey: "request_id"] = .string(requestID)

        let start = Date()
        do {
            let response = try await next.respond(to: req)
            response.headers.replaceOrAdd(name: "X-Request-ID", value: requestID)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            req.logger.info("\(req.method.rawValue) \(req.url.path) -> \(response.status.code) (\(durationMs)ms)")
            return response
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            req.logger.error("\(req.method.rawValue) \(req.url.path) failed after \(durationMs)ms: \(error)")
            throw error
        }
    }
}
