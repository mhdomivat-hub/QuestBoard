import Vapor
import Fluent

func requestPasswordReset(_ req: Request) async throws -> Response {
    try await enforcePasswordResetRequestRateLimit(req)
    let body = try req.content.decode(PasswordResetRequestCreateDTO.self)

    if let user = try await User.query(on: req.db)
        .filter(\.$username == body.username)
        .first(),
       let userID = user.id
    {
        let existingPending = try await PasswordResetRequestModel.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$status == .pending)
            .first()

        if existingPending == nil {
            let reset = PasswordResetRequestModel(userID: userID, status: .pending, note: body.note)
            try await reset.save(on: req.db)
        }
    }

    return Response(status: .ok)
}

func listPendingPasswordResets(_ req: Request) async throws -> [PasswordResetAdminListItemDTO] {
    _ = try requireAdminOrSuperAdmin(req)

    let requestedLimit = req.query[Int.self, at: "limit"] ?? 100
    let limit = max(1, min(requestedLimit, 500))
    let requestedOffset = req.query[Int.self, at: "offset"] ?? 0
    let offset = max(0, requestedOffset)

    let items = try await PasswordResetRequestModel.query(on: req.db)
        .filter(\.$status == .pending)
        .sort(\.$createdAt, .descending)
        .limit(limit)
        .offset(offset)
        .with(\.$user)
        .all()

    return items.compactMap { item in
        guard let id = item.id else { return nil }
        return PasswordResetAdminListItemDTO(
            id: id,
            username: item.user.username,
            status: item.status,
            createdAt: item.createdAt,
            note: item.note
        )
    }
}

func approvePasswordReset(_ req: Request) async throws -> PasswordResetApproveResponseDTO {
    let admin = try requireAdminOrSuperAdmin(req)
    guard let requestID = req.parameters.get("requestID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    let response = try await req.db.transaction { db in
        guard let resetReq = try await PasswordResetRequestModel.find(requestID, on: db) else {
            throw Abort(.notFound)
        }

        guard resetReq.status == .pending else {
            throw Abort(.badRequest, reason: "Reset request not pending")
        }

        resetReq.status = .approved
        resetReq.$approvedBy.id = admin.id
        resetReq.approvedAt = Date()
        try await resetReq.save(on: db)

        let rawToken = generateOpaqueToken()
        let tokenHash = sha256Hex(rawToken)

        let ttlHours = Int(Environment.get("RESET_TOKEN_TTL_HOURS") ?? "2") ?? 2
        let expiresAt = Date().addingTimeInterval(TimeInterval(60 * 60 * ttlHours))

        let token = PasswordResetToken(requestID: requestID, tokenHash: tokenHash, expiresAt: expiresAt)
        try await token.save(on: db)

        let appBaseURL = Environment.get("APP_BASE_URL") ?? ""
        let baseURL = appBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return PasswordResetApproveResponseDTO(
            requestId: requestID,
            resetLink: "\(baseURL)/reset-password?token=\(rawToken)",
            expiresAt: expiresAt
        )
    }

    await recordAuditEvent(
        on: req,
        actor: admin,
        action: "password_reset.approve",
        entityType: "password_reset_request",
        entityId: requestID
    )

    return response
}

func rejectPasswordReset(_ req: Request) async throws -> Response {
    let admin = try requireAdminOrSuperAdmin(req)
    guard let requestID = req.parameters.get("requestID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    guard let item = try await PasswordResetRequestModel.find(requestID, on: req.db) else {
        throw Abort(.notFound)
    }

    if item.status == .pending {
        item.status = .rejected
        try await item.save(on: req.db)
        await recordAuditEvent(
            on: req,
            actor: admin,
            action: "password_reset.reject",
            entityType: "password_reset_request",
            entityId: requestID
        )
    }

    return Response(status: .ok)
}

func confirmPasswordReset(_ req: Request) async throws -> Response {
    try await enforcePasswordResetConfirmRateLimit(req)
    let body = try req.content.decode(PasswordResetConfirmDTO.self)
    guard body.newPassword.count >= 8 else {
        throw Abort(.badRequest, reason: "Password too short")
    }

    let tokenHash = sha256Hex(body.token)
    let now = Date()

    try await req.db.transaction { db in
        guard let token = try await PasswordResetToken.query(on: db)
            .filter(\.$tokenHash == tokenHash)
            .first()
        else {
            throw Abort(.badRequest, reason: "Invalid token")
        }

        guard token.usedAt == nil else {
            throw Abort(.badRequest, reason: "Token already used")
        }

        guard token.expiresAt > now else {
            throw Abort(.badRequest, reason: "Token expired")
        }

        let resetReq = try await token.$request.get(on: db)
        guard resetReq.status == .approved else {
            throw Abort(.badRequest, reason: "Reset request not approved")
        }

        let user = try await resetReq.$user.get(on: db)
        user.passwordHash = try hashPassword(body.newPassword)
        try await user.save(on: db)

        token.usedAt = now
        try await token.save(on: db)

        resetReq.status = .completed
        try await resetReq.save(on: db)
    }

    return Response(status: .ok)
}
