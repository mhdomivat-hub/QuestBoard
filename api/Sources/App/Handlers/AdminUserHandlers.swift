import Vapor
import Fluent

private func isBootstrapAdminUsername(_ username: String) -> Bool {
    let bootstrap = (Environment.get("BOOTSTRAP_ADMIN_USERNAME") ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bootstrap.isEmpty else { return false }
    return username.caseInsensitiveCompare(bootstrap) == .orderedSame
}

private func canActorAssignRole(actor: User, target: User, newRole: User.Role) -> Bool {
    switch actor.role {
    case .superAdmin:
        return true
    case .admin:
        let editableRoles: Set<User.Role> = [.guest, .member]
        return editableRoles.contains(target.role) && editableRoles.contains(newRole)
    case .guest, .member:
        return false
    }
}

func listAdminUsers(_ req: Request) async throws -> [AdminUserDTO] {
    let _ = try requireAdminOrSuperAdmin(req)
    let users = try await User.query(on: req.db)
        .sort(\.$username, .ascending)
        .all()

    return try users.map { user in
        guard let userID = user.id else {
            throw Abort(.internalServerError)
        }
        return .init(
            id: userID,
            username: user.username,
            role: user.role,
            isRoleImmutable: isBootstrapAdminUsername(user.username)
        )
    }
}

func updateUserRole(_ req: Request) async throws -> AdminUserDTO {
    let actor = try requireAdminOrSuperAdmin(req)

    let body = try req.content.decode(UpdateUserRoleRequestDTO.self)
    guard let target = try await User.find(req.parameters.get("userID"), on: req.db) else {
        throw Abort(.notFound)
    }
    guard let targetID = target.id else {
        throw Abort(.internalServerError)
    }

    let oldRole = target.role
    let newRole = body.role
    if oldRole == newRole {
        return .init(
            id: targetID,
            username: target.username,
            role: target.role,
            isRoleImmutable: isBootstrapAdminUsername(target.username)
        )
    }

    if isBootstrapAdminUsername(target.username) {
        throw Abort(.forbidden, reason: "Bootstrap admin role is immutable")
    }

    guard canActorAssignRole(actor: actor, target: target, newRole: newRole) else {
        throw Abort(.forbidden, reason: "Role change not allowed for your role level")
    }

    if oldRole == .superAdmin, newRole != .superAdmin {
        let superAdminCount = try await User.query(on: req.db)
            .filter(\.$role == .superAdmin)
            .count()
        if superAdminCount <= 1 {
            throw Abort(.badRequest, reason: "Cannot demote the last superAdmin")
        }
        if actor.id == targetID {
            throw Abort(.badRequest, reason: "Cannot self-demote superAdmin account")
        }
    }

    target.role = newRole
    try await target.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "admin.user.role.update",
        entityType: "user",
        entityId: target.id,
        details: "from=\(oldRole.rawValue);to=\(newRole.rawValue)"
    )

    return .init(
        id: targetID,
        username: target.username,
        role: target.role,
        isRoleImmutable: isBootstrapAdminUsername(target.username)
    )
}

func deleteAdminUser(_ req: Request) async throws -> HTTPStatus {
    let actor = try requireAdminOrSuperAdmin(req)
    guard actor.role == .superAdmin else {
        throw Abort(.forbidden, reason: "Only superAdmin may delete users")
    }

    guard let target = try await User.find(req.parameters.get("userID"), on: req.db) else {
        throw Abort(.notFound)
    }
    guard let targetID = target.id else {
        throw Abort(.internalServerError)
    }

    if actor.id == targetID {
        throw Abort(.badRequest, reason: "Cannot delete own account")
    }

    if target.role == .superAdmin {
        let superAdminCount = try await User.query(on: req.db)
            .filter(\.$role == .superAdmin)
            .count()
        if superAdminCount <= 1 {
            throw Abort(.badRequest, reason: "Cannot delete the last superAdmin")
        }
    }

    let targetUsername = target.username
    let targetRole = target.role.rawValue
    try await target.delete(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "admin.user.delete",
        entityType: "user",
        entityId: targetID,
        details: "username=\(targetUsername);role=\(targetRole)"
    )

    return .noContent
}
