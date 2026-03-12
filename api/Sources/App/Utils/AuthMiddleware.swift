import Vapor
import Fluent

struct AuthenticatedUserKey: StorageKey {
    typealias Value = User
}

struct BearerTokenMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let header = req.headers.bearerAuthorization else {
            throw Abort(.unauthorized)
        }

        let tokenHash = sha256Hex(header.token)
        let now = Date()

        guard let token = try await APIToken.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .filter(\.$expiresAt > now)
            .with(\.$user)
            .first()
        else {
            throw Abort(.unauthorized)
        }

        req.storage[AuthenticatedUserKey.self] = token.user
        return try await next.respond(to: req)
    }
}

func requireAuthenticatedUser(_ req: Request) throws -> User {
    guard let user = req.storage[AuthenticatedUserKey.self] else {
        throw Abort(.unauthorized)
    }
    return user
}

func requireAdminOrSuperAdmin(_ req: Request) throws -> User {
    let user = try requireAuthenticatedUser(req)
    switch user.role {
    case .admin, .superAdmin:
        return user
    case .guest, .member:
        throw Abort(.forbidden)
    }
}

func requireNonGuestUser(_ req: Request) throws -> User {
    let user = try requireAuthenticatedUser(req)
    guard user.role != .guest else {
        throw Abort(.forbidden)
    }
    return user
}

func requireSuperAdmin(_ req: Request) throws -> User {
    let user = try requireAuthenticatedUser(req)
    guard user.role == .superAdmin else {
        throw Abort(.forbidden)
    }
    return user
}
