import Vapor
import Fluent

func login(_ req: Request) async throws -> LoginResponseDTO {
    let body = try req.content.decode(LoginRequestDTO.self)
    try await enforceLoginRateLimit(req, username: body.username)

    guard let user = try await User.query(on: req.db)
        .filter(\.$username == body.username)
        .first()
    else {
        throw Abort(.unauthorized)
    }

    guard try Bcrypt.verify(body.password, created: user.passwordHash) else {
        throw Abort(.unauthorized)
    }

    guard let userID = user.id else {
        throw Abort(.internalServerError)
    }

    let rawToken = generateOpaqueToken()
    let tokenHash = sha256Hex(rawToken)

    let ttlHours = Int(Environment.get("API_TOKEN_TTL_HOURS") ?? "168") ?? 168
    let expiresAt = Date().addingTimeInterval(TimeInterval(60 * 60 * ttlHours))

    let token = APIToken(userID: userID, tokenHash: tokenHash, expiresAt: expiresAt)
    try await token.save(on: req.db)

    return .init(token: rawToken, userId: userID, username: user.username, role: user.role)
}

func me(_ req: Request) async throws -> MeResponseDTO {
    let user = try requireAuthenticatedUser(req)
    guard let userID = user.id else {
        throw Abort(.internalServerError)
    }

    return .init(userId: userID, username: user.username, role: user.role)
}

func logout(_ req: Request) async throws -> HTTPStatus {
    guard let header = req.headers.bearerAuthorization else {
        throw Abort(.unauthorized)
    }

    let tokenHash = sha256Hex(header.token)
    try await APIToken.query(on: req.db)
        .filter(\.$tokenHash == tokenHash)
        .delete()

    return .ok
}
