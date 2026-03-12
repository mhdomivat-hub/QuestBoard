import Vapor
import Fluent

private func isBootstrapAdminUsernameForProfile(_ username: String) -> Bool {
    let bootstrap = (Environment.get("BOOTSTRAP_ADMIN_USERNAME") ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bootstrap.isEmpty else { return false }
    return username.caseInsensitiveCompare(bootstrap) == .orderedSame
}

private func normalizeRequestedUsername(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func validateRequestedUsername(_ username: String) throws {
    guard !username.isEmpty else {
        throw Abort(.badRequest, reason: "Username required")
    }
    guard username.count <= 64 else {
        throw Abort(.badRequest, reason: "Username too long")
    }
}

private func usernameRequestToSummary(_ item: UsernameChangeRequestModel) throws -> UsernameChangeRequestSummaryDTO {
    guard let requestID = item.id else {
        throw Abort(.internalServerError)
    }

    return .init(
        id: requestID,
        desiredUsername: item.desiredUsername,
        status: item.status,
        createdAt: item.createdAt,
        reviewedAt: item.reviewedAt
    )
}

private func usernameRequestToAdminDTO(_ item: UsernameChangeRequestModel) throws -> AdminUsernameChangeRequestDTO {
    guard let requestID = item.id else {
        throw Abort(.internalServerError)
    }
    let user = item.user
    guard let userID = user.id else {
        throw Abort(.internalServerError)
    }

    return .init(
        id: requestID,
        userId: userID,
        currentUsername: item.currentUsername,
        desiredUsername: item.desiredUsername,
        status: item.status,
        createdAt: item.createdAt,
        reviewedAt: item.reviewedAt
    )
}

func getAccount(_ req: Request) async throws -> AccountResponseDTO {
    let user = try requireNonGuestUser(req)
    guard let userID = user.id else {
        throw Abort(.internalServerError)
    }

    let pendingRequest = try await UsernameChangeRequestModel.query(on: req.db)
        .filter(\.$user.$id == userID)
        .filter(\.$status == .pending)
        .sort(\.$createdAt, .descending)
        .first()

    return .init(
        userId: userID,
        username: user.username,
        role: user.role,
        pendingUsernameChangeRequest: try pendingRequest.map(usernameRequestToSummary)
    )
}

func changeOwnPassword(_ req: Request) async throws -> HTTPStatus {
    let user = try requireNonGuestUser(req)
    let body = try req.content.decode(ChangeOwnPasswordRequestDTO.self)

    guard try Bcrypt.verify(body.currentPassword, created: user.passwordHash) else {
        throw Abort(.unauthorized, reason: "Current password invalid")
    }
    guard body.newPassword.count >= 8 else {
        throw Abort(.badRequest, reason: "Password too short")
    }
    guard let userID = user.id else {
        throw Abort(.internalServerError)
    }

    try await req.db.transaction { db in
        guard let freshUser = try await User.find(userID, on: db) else {
            throw Abort(.notFound)
        }

        freshUser.passwordHash = try hashPassword(body.newPassword)
        try await freshUser.save(on: db)

        try await APIToken.query(on: db)
            .filter(\.$user.$id == userID)
            .delete()
    }

    await recordAuditEvent(
        on: req,
        actor: user,
        action: "account.password.change",
        entityType: "user",
        entityId: userID
    )

    return .ok
}

func requestOwnUsernameChange(_ req: Request) async throws -> UsernameChangeRequestSummaryDTO {
    let user = try requireNonGuestUser(req)
    guard let userID = user.id else {
        throw Abort(.internalServerError)
    }
    guard !isBootstrapAdminUsernameForProfile(user.username) else {
        throw Abort(.forbidden, reason: "Bootstrap admin username cannot be changed")
    }

    let body = try req.content.decode(CreateUsernameChangeRequestDTO.self)
    let desiredUsername = normalizeRequestedUsername(body.desiredUsername)
    try validateRequestedUsername(desiredUsername)

    guard desiredUsername.caseInsensitiveCompare(user.username) != .orderedSame else {
        throw Abort(.badRequest, reason: "Username unchanged")
    }

    let existingPending = try await UsernameChangeRequestModel.query(on: req.db)
        .filter(\.$user.$id == userID)
        .filter(\.$status == .pending)
        .first()
    if existingPending != nil {
        throw Abort(.conflict, reason: "Pending username change request already exists")
    }

    let usernameExists = try await User.query(on: req.db)
        .filter(\.$username == desiredUsername)
        .first() != nil
    if usernameExists {
        throw Abort(.conflict, reason: "Username already exists")
    }

    let item = UsernameChangeRequestModel(
        userID: userID,
        currentUsername: user.username,
        desiredUsername: desiredUsername,
        status: .pending
    )
    try await item.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: user,
        action: "account.username_change.request",
        entityType: "username_change_request",
        entityId: item.id,
        details: "desiredUsername=\(desiredUsername)"
    )

    return try usernameRequestToSummary(item)
}

func listPendingUsernameChangeRequests(_ req: Request) async throws -> [AdminUsernameChangeRequestDTO] {
    _ = try requireSuperAdmin(req)

    let items = try await UsernameChangeRequestModel.query(on: req.db)
        .filter(\.$status == .pending)
        .sort(\.$createdAt, .descending)
        .with(\.$user)
        .all()

    return try items.map(usernameRequestToAdminDTO)
}

func approveUsernameChangeRequest(_ req: Request) async throws -> AdminUsernameChangeRequestDTO {
    let actor = try requireSuperAdmin(req)
    guard let requestID = req.parameters.get("requestID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    let updated = try await req.db.transaction { db in
        guard let item = try await UsernameChangeRequestModel.query(on: db)
            .filter(\.$id == requestID)
            .with(\.$user)
            .first()
        else {
            throw Abort(.notFound)
        }

        guard item.status == .pending else {
            throw Abort(.badRequest, reason: "Request not pending")
        }

        let desiredUsername = normalizeRequestedUsername(item.desiredUsername)
        let usernameExists = try await User.query(on: db)
            .filter(\.$username == desiredUsername)
            .filter(\.$id != item.$user.id)
            .first() != nil
        if usernameExists {
            throw Abort(.conflict, reason: "Username already exists")
        }

        let user = item.user
        user.username = desiredUsername
        try await user.save(on: db)

        item.currentUsername = desiredUsername
        item.desiredUsername = desiredUsername
        item.status = .approved
        item.$reviewedBy.id = actor.id
        item.reviewedAt = Date()
        try await item.save(on: db)
        try await item.$user.load(on: db)

        return item
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "account.username_change.approve",
        entityType: "username_change_request",
        entityId: updated.id,
        details: "desiredUsername=\(updated.desiredUsername)"
    )

    return try usernameRequestToAdminDTO(updated)
}

func rejectUsernameChangeRequest(_ req: Request) async throws -> AdminUsernameChangeRequestDTO {
    let actor = try requireSuperAdmin(req)
    guard let requestID = req.parameters.get("requestID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    guard let item = try await UsernameChangeRequestModel.query(on: req.db)
        .filter(\.$id == requestID)
        .with(\.$user)
        .first()
    else {
        throw Abort(.notFound)
    }

    guard item.status == .pending else {
        throw Abort(.badRequest, reason: "Request not pending")
    }

    item.status = .rejected
    item.$reviewedBy.id = actor.id
    item.reviewedAt = Date()
    try await item.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "account.username_change.reject",
        entityType: "username_change_request",
        entityId: item.id,
        details: "desiredUsername=\(item.desiredUsername)"
    )

    return try usernameRequestToAdminDTO(item)
}
