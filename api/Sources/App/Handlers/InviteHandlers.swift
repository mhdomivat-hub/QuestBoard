import Vapor
import Fluent

private func appBaseUrl() -> String {
    (Environment.get("APP_BASE_URL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

private func buildInviteLink(token: String) -> String {
    let baseUrl = appBaseUrl()
    return baseUrl.isEmpty ? "/register?token=\(token)" : "\(baseUrl)/register?token=\(token)"
}

private func inviteStatus(invite: Invite, now: Date = Date()) -> String {
    if invite.revokedAt != nil { return "REVOKED" }
    if invite.useCount >= invite.maxUses { return "USED" }
    if invite.expiresAt <= now { return "EXPIRED" }
    return "OPEN"
}

private func inviteToResponse(_ invite: Invite) throws -> InviteResponseDTO {
    guard
        let inviteID = invite.id,
        let role = User.Role(rawValue: invite.role)
    else {
        throw Abort(.internalServerError, reason: "Invalid invite record")
    }
    return .init(
        id: inviteID,
        role: role,
        status: inviteStatus(invite: invite),
        token: invite.rawToken,
        inviteLink: invite.rawToken.map(buildInviteLink(token:)),
        maxUses: invite.maxUses,
        useCount: invite.useCount,
        remainingUses: max(0, invite.maxUses - invite.useCount),
        expiresAt: invite.expiresAt,
        createdAt: invite.createdAt,
        usedAt: invite.usedAt,
        revokedAt: invite.revokedAt,
        createdByUsername: invite.createdBy.username
    )
}

func listInvites(_ req: Request) async throws -> [InviteResponseDTO] {
    let _ = try requireAdminOrSuperAdmin(req)
    let limit = min(max((try? req.query.get(Int.self, at: "limit")) ?? 200, 1), 500)
    let offset = max((try? req.query.get(Int.self, at: "offset")) ?? 0, 0)

    let items = try await Invite.query(on: req.db)
        .with(\.$createdBy)
        .sort(\.$createdAt, .descending)
        .range(offset..<(offset + limit))
        .all()

    return try items.map(inviteToResponse)
}

func createInvite(_ req: Request) async throws -> CreateInviteResponseDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    let body = try req.content.decode(CreateInviteRequestDTO.self)

    let role: User.Role = .guest

    let expiresInHours = min(max(body.expiresInHours ?? 168, 1), 24 * 30)
    let maxUses = min(max(body.maxUses ?? 1, 1), 10_000)
    let now = Date()
    let expiresAt = now.addingTimeInterval(TimeInterval(expiresInHours * 3600))

    guard let actorID = actor.id else {
        throw Abort(.internalServerError)
    }

    let rawToken = generateOpaqueToken()
    let tokenHash = sha256Hex(rawToken)

    let invite = Invite(
        tokenHash: tokenHash,
        rawToken: rawToken,
        role: role.rawValue,
        maxUses: maxUses,
        createdByUserID: actorID,
        expiresAt: expiresAt,
        createdAt: now
    )
    try await invite.save(on: req.db)
    try await invite.$createdBy.load(on: req.db)

    let inviteLink = buildInviteLink(token: rawToken)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "admin.invite.create",
        entityType: "invite",
        entityId: invite.id,
        details: "role=\(role.rawValue);expiresInHours=\(expiresInHours);maxUses=\(maxUses)"
    )

    return .init(
        invite: try inviteToResponse(invite),
        token: rawToken,
        inviteLink: inviteLink
    )
}

func revokeInvite(_ req: Request) async throws -> InviteResponseDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let invite = try await Invite.find(req.parameters.get("inviteID"), on: req.db) else {
        throw Abort(.notFound)
    }

    if invite.useCount < invite.maxUses && invite.revokedAt == nil {
        invite.revokedAt = Date()
        invite.rawToken = nil
        try await invite.save(on: req.db)
        await recordAuditEvent(
            on: req,
            actor: actor,
            action: "admin.invite.revoke",
            entityType: "invite",
            entityId: invite.id
        )
    }

    try await invite.$createdBy.load(on: req.db)
    return try inviteToResponse(invite)
}

func registerByInvite(_ req: Request) async throws -> RegisterByInviteResponseDTO {
    try await enforceInviteRegisterRateLimit(req)
    let body = try req.content.decode(RegisterByInviteRequestDTO.self)
    let username = body.username.trimmingCharacters(in: .whitespacesAndNewlines)
    let password = body.password

    guard !username.isEmpty else {
        throw Abort(.badRequest, reason: "Username required")
    }
    guard password.count >= 8 else {
        throw Abort(.badRequest, reason: "Password too short")
    }

    let tokenHash = sha256Hex(body.token)
    guard let invite = try await Invite.query(on: req.db)
        .filter(\.$tokenHash == tokenHash)
        .with(\.$createdBy)
        .first()
    else {
        throw Abort(.badRequest, reason: "Invalid invite token")
    }

    let now = Date()
    if invite.revokedAt != nil {
        throw Abort(.badRequest, reason: "Invite revoked")
    }
    if invite.useCount >= invite.maxUses {
        throw Abort(.badRequest, reason: "Invite usage limit reached")
    }
    if invite.expiresAt <= now {
        throw Abort(.badRequest, reason: "Invite expired")
    }

    guard let role = User.Role(rawValue: invite.role) else {
        throw Abort(.internalServerError, reason: "Invalid invite role")
    }

    let usernameExists = try await User.query(on: req.db)
        .filter(\.$username == username)
        .first() != nil
    if usernameExists {
        throw Abort(.conflict, reason: "Username already exists")
    }

    let user = User(username: username, passwordHash: try hashPassword(password), role: role)
    try await user.save(on: req.db)

    guard let userID = user.id else {
        throw Abort(.internalServerError)
    }
    invite.useCount += 1
    if invite.usedAt == nil {
        invite.usedAt = now
    }
    invite.$usedBy.id = userID
    if invite.useCount >= invite.maxUses {
        invite.rawToken = nil
    }
    try await invite.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: user,
        action: "auth.register.invite",
        entityType: "user",
        entityId: user.id,
        details: "inviteId=\(invite.id?.uuidString ?? "")"
    )

    return .init(userId: userID, username: user.username, role: user.role)
}
